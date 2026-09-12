// --------------------------------------------------------------------------
// Sealed-hardware host (main thread).
//
// Instantiates TWO wasm modules over ONE shared WebAssembly.Memory:
//   - machine-video.wasm : the sealed hardware (render pipeline). Exports hw*.
//   - demo.wasm          : the open ZigOS + effects + scene. Exports boot/frame.
//
// The machine calls back into the demo via env.hblDispatch at each HBL point.
// Per frame: machine.hwClear() -> demo.frame(dt) -> machine.hwRenderPlane(i) per
// enabled plane -> blit the physical framebuffer to canvas[i].
//
// Audio is unchanged: the standalone audio.wasm still runs on the AudioWorklet
// thread; JS mirrors its YM regs / player mode / scopes into the demo module.
// --------------------------------------------------------------------------

// MUST match machine/sdk/memmap.zig SHARED_PAGES. v1.3: 2 MiB cart window + 1 MiB
// VRAM + PFB + the 2 MiB ROM window. Raising it is a BREAKING change for carts
// packed against the old value — a cart declares the imported memory's
// initial/max, so it refuses a memory bigger than its max. Repack with
// tools/mkdisks.sh (node apps/disk_check.mjs catches it).
const SHARED_PAGES = 112;

// Cache-bust every wasm fetch with the page-load time, so a rebuilt .wasm is
// always picked up on reload (mobile browsers cache the 1.9 MB blob hard and
// otherwise keep serving the stale one). See notes/zigmachine-workflow-cache.
const BUST = "?t=" + Date.now();

const memory = new WebAssembly.Memory({ initial: SHARED_PAGES, maximum: SHARED_PAGES });

const text_decoder = new TextDecoder();
let console_log_buffer = "";

let machine = null;   // machine-video.wasm exports
let rom = null;       // rom.wasm exports — the ROM chip's flat app-facing ABI
let demo = null;      // demo.wasm exports
let demoImports = null; // env wired to machine + host — reused on cart swap
let swapping = false; // a cartridge swap (disk boot) is in flight
let diskApp = false; // GEM was booted for an app-disk -> FLOPPY opens the app
let diskDirSet = false; // handed GEM the FAT directory for the FLOPPY window yet
const text_encoder = new TextEncoder();
let requestId = null;

// --- console/env imports shared by both modules ---
function consoleWrite(ptr, len) {
    const arr8 = new Uint8Array(memory.buffer, ptr, len);
    console_log_buffer += text_decoder.decode(arr8);
}
function consoleFlush() {
    if (console_log_buffer.length) { console.log(console_log_buffer); console_log_buffer = ""; }
}
function throwError(ptr, len) {
    const arr8 = new Uint8Array(memory.buffer, ptr, len);
    throw new Error(text_decoder.decode(arr8));
}
function consoleLogJS(ptr, len) {
    console.log(text_decoder.decode(new Uint8Array(memory.buffer, ptr, len)));
}

// --------------------------------------------------------------------------
// Floppy drive: mount a ZigMachine disk image (docs/FLOPPY_DISK.md), verify the
// executable boot sector ($1234 checksum, ST-style), and return the boot cart's
// wasm bytes. v1 reads the whole image up front; block streaming comes later.
// --------------------------------------------------------------------------
let mountedDisk = null; // { buf, files: {NAME: {start,len}} } — the currently inserted disk

async function mountDisk(url) {
    const buf = new Uint8Array(await fetch(url + BUST).then((r) => r.arrayBuffer()));
    // Format v2: block 0 is an EXECUTABLE boot sector — a wasm module (\0asm), with the
    // descriptor at $400 (see docs/FLOPPY_DISK.md). v1 has the "ZMDISK" descriptor at $0.
    if (buf[0] === 0x00 && buf[1] === 0x61 && buf[2] === 0x73 && buf[3] === 0x6d)
        return mountDiskV2(url, buf);
    if (String.fromCharCode(...buf.subarray(0, 6)) !== "ZMDISK")
        throw new Error("not a ZigMachine disk: " + url);
    // Executability (ST-style): boot sector's 256 big-endian words sum to 0x1234 for
    // a BOOTABLE disk; a DATA disk sums to 0x0000 and boots the OS (GEM) instead.
    let sum = 0;
    for (let i = 0; i < 256; i++) sum = (sum + ((buf[2 * i] << 8) | buf[2 * i + 1])) & 0xFFFF;
    const bootable = sum === 0x1234;
    if (!bootable && sum !== 0x0000)
        throw new Error("disk corrupt: boot-sector checksum 0x" + sum.toString(16));
    const dv = new DataView(buf.buffer);
    const blockSize = dv.getUint16(0x08, true);
    const bootBlock = dv.getUint32(0x0e, true);
    const bootLen = dv.getUint32(0x12, true);
    const title = text_decoder.decode(buf.subarray(0x200, 0x240)).replace(/\0.*$/, "");
    // FAT: flat file table at $300 (see docs/FLOPPY_DISK.md).
    const nFiles = dv.getUint16(0x2e4, true);
    const files = {};
    for (let i = 0; i < nFiles; i++) {
        const e = 0x300 + i * 32;
        const name = text_decoder.decode(buf.subarray(e, e + 16)).replace(/\0.*$/, "");
        files[name] = { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true), type: buf[e + 0x18] };
    }
    mountedDisk = { buf, files };
    const start = bootBlock * blockSize;
    console.log(`Mounted "${title}" — ${bootable ? "bootable" : "DATA disk"}, ${nFiles} FAT file(s)`);
    return { bootable, cart: bootable ? buf.buffer.slice(start, start + bootLen) : null };
}

// Format v2: the 1 KB boot sector IS an executable wasm module (its 512 big-endian
// words sum to $1234). We hand the loader those 1 KB to instantiate FIRST; the boot
// program then asks (pollCartRequest() == 2) to CHAINLOAD the real cart, whose pointer
// lives in the descriptor at $400. Regions: boot [0,1K) · descriptor [1K,2K) · FAT
// [2K,3K) · data [3K,). Streaming stays 512-byte blocks.
function mountDiskV2(url, buf) {
    let sum = 0;
    for (let i = 0; i < 512; i++) sum = (sum + ((buf[2 * i] << 8) | buf[2 * i + 1])) & 0xFFFF;
    const bootable = sum === 0x1234; // else: not executable -> treat as a data disk (GEM)
    const dv = new DataView(buf.buffer);
    if (String.fromCharCode(...buf.subarray(0x400, 0x406)) !== "ZMDISK")
        throw new Error("v2 disk: bad descriptor magic");
    const cartBlock = dv.getUint32(0x408, true);
    const cartLen = dv.getUint32(0x40c, true);
    const title = text_decoder.decode(buf.subarray(0x410, 0x450)).replace(/\0.*$/, "");
    const nFiles = dv.getUint16(0x4f4, true);
    const files = {}; // FAT at $800, same 32-byte entries as v1
    for (let i = 0; i < nFiles; i++) {
        const e = 0x800 + i * 32;
        const name = text_decoder.decode(buf.subarray(e, e + 16)).replace(/\0.*$/, "");
        files[name] = { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true), type: buf[e + 0x18] };
    }
    const cartStart = cartBlock * 512;
    const date = dv.getUint32(0x4f0, true); // descriptor $4F0 YYYYMMDD (disk build date)
    mountedDisk = { buf, files, date, v2: true, chainCart: { start: cartStart, len: cartLen } };
    console.log(`Mounted v2 "${title}" — ${bootable ? "executable boot sector" : "data disk"}, ${nFiles} FAT file(s)`);
    // Run the 1 KB boot sector first; it chainloads the cart (swapCart req 2).
    return { bootable, v2: true, cart: bootable ? buf.buffer.slice(0, 1024) : null };
}

// Read a named file from the mounted disk's FAT (streaming a whole file for now).
function diskFile(name) {
    if (!mountedDisk || !mountedDisk.files[name]) return null;
    const { start, len } = mountedDisk.files[name];
    return mountedDisk.buf.subarray(start, start + len);
}

// Disk DRIVE: copy one 512-byte block from the mounted disk into shared memory at
// dstOff (a raw wasm address = byte offset). The machine never holds the disk — it
// asks the drive for a block at a time (docs/FLOPPY_DISK.md "Drive ABI"). Returns
// bytes copied (0 = past end / no disk).
function diskReadBlock(block, dstOff) {
    if (!mountedDisk) return 0;
    const start = block * 512;
    const src = mountedDisk.buf.subarray(start, start + 512);
    if (src.length === 0) return 0;
    new Uint8Array(memory.buffer, dstOff, src.length).set(src);
    return src.length;
}


// Swap the running cartridge: the menu launcher asks to boot a scene's floppy
// (req 1 + a tag), a scene asks to return to the menu (req -1). We mount the disk
// and re-instantiate the demo module over the SAME shared memory (audio untouched);
// scenes skip the boot ROM. The render loop keeps drawing the old cart until this
// resolves, so there's no black frame.
const badCarts = new Set(); // disks that failed to start; do not retry in a loop

async function swapCart(req) {
    if (swapping) return;
    swapping = true;
    let url = null;
    try {
        // req 2 = CHAINLOAD (format v2): the boot sector is done — instantiate this
        // disk's cart (pointer in the descriptor, already parsed) over the same memory.
        if (req === 2 && mountedDisk && mountedDisk.chainCart) {
            beepStop(); // silence the boot-sector tone before the cart takes over
            const { start, len } = mountedDisk.chainCart;
            const bytes = mountedDisk.buf.buffer.slice(start, start + len);
            demo = (await instantiateCart(bytes, "the chainloaded cart")).instance.exports;
            machine.hwInit();
            demo.boot();
            if (demo.skipBoot) demo.skipBoot(); // straight into the cart (boot sector already showed)
            swapping = false;
            return;
        }
        if (req === 1) {
            const tag = text_decoder.decode(
                new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
            url = "demo-" + tag + ".zmd";
        } else {
            url = "demo.zmd"; // back to the menu
        }
        if (badCarts.has(url)) return; // already failed once: do not retry every frame
        const { bootable, cart } = await mountDisk(url);
        // A data disk (e.g. ST Replay) isn't bootable — bring up GEM, which opens
        // its app + reads its files. A bootable disk runs its own cart.
        const bytes = bootable ? cart : await fetch("demo-gem.wasm" + BUST).then((r) => r.arrayBuffer());
        demo = (await instantiateCart(bytes, url)).instance.exports;
        machine.hwInit();
        demo.boot();
        if (req === 1) demo.skipBoot(); // scene or data-disk→GEM: straight in (no boot ROM)
        diskApp = !bootable;            // data disk → GEM's FLOPPY opens its app
        diskDirSet = false;            // re-hand GEM the new disk's FAT listing
    } catch (e) {
        // The running cart keeps going. Without remembering the failure the menu
        // would ask for this disk again next frame, and every frame after —
        // which reads as a freeze rather than as an error.
        if (url) badCarts.add(url);
        console.error("cart swap failed:", e);
    }
    swapping = false;
}

// Any import a cart asks for that this host does not implement becomes a LOGGED
// NO-OP instead of a LinkError. The alternative has now bitten three times: add
// or retire one name and every cart built on the other side of the change dies
// at instantiation, which surfaces as a black screen or a boot loop. A missing
// import should cost that one feature, not the machine.
function tolerantEnv(env) {
    return new Proxy(env, {
        has: () => true,
        get(target, key) {
            if (key in target) return target[key];
            if (typeof key !== "string") return undefined;
            console.warn(`host: cart imports "${key}", which this loader does not implement — stubbed`);
            return () => 0;
        },
    });
}

// Tell the machine where this cart's static data + stack end, so hwRamFree()
// can answer truthfully for it (see machine/sdk/memmap.zig REG_CART_HIGH). Only
// the host can know: the number is baked into the cart binary by the linker.
// Every failure here is non-fatal — an undeclared high-water makes hwRamFree()
// report 0 ("take nothing"), which is the safe answer, and never blocks a boot.
function declareCartRam(bytes, what) {
    if (!machine || !machine.hwSetCartHigh) return; // pre-1.2.0 machine
    if (!globalThis.ZMRam) {
        console.warn("wasm_hiwater.js not loaded — hwRamFree() will report 0");
        return;
    }
    try {
        const ram = globalThis.ZMRam.cartRam(bytes);
        machine.hwSetCartHigh(ram.known ? ram.high : 0);
        if (ram.over) {
            console.error(`${what}: OVERRUNS the cart RAM window — data+stack end at ` +
                          `0x${ram.high.toString(16)}, past 0x${globalThis.ZMRam.CART_RAM_TOP.toString(16)}. ` +
                          `It will corrupt the video region. Shrink its statics.`);
        } else if (ram.known) {
            console.log(`${what}: RAM ${(ram.used / 1024) | 0} KB used, ` +
                        `${(ram.free / 1024) | 0} KB free of 2048 KB`);
        }
    } catch (e) {
        console.warn(`Cannot measure ${what}'s RAM high-water: ${e.message}`);
        machine.hwSetCartHigh(0);
    }
}

// Instantiate a cart, turning a link failure into a REPORT rather than a freeze.
// A disk packed against an older host import surface fails here; saying which
// import is missing beats a black screen.
async function instantiateCart(bytes, what) {
    try {
        const mod = await WebAssembly.instantiate(bytes, demoImports);
        declareCartRam(bytes, what);
        return mod;
    } catch (e) {
        console.error(`Cannot start ${what}: ${e.message}`);
        alert(`ZigMachine: cannot start ${what}.\n\n${e.message}\n\n` +
              `The disk was probably packed against an older host — rebuild it with tools/mkdisk.py.`);
        throw e;
    }
}

// --------------------------------------------------------------------------
// Instantiate the sealed machine, then the demo (wired to it via shared memory).
// --------------------------------------------------------------------------
async function boot() {
    // The machine's only host import (besides memory) is hblDispatch, which we
    // route back into the demo. The demo instance is assigned before the render
    // loop starts, so the closure is safe.
    const machineImports = {
        env: {
            memory,
            hblDispatch: (id, plane, line, x) => demo.hblDispatch(id, plane, line, x),
        },
    };
    const machineMod = await WebAssembly.instantiateStreaming(fetch("machine-video.wasm" + BUST), machineImports);
    machine = machineMod.instance.exports;
    console.log("Sealed machine-video.wasm loaded, HW version 0x" + machine.hwVersion().toString(16));

    // The ROM CHIP (Phase 2). Its own module in its own RAM window, linked against
    // the machine exactly like a cart — it imports nothing but memory and two hw*
    // calls. An app's env is wired to its exports below, so an app links none of
    // GEM at all. Instantiation order is machine -> rom -> app, because each one
    // only ever imports from the ones before it.
    const romBytes = await fetch("rom.wasm" + BUST).then((r) => r.arrayBuffer());
    const romMod = await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    });
    rom = romMod.instance.exports;
    // Same declaration the cart gets, for the ROM's own window (REG_ROM_HIGH), so
    // hwRomRamFree() reports the truth instead of "no chip fitted".
    if (globalThis.ZMRam && machine.hwSetRomHigh) {
        const r = globalThis.ZMRam.romRam(romBytes);
        machine.hwSetRomHigh(r.known ? r.high : 0);
        console.log(`rom.wasm loaded — ROM RAM ${(r.used / 1024) | 0} KB used, ` +
                    `${(r.free / 1024) | 0} KB free of 2048 KB`);
    }

    // The demo imports the machine's hwVideoBase (to discover the region) + console.
    demoImports = {
        env: tolerantEnv({
            memory,
            jsConsoleLogWrite: consoleWrite,
            jsConsoleLogFlush: consoleFlush,
            jsThrowError: throwError,
            consoleLogJS: consoleLogJS,
            hwVideoBase: machine.hwVideoBase,
            hwBlit: machine.hwBlit, // sealed 2D blitter (execute COMMAND register)
            // RAM instructions: how much of the cart window is left (see
            // declareCartRam above, which tells the machine where this cart ends).
            hwRamBase: machine.hwRamBase,
            hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize,
            hwRamUsed: machine.hwRamUsed,
            hwRamFree: machine.hwRamFree,
            // The ROM chip's own window (Phase 2). No rom.wasm is fitted yet, so
            // these report 0 — which reads as "take nothing", the safe answer.
            hwRomRamBase: machine.hwRomRamBase,
            hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize,
            hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree,
            // The ROM chip's flat ABI (rom/sdk/rom.zig). Spread, not listed: the
            // ROM's exports ARE the surface, so a new entry point needs no host
            // change — and the host cannot silently omit one and leave an app
            // linking against a name that resolves to nothing.
            ...rom,
            beep: () => beep(), // boot-sector YM2149 tone (see novirus.zig)
            diskReadBlock: (block, dst) => diskReadBlock(block, dst), // drive: 512 B block -> RAM
            hostAudioStreamStart: (rate) => hostAudioStreamStart(rate), // begin ring streaming
            hostAudioFeed: (ptr, len) => hostAudioFeed(ptr, len), // append samples to the ring
            hostAudioStreamStop: () => hostAudioStreamStop(), // silence the ring
            // RETIRED imports, kept as no-ops. The env object is an ABI: every
            // cart ever built links against the names that existed when it was
            // packed, and a .zmd carries its wasm frozen inside it. Dropping a
            // name makes those disks fail to instantiate — so names leave the
            // surface as stubs, not as deletions. (Sample loading and playback
            // moved into the machine; see libs/zig/disk.zig.)
            audioPlay: () => {},
            audioStop: () => {},
            loadSample: () => {},
        }),
    };
    // What to boot: ?disk=X.zmd boots a cart from a ZigMachine disk image (see
    // docs/FLOPPY_DISK.md); ?demo=X.wasm loads a raw cart; default is demo.wasm.
    const params = new URLSearchParams(window.location.search);
    const diskUrl = params.get("disk");
    let demoMod;
    if (diskUrl) {
        const { bootable, cart } = await mountDisk(diskUrl);
        if (bootable) {
            demoMod = await instantiateCart(cart, diskUrl);
            console.log("Booted cart from disk:", diskUrl);
        } else {
            // A data disk isn't bootable — bring up the OS (GEM); the disk stays
            // mounted so GEM can open its app + read its files (e.g. SAMPLE.RAW).
            demoMod = await instantiateCart(
                await fetch("demo-gem.wasm" + BUST).then((r) => r.arrayBuffer()), "demo-gem.wasm");
            diskApp = true; // GEM's FLOPPY icon opens this disk's app
            console.log("Data disk inserted → booting GEM");
        }
    } else {
        const demoWasm = params.get("demo") || "demo.wasm";
        demoMod = await instantiateCart(
            await fetch(demoWasm + BUST).then((r) => r.arrayBuffer()), demoWasm);
        console.log("Open demo.wasm loaded");
    }
    demo = demoMod.instance.exports;

    machine.hwInit();
    demo.boot();

    // The sample is fed by the render loop once the running cart exposes its
    // buffer (after the boot ROM / immediately on a scene swap) — see the loop.
    start();
}


// --------------------------------------------------------------------------
// Render loop
// --------------------------------------------------------------------------
function start() {
    if (requestId) window.cancelAnimationFrame(requestId);

    const nb_planes = machine.hwPlanesNumber();
    const fb_width = machine.hwPhysWidth();
    const fb_height = machine.hwPhysHeight();
    const fb_len = fb_width * fb_height * 4;

    // The physical framebuffer lives at a fixed address in the shared memory,
    // which never grows (initial == max), so the view + ImageDatas are built ONCE.
    const pfbPtr = machine.hwPhysicalPtr();
    const fbView = new Uint8Array(memory.buffer, pfbPtr, fb_len);

    const contexts = [];
    const imageDatas = [];
    for (let p = 0; p < nb_planes; p++) {
        const canvas = document.getElementById(p);
        canvas.width = fb_width;    // match the raster (800x280); CSS scales to 800x560
        canvas.height = fb_height;
        const ctx = canvas.getContext("2d");
        contexts.push(ctx);
        imageDatas.push(ctx.createImageData(fb_width, fb_height));
    }

    // Track which plane canvases currently hold pixels, so a plane that goes
    // from enabled -> disabled (e.g. a multi-plane scene returning to the menu)
    // gets its stale layer cleared ONCE, instead of leaving the old image on top.
    const planeDirty = new Array(nb_planes).fill(false);

    let last_timestamp = 0;
    const loop = function (timestamp) {
        const elapsed_time = (timestamp - last_timestamp);
        last_timestamp = timestamp;
        document.title = "Sealed HW — FPS:" + (1000 / elapsed_time).toFixed(1);

        machine.hwClear();          // sealed: clear PFB + global HBL
        demo.frame(elapsed_time);   // open: scene draws into shared LFBs (+ overscan poke)

        // Cartridge swap: the menu boots a scene's floppy; a scene returns to the
        // menu. Async (fetch the disk) — the loop keeps running the current cart.
        if (!swapping && demo.pollCartRequest) {
            const req = demo.pollCartRequest();
            if (req !== 0) swapCart(req);
        }

        // Tell GEM whether an app-disk is inserted (idempotent; takes effect once
        // the cart is booted) so its FLOPPY icon opens the app.
        if (demo.insertDisk) demo.insertDisk(diskApp ? 1 : 0);

        // Hand GEM the mounted disk's FAT directory for its FLOPPY window (once
        // booted): per file a 16-byte name + 1 type byte (0=program, 1=data).
        if (!diskDirSet && diskApp && mountedDisk && demo.diskDirPtr &&
            demo.isBooted && demo.isBooted()) {
            const ENT = 25; // 16 name + 1 type + 4 size + 4 date (must match desktop.zig FILE_ENT)
            const names = Object.keys(mountedDisk.files).slice(0, 12);
            const dir = new Uint8Array(memory.buffer, demo.diskDirPtr(), names.length * ENT);
            dir.fill(0);
            const ddv = new DataView(dir.buffer, dir.byteOffset, dir.byteLength);
            names.forEach((name, i) => {
                dir.set(text_encoder.encode(name).subarray(0, 16), i * ENT);
                dir[i * ENT + 16] = mountedDisk.files[name].type & 0xff;
                ddv.setUint32(i * ENT + 17, (mountedDisk.files[name].len || 0) >>> 0, true); // size
                ddv.setUint32(i * ENT + 21, (mountedDisk.date || 0) >>> 0, true); // date YYYYMMDD
            });
            demo.setDiskFileCount(names.length);
            diskDirSet = true;
        }

        // Song bridge: the active scene requests a tune BY NAME (zigos.requestSong);
        // the host just plays it. No per-scene playlist lives here.
        if (audioCtx && demo.pollSongRequest && demo.pollSongRequest()) {
            playSongByName(text_decoder.decode(
                new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())));
        }

        for (let i = 0; i < nb_planes; i++) {
            if (demo.isPlaneEnabled(i)) {
                machine.hwRenderPlane(i);       // sealed: composite LFB[i] -> PFB
                imageDatas[i].data.set(fbView); // single copy PFB -> plane i's canvas
                contexts[i].putImageData(imageDatas[i], 0, 0);
                planeDirty[i] = true;
            } else if (planeDirty[i]) {
                contexts[i].clearRect(0, 0, fb_width, fb_height); // blank the stale layer
                planeDirty[i] = false;
            }
        }
        requestId = window.requestAnimationFrame(loop);
    };
    loop();
}

window.document.body.onload = boot;

// Sound on by default: browsers block audio until a user gesture, so resume on the
// FIRST interaction anywhere (click / key / touch) — no need to find the button.
(function () {
    let started = false;
    const go = (e) => {
        if (started) return;
        // The Sound-on button has its own handler (main); skip it here so a single
        // tap doesn't start audio on pointerdown AND toggle it back off on click.
        if (e && e.target && e.target.closest && e.target.closest('.sound_button')) return;
        started = true;
        startAudio();
        const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
    };
    for (const ev of ["pointerdown", "keydown", "touchstart"]) window.addEventListener(ev, go);
})();

// Keys with no printable codepoint, sent to demo.key() in the Unicode PRIVATE
// USE AREA so they can never be mistaken for typed text. Mirrored by the K_*
// constants in apps/zig/scenes/st_replay.zig — a keyboard-driven app (the ST
// Replay panel) needs the function keys the original was built around.
const KEY_CODES = {
    F1: 0xE001, F2: 0xE002, F3: 0xE003, F4: 0xE004, F5: 0xE005,
    F6: 0xE006, F7: 0xE007, F8: 0xE008, F9: 0xE009, F10: 0xE00A,
    Insert: 0xE00B, Delete: 0xE00C,
    Undo: 0xE010, Help: 0xE011, Escape: 0xE012,
};

window.document.body.addEventListener('keydown', function (evt) {
    if (!demo) return;
    // Stop the browser's default for keys we handle (Space scrolling the page,
    // Enter re-triggering the focused "Sound on" button, arrows scrolling).
    if (["Escape", "Enter", " ", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(evt.key)) {
        evt.preventDefault();
    }
    // Does the cart own the keyboard? A GEM-style application binds every key
    // itself, so the host's own shortcuts below (Space/Enter = Fire, WASD =
    // movement, 1-7 = shading) must NOT fire — they are for navigating a demo
    // scene, and W would both Wipe and move the rate ladder. Carts that do not
    // declare it keep the old behaviour.
    const owns = demo.ownsKeyboard ? demo.ownsKeyboard() !== 0 : false;

    // Escape is NOT a host shortcut. It used to skip the boot screen and return
    // any running scene to the menu, which meant no screen could ever bind it —
    // ST Replay's "Esc = stop" rebooted the machine instead. It is now forwarded
    // like every other key (KEY_CODES below) and the MACHINE decides: the boot ROM
    // skips, a screen that handles keys owns it, and a plain scene cart falls back
    // to the menu. See apps/zig/demo_main.zig.
    // The ARROWS stay movement even for an owning app (ST Replay walks its rate
    // ladder with them); WASD does not, or W would wipe AND move at once.
    if ((!owns && evt.key == "w") || (evt.key == "ArrowUp")) demo.input(0);
    if ((!owns && evt.key == "s") || (evt.key === "ArrowDown")) demo.input(1);
    if ((!owns && evt.key === "a") || (evt.key === "ArrowLeft")) demo.input(2);
    if ((!owns && evt.key === "d") || (evt.key === "ArrowRight")) demo.input(3);
    // Enter/Space = Fire (5): launch the highlighted menu entry.
    if (!owns && (evt.key === "Enter" || evt.key === " ")) demo.input(5);

    // Keys 1-7 → the scene's own mode/song switch. Scenes OWN the behaviour
    // (shading, or a song request via zigos.requestSong); the host only forwards.
    if (!owns && "1234567".includes(evt.key) && demo.setShadeMode) demo.setShadeMode(Number(evt.key) - 1);

    // Text entry (GEM rename etc.): forward printable keys + Backspace/Enter to the
    // app via demo.key(codepoint). 8 = Backspace, 13 = Enter.
    if (demo.key) {
        if (evt.key === "Backspace") { evt.preventDefault(); demo.key(8); }
        else if (evt.key === "Enter") demo.key(13);
        else if (evt.key.length === 1) demo.key(evt.key.charCodeAt(0));
        else if (KEY_CODES[evt.key] !== undefined) { evt.preventDefault(); demo.key(KEY_CODES[evt.key]); }
    }
});

// --------------------------------------------------------------------------
// Pointer input: map mouse events on the (scaled) canvas to the 320x200 visible
// area and forward to demo.pointer(x, y, buttons) — for GEM-style windowed apps.
// The physical framebuffer is 400x280 with a 40px border, so visible = phys - 40.
// --------------------------------------------------------------------------
(function () {
    const surface = window.document.getElementById("3"); // topmost stacked canvas
    surface.style.pointerEvents = "auto";   // re-enable: .overlay sets pointer-events:none
    // The decorative monitor bezel <img> has z-index:100 and sits OVER the canvas,
    // swallowing every click — make it click-through so events reach the surface.
    const bezel = window.document.querySelector(".monitor");
    if (bezel) bezel.style.pointerEvents = "none";
    surface.style.userSelect = "none";      // no text selection while dragging windows
    surface.draggable = false;              // stop the browser "grab the image" drag-ghost
    surface.addEventListener('dragstart', function (e) { e.preventDefault(); });
    let buttons = 0;
    // Send PHYSICAL-VISIBLE coordinates (0..RASTER_VIS_WIDTH / 0..RASTER_VIS_HEIGHT):
    // for a medium screen those ARE the logical coords; a low-res scene halves x.
    function send(evt) {
        if (!demo || !demo.pointer || !machine) return;
        const r = surface.getBoundingClientRect();
        const px = (evt.clientX - r.left) * (machine.hwPhysWidth() / r.width) - machine.hwBorderX();
        const py = (evt.clientY - r.top) * (machine.hwPhysHeight() / r.height) - machine.hwBorderY();
        demo.pointer(Math.round(px), Math.round(py), buttons);
    }
    surface.addEventListener('mousemove', send);
    surface.addEventListener('mousedown', function (e) { buttons = 1; send(e); e.preventDefault(); });
    // Defer the release by one animation frame so a fast click (down+up within a
    // single frame) is still seen as "pressed" for at least one render.
    // The deferred release must itself be SENT: without a mousemove afterwards
    // the module would still believe the button is down (e.g. right after a
    // double-click), leaving an icon latched to the pointer until the next click.
    window.addEventListener('mouseup', function (e) {
        send(e);
        window.requestAnimationFrame(function () { buttons = 0; send(e); });
    });
    // Double-click: use the browser's own dblclick (honours the OS double-click
    // speed) and pulse buttons bit 1 (=2) so the app opens the item under the
    // cursor — frame-sampling can't reliably see two fast presses as two edges.
    surface.addEventListener('dblclick', function (e) {
        const save = buttons; buttons = 2; send(e); buttons = save;
    });
})();

// --------------------------------------------------------------------------
// Touch gamepad: on-screen D-pad + Fire + Esc for phones (no keyboard). Wired
// to the SAME demo.input(N) codes as keydown (0=up 1=down 2=left 3=right
// 5=fire/enter 6=esc). D-pad repeats while held so "hold-Left to slow" works;
// Fire/Esc are single-press. Purely page input — the sealed pipeline is untouched.
// --------------------------------------------------------------------------
(function () {
    const S = document.createElement("style");
    S.textContent = ".tpad{position:fixed;bottom:12px;left:0;right:0;display:flex;" +
        "justify-content:space-between;padding:0 14px;z-index:1000;pointer-events:none;" +
        "user-select:none;-webkit-user-select:none}" +
        ".tpad>div{display:grid;gap:6px;pointer-events:none}" +
        ".dpad{grid-template-columns:repeat(3,52px);grid-template-rows:repeat(3,52px)}" +
        ".tpad button{pointer-events:auto;touch-action:none;font:700 20px system-ui;" +
        "color:#eee;background:rgba(20,20,28,.55);border:1px solid rgba(255,255,255,.25);" +
        "border-radius:10px;width:52px;height:52px}.tpad button:active{background:rgba(90,120,200,.7)}" +
        ".act{align-content:end}.act button{width:64px;height:64px;border-radius:50%}";
    document.head.appendChild(S);

    const pad = document.createElement("div");
    pad.className = "tpad";
    // grid cells: ""=empty; [label,input,repeat]
    const D = { "↑": [0, 1], "←": [2, 1], "→": [3, 1], "↓": [1, 1], "⏎": [5, 0], "␛": [6, 0] };
    function btn(label) {
        const b = document.createElement("button");
        b.textContent = label;
        const code = D[label][0], repeat = D[label][1];
        let timer = null;
        const press = (e) => {
            e.preventDefault();
            if (!demo || !demo.input) return;
            if (label === "␛" && demo.skipBoot) demo.skipBoot();
            demo.input(code);
            if (repeat && timer === null) timer = setInterval(() => demo.input(code), 70);
        };
        const release = () => { if (timer !== null) { clearInterval(timer); timer = null; } };
        b.addEventListener("pointerdown", press);
        b.addEventListener("pointerup", release);
        b.addEventListener("pointercancel", release);
        b.addEventListener("pointerleave", release);
        return b;
    }
    const dpad = document.createElement("div");
    dpad.className = "dpad";
    for (const cell of ["", "↑", "", "←", "", "→", "", "↓", ""]) {
        dpad.appendChild(cell ? btn(cell) : document.createElement("span"));
    }
    const act = document.createElement("div");
    act.className = "act";
    act.appendChild(btn("␛"));
    act.appendChild(btn("⏎"));
    pad.appendChild(dpad);
    pad.appendChild(act);
    document.body.appendChild(pad);
})();

// --------------------------------------------------------------------------
// Audio: AudioWorklet running audio.wasm on the audio thread (unchanged). JS
// mirrors chip state into the demo module for the scene's oscilloscope.
// --------------------------------------------------------------------------
let audioCtx = null;
let audioNode = null;
let audioReady = null;
let streamRate = null;     // active stream scene's sample rate (set by the scene), or null
let streamStarted = false; // have we issued streamStart to the CURRENT audioNode yet?
let recentChunks = [];     // rolling copies of recent fed blocks, to pre-fill the ring on (re)start

function startAudio() {
    if (audioReady) return audioReady;
    audioReady = (async () => {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
        // Sealed audio: two modules (machine-audio + demo-audio) share one memory
        // inside the worklet, mirroring the video seal.
        const [machineBytes, demoBytes] = await Promise.all([
            fetch("machine-audio.wasm" + BUST).then(r => r.arrayBuffer()),
            fetch("demo-audio.wasm" + BUST).then(r => r.arrayBuffer()),
        ]);
        await audioCtx.audioWorklet.addModule("audio-worklet-sealed.js" + BUST);
        audioNode = new AudioWorkletNode(audioCtx, "zig-audio-sealed", {
            numberOfInputs: 0,
            numberOfOutputs: 1,
            outputChannelCount: [2],
            processorOptions: { machineBytes: machineBytes, demoBytes: demoBytes },
        });
        await new Promise((resolve) => {
            audioNode.port.onmessage = (event) => {
                const msg = event.data;
                if (msg.type === "ready") { console.log("Audio worklet ready"); resolve(); }
                else if (msg.type === "error") console.error("Audio worklet error:", msg.message);
                else if (msg.type === "audioState") {
                    if (demo && demo.getYmRegsPointer) {
                        new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 16).set(msg.regs);
                    }
                    if (demo && demo.getAudioModePointer) {
                        new Uint8Array(memory.buffer, demo.getAudioModePointer(), 1)[0] = msg.mode;
                    }
                    if (demo && demo.getScopesPointer && msg.scopes) {
                        const len = msg.scopes[0].length;
                        const flat = new Float32Array(memory.buffer, demo.getScopesPointer(), 4 * len);
                        for (let ch = 0; ch < 4; ch++) flat.set(msg.scopes[ch], ch * len);
                    }
                }
            };
        });
        audioNode.connect(audioCtx.destination);
        await audioCtx.resume();
        flushPendingStream(); // a scene may have requested streaming before audio was enabled
    })();
    return audioReady;
}

async function main() {
    const button = document.querySelector('.sound_button');
    if (audioCtx) {
        try { await audioCtx.close(); } catch (e) {}
        audioCtx = null; audioNode = null; audioReady = null;
        streamStarted = false; // the ring player died with the context; re-arm for next start
        if (button) button.textContent = "Sound on";
        return;
    }
    await startAudio();
    // Don't force a track here — the active scene picks the music via
    // pollSongRequest (union main autoplays Sharpness Buzztone; music_debug uses
    // keys 1-3). Sound on just enables the audio engine.
    if (button) button.textContent = "Sound off";
}
window.main = main;

async function playMod(url) {
    await startAudio();
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    audioNode.port.postMessage({ type: "loadMod", bytes: bytes }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
async function playYm(url) {
    await startAudio();
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    audioNode.port.postMessage({ type: "loadYm", bytes: bytes }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
async function playSndh(url, tune) {
    await startAudio();
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    audioNode.port.postMessage({ type: "loadSndh", bytes: bytes, tune: tune || 0 }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}

// Stop a raw sample by (re)loading a tiny silent buffer onto the channel — the
// sealed chip has no raw-stop, so this overwrites it with silence.
function stopRaw() {
    if (audioNode) audioNode.port.postMessage(
        { type: "loadRaw", bytes: new Uint8Array([128, 128, 128, 128]).buffer, rate: 12517, unsigned: true });
}

async function playRaw(url, rate, unsigned) {
    await startAudio();
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    audioNode.port.postMessage({ type: "loadRaw", bytes: bytes, rate: rate || 12517, unsigned: !!unsigned }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
// Play a scene-requested music file BY NAME (a path under music/). The extension
// picks the player — the host keeps no per-scene playlist. Name comes from wasm
// (zigos.requestSong), so reject a path escape defensively.
function playSongByName(name) {
    if (!name || name.includes("..") || name.startsWith("/")) return;
    const url = "music/" + name;
    if (name.endsWith(".mod")) playMod(url);
    else if (name.endsWith(".ymraw")) playYm(url);
    else if (name.endsWith(".sndh")) playSndh(url);
    else if (name.endsWith(".raw")) playRaw(url, 12517, false);
}

// Boot-sector beep: a raw YM2149 tone (no song player). Exposed to the boot program
// as the `beep` import; the host stops it (beepStop) when the cart chainloads.
async function beep() {
    await startAudio();
    if (audioNode) audioNode.port.postMessage({ type: "beep" });
}
function beepStop() {
    if (audioNode) audioNode.port.postMessage({ type: "beepStop" });
}

// Streaming raw audio: a scene starts a ring player then feeds it chunks it pulls
// off the disk (see STREAM scene). The host only relays — the ring lives in the
// worklet (audio-worklet-sealed.js), fed at the play rate so it never fills.
// Remember the scene's stream request. We must NOT create the AudioContext here:
// that only succeeds inside a user gesture (Sound-on / first interaction), otherwise
// the browser opens it suspended and silent. startAudio() flushes this once audio is live.
function hostAudioStreamStart(rate) {
    streamRate = rate;
    streamStarted = false;
    flushPendingStream(); // no-op until audio is enabled, then startAudio() calls it
}
// Issue streamStart to the worklet and pre-fill the ring from the most-recent audio so
// playback starts buffered (no underrun/noise even if the scene began streaming before
// the user turned sound on). Idempotent per audioNode via streamStarted.
function flushPendingStream() {
    if (streamRate === null || !audioNode || streamStarted) return;
    streamStarted = true;
    audioNode.port.postMessage({ type: "streamStart", rate: streamRate });
    for (const chunk of recentChunks) {
        const bytes = chunk.slice().buffer;
        audioNode.port.postMessage({ type: "streamFeed", bytes }, [bytes]);
    }
}
// Silence the stream: the machine asked the speaker to stop, which the looping
// ring will not do by itself.
function hostAudioStreamStop() {
    streamRate = null;
    streamStarted = false;
    recentChunks.length = 0; // nothing to pre-fill a restart with
    if (audioNode) audioNode.port.postMessage({ type: "streamStop" });
}
function hostAudioFeed(ptr, len) {
    if (len <= 0) return;
    const src = new Uint8Array(memory.buffer, ptr, len); // live view into wasm memory
    recentChunks.push(src.slice()); // keep a copy for the ring pre-fill (transfer detaches)
    if (recentChunks.length > 32) recentChunks.shift(); // ~32 blocks = 16 KiB = half the ring
    if (!audioNode || !streamStarted) return; // audio not live / stream not started yet
    const bytes = src.slice().buffer; // transferable copy
    audioNode.port.postMessage({ type: "streamFeed", bytes }, [bytes]);
}
window.playMod = playMod;
window.playYm = playYm;
window.playRaw = playRaw;
