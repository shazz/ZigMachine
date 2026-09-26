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
// A cart that trapped (e.g. memory access out of bounds) is never called again;
// the loop stays alive so +/- and the menu can still swap in another cart.
let cartTrapped = false;
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
    return mountDiskBytes(new Uint8Array(await fetch(url + BUST).then((r) => r.arrayBuffer())), url);
}

// Insert a disk image held in memory: a fetched URL or a visitor's upload
// (upload-cart.js) go through this same parse, so both leave the drive in the
// same state for diskReadBlock. The parser is docs/zmdisk.js (shared with the
// node checks). v1: "ZMDISK" boot sector at $0, $1234 = bootable, $0000 = data
// disk (GEM). v2: the 1 KB boot sector IS a wasm module that chainloads the cart
// (swapCart req 2) from the descriptor at $400. Returns { bootable, cart[, v2] }.
function mountDiskBytes(buf, name) {
    if (!globalThis.ZMDisk) throw new Error(`zmdisk.js not loaded: cannot mount ${name}`);
    const d = globalThis.ZMDisk.parseDisk(buf, name);
    mountedDisk = d.mounted;
    if (d.v2) {
        console.log(`Mounted v2 "${d.title}" — ${d.bootable ? "executable boot sector" : "data disk"}, ${d.nFiles} FAT file(s)`);
        return { bootable: d.bootable, v2: true, cart: d.cart };
    }
    console.log(`Mounted "${d.title}" — ${d.bootable ? "bootable" : "DATA disk"}, ${d.nFiles} FAT file(s)`);
    return { bootable: d.bootable, cart: d.cart };
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

// A channel change (+/- on the monitor) is req 1 with the tag supplied by the
// host instead of read from the cart; it tunes in through TV snow (tuneIn).
async function swapCart(req, channelTag) {
    if (swapping) return;
    swapping = true;
    let url = null;
    let failed = false;
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
            heldDirs.clear(); heldKeys.clear(); // the new cart never saw those presses: no releases for them
            swapping = false;
            return;
        }
        // req 3 = RUN A PROGRAM off the mounted disk. GEM launching an app the way
        // TOS does: the program is a FILE in the floppy's FAT, not something linked
        // into the desktop. The disk stays mounted, so the app can read its own data
        // files (ST Replay reads the .RAW sitting next to it).
        //
        // This is also what stops the launch double-click leaking into the app it
        // started: the app used to be already resident, so the second click landed
        // in it. A freshly instantiated cart has no pointer state to inherit.
        if (req === 3) {
            const name = text_decoder.decode(
                new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
            const entry = mountedDisk && mountedDisk.files[name];
            if (!entry) throw new Error(`no program "${name}" on the mounted disk`);
            const bytes = mountedDisk.buf.buffer.slice(entry.start, entry.start + entry.len);
            demo = (await instantiateCart(bytes, `${name} (from the disk)`)).instance.exports;
            machine.hwInit();
            demo.boot();
            demo.skipBoot(); // GEM already booted the machine; no second boot screen
            heldDirs.clear(); heldKeys.clear(); // the new cart never saw those presses: no releases for them
            swapping = false;
            return;
        }
        // req 4 = back to the OS. An app quitting returns to the desktop it was
        // launched from, with its disk still in the drive — NOT to the menu.
        if (req === 4) {
            demo = (await instantiateCart(
                await fetch("demo-gem.wasm" + BUST).then((r) => r.arrayBuffer()),
                "demo-gem.wasm (back to the OS)")).instance.exports;
            machine.hwInit();
            demo.boot();
            demo.skipBoot();
            heldDirs.clear(); heldKeys.clear(); // the new cart never saw those presses: no releases for them
            diskApp = true;      // the disk is still mounted: FLOPPY still opens it
            diskDirSet = false;  // re-hand GEM the FAT listing
            swapping = false;
            return;
        }
        let tag = null;
        if (req === 1) {
            tag = channelTag || text_decoder.decode(
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
        // Channel change: snow first (a disk packed before tuneIn existed just starts).
        if (channelTag && demo.tuneIn) demo.tuneIn(TUNE_FRAMES);
        else if (req === 1) demo.skipBoot(); // scene or data-disk→GEM: straight in (no boot ROM)
        // The deck's name card, over the picture this cart is about to draw. Only
        // for a real cart: a data disk brings up GEM, and req -1 is the menu.
        if (req === 1 && bootable && window.armCartOsd) window.armCartOsd(tag);
        heldDirs.clear(); heldKeys.clear(); // the new cart never saw those presses: no releases for them
        currentTag = tag; // null = the menu
        diskApp = !bootable;            // data disk → GEM's FLOPPY opens its app
        diskDirSet = false;            // re-hand GEM the new disk's FAT listing
    } catch (e) {
        // The running cart keeps going. Without remembering the failure the menu
        // would ask for this disk again next frame, and every frame after —
        // which reads as a freeze rather than as an error.
        if (url) badCarts.add(url);
        console.error("cart swap failed:", e);
        failed = true;
    } finally {
        // Every path must release the guard: an early `return` inside the try
        // (a disk already known bad) used to leave `swapping` set forever, and
        // with it +/- and every later swap silently refused.
        swapping = false;
        // The old cart is still the one running: a key that came up during the
        // swap was not released to it (the keyup listener kept it in heldDirs), so
        // release now everything it still holds, or its scene walks on for good.
        if (failed) releaseAll();
    }
}

// --------------------------------------------------------------------------
// TV channels: the monitor's +/- step through docs/channels.json (generated by
// tools/channels.py from the menu's catalog), wrapping at both ends — the
// original gh-page behaviour. The swap is an ordinary disk boot (swapCart), so
// the ROM and sound chip are reset exactly as for a menu launch.
// --------------------------------------------------------------------------
const TUNE_FRAMES = 25; // frames of snow before the new channel's picture
// [{tag, title, type}, ...], fetched once. The title and type are what the VHS
// name card prints when the channel comes up (cart-osd.js); nothing else here
// reads them, so a record with only a tag still tunes.
let channels = null;
let currentTag = null;  // tag of the running scene disk, null = menu / other

// The channel list, fetched once. null (logged) if it cannot be had.
async function loadChannels() {
    if (!channels) {
        try {
            channels = await fetch("channels.json" + BUST).then((r) => r.json());
        } catch (e) {
            console.error("no channel list (docs/channels.json):", e);
            return null;
        }
    }
    return Array.isArray(channels) && channels.length > 0 ? channels : null;
}

// The channel a fresh page tunes to: ?channel=<tag> if it is one, else the first.
// null only when there is no channel list — the page then boots the menu.
async function firstChannel(wanted) {
    const list = await loadChannels();
    if (!list) return null;
    const has = wanted && list.some((c) => c.tag === wanted);
    if (wanted && !has) console.error(`?channel=${wanted} is not a channel; tuning to ${list[0].tag}`);
    return has ? wanted : list[0].tag;
}

async function changeChannel(step) {
    if (swapping || !demo) return;
    if (!(await loadChannels())) return;
    const at = channels.findIndex((c) => c.tag === currentTag);
    const next = at < 0 ? 0 : (at + step + channels.length) % channels.length;
    swapCart(1, channels[next].tag);
}
function nextChannel() { changeChannel(1); }
function previousChannel() { changeChannel(-1); }

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
        // Still a NEW cart: declaring 0 also empties the previous cart's RAM
        // arena, so nothing it allocated is handed on (or counted) as ours.
        machine.hwSetCartHigh(0);
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
// A disk stores its cart ZX0-packed ("ZX0!", see tools/mkdisks.sh): a tenth of
// the size. Unpacking a program is the MACHINE's job, so the ROM chip does it.
// The host only moves bytes: the packed image into the ROM's free RAM, then
// romDepack unpacks it into the cart window (the outgoing program no longer owns
// it), and a copy of the result is instantiated. Anything else passes through.
function unpackCart(bytes, what) {
    const u8 = new Uint8Array(bytes);
    if (u8.length < 10 || u8[0] !== 0x5a || u8[1] !== 0x58 || u8[2] !== 0x30 || u8[3] !== 0x21) return bytes;
    if (!rom || !rom.romDepack) throw new Error(`${what} is packed, but this ROM cannot depack it`);
    if (u8.length > machine.hwRomRamFree())
        throw new Error(`${what}: packed cart (${u8.length} B) does not fit the ROM's free RAM`);
    const src = machine.hwRomRamBase() + machine.hwRomRamUsed();
    new Uint8Array(memory.buffer, src, u8.length).set(u8);
    const dst = machine.hwRamBase();
    const n = rom.romDepack(src, u8.length, dst, machine.hwRamSize());
    if (!n) throw new Error(`${what}: packed cart is corrupt or too big for the cart window`);
    return memory.buffer.slice(dst, dst + n);
}

async function instantiateCart(bytes, what) {
    try {
        bytes = unpackCart(bytes, what);
        const mod = await WebAssembly.instantiate(bytes, demoImports);
        declareCartRam(bytes, what);
        // The outgoing program cannot release its ROM handles — it is already gone.
        // So the machine reclaims them, the way an OS does when a program ends.
        // Without this, MAX_GUI launches exhaust the tables and every ROM call
        // silently becomes a no-op: the app draws, and its dialogs never appear.
        if (rom && rom.romReset) rom.romReset();
        // Same reasoning for the sound chip: the outgoing program cannot stop
        // its own music -- it is already gone -- so the machine silences it.
        // Without this, Escape out of a screen and its tune plays on over the
        // next one. The audio half lives on the worklet thread, so it is a
        // message rather than a call.
        if (audioNode) audioNode.port.postMessage({ type: "reset" });
        cartTrapped = false; // a fresh cart runs again
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
            // The RAM arena (1.7.0): malloc above the cart's high-water, emptied
            // by the hwSetCartHigh every cart load makes (declareCartRam).
            hwRamAlloc: machine.hwRamAlloc,
            hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease,
            hwRamAllocFailures: machine.hwRamAllocFailures,
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
    // docs/FLOPPY_DISK.md); ?demo=X.wasm loads a raw cart; ?menu boots the menu.
    // With none of those the machine powers up like the TV it sits in: straight
    // into a channel (?channel=<tag>, else the first), boot ROM first.
    const params = new URLSearchParams(window.location.search);
    let diskUrl = params.get("disk");
    if (!diskUrl && !params.has("demo") && !params.has("menu")) {
        const tag = await firstChannel(params.get("channel"));
        if (tag) {
            diskUrl = "demo-" + tag + ".zmd";
            currentTag = tag;
        }
    }
    let demoMod;
    if (diskUrl) {
        const { bootable, cart } = await mountDisk(diskUrl);
        if (bootable) {
            demoMod = await instantiateCart(cart, diskUrl);
            console.log("Booted cart from disk:", diskUrl);
            // Power-on into a channel (or ?disk=): name the cart once it is up.
            if (window.armCartOsd) window.armCartOsd(currentTag || window.osdTagFromDiskUrl(diskUrl));
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

    // ?step=N: run a cart at an intermediate state. docs/TUTORIAL.html uses it to
    // boot the tutorial screen as it stands at each step of docs/TUTORIAL.md, so
    // "what you should see" is literally what you see. It rides the existing
    // per-scene mode switch (setShadeMode) rather than adding an ABI point, and a
    // cart that ignores the mode simply runs as usual.
    // skipBoot first: the mode only reaches a RUNNING cart, and an embedded panel
    // does not want the boot ROM animation anyway.
    const stepArg = params.get("step");
    if (stepArg !== null) {
        const n = Number(stepArg);
        if (!Number.isInteger(n) || n < 1) {
            console.warn("?step must be a positive integer, got:", stepArg);
        } else {
            demo.skipBoot();
            if (!demo.setShadeMode || !demo.setShadeMode(n)) {
                console.warn("?step=" + n + ": this cart has no steps, running it whole");
            }
        }
    }

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

    // The machine runs at a FIXED 60 Hz, whatever the display refreshes at. rAF
    // fires once per refresh, so on a 120 Hz ProMotion panel (or 144 Hz) a cart
    // that steps once per frame ran 2x (2.4x) too fast. Now a refresh only runs the
    // machine when a 60 Hz tick is due; the others keep the last picture. Carts that
    // pace by elapsed time are unaffected (dt now spans the skipped refreshes).
    const MACHINE_HZ = 60;
    const TICK_MS = 1000 / MACHINE_HZ;
    let last_timestamp = 0;
    let next_tick = 0;
    // The title shows both rates, averaged over ~0.5 s: how often the machine
    // ran, and how often the display refreshed. Written only when it changes.
    let rate_refreshes = 0, rate_ticks = 0, rate_since = 0, rate_shown = "";
    const showRates = function (timestamp, ticked) {
        if (rate_since === 0) rate_since = timestamp; // first frame: start the window here
        rate_refreshes++;
        if (ticked) rate_ticks++;
        const span = timestamp - rate_since;
        if (span < 500) return;
        const title = "ZigMachine — " + Math.round(rate_ticks * 1000 / span) + " fps · display " +
            Math.round(rate_refreshes * 1000 / span) + " Hz";
        if (title !== rate_shown) document.title = rate_shown = title;
        rate_refreshes = rate_ticks = 0;
        rate_since = timestamp;
    };
    const step = function (timestamp) {
        // The very first call is loop() itself, not rAF: it has no timestamp.
        if (timestamp === undefined) timestamp = performance.now();
        if (next_tick === 0) next_tick = timestamp;
        // 1 ms of slack for rAF jitter, so a 60 Hz display never skips a tick.
        const due = timestamp >= next_tick - 1;
        showRates(timestamp, due);
        if (!due) return;
        next_tick += TICK_MS;
        if (timestamp - next_tick > 250) next_tick = timestamp; // after a stall: resync, no burst
        if (last_timestamp === 0) last_timestamp = timestamp; // first tick: dt 0, not the page's age
        const elapsed_time = (timestamp - last_timestamp);
        last_timestamp = timestamp;

        // A swap unpacks the NEW cart into the cart RAM window (unpackCart), which
        // is the OLD cart's statics and stack. Running the old cart meanwhile reads
        // that half-written memory and traps. So during a swap, and after a trap,
        // the cart is not called and the canvases keep their last picture.
        if (swapping || cartTrapped) return;
        machine.hwClear();          // sealed: clear PFB + global HBL
        demo.frame(elapsed_time);   // open: scene draws into shared LFBs (+ overscan poke)

        // The VHS name card: fires once the booting cart is really running (past
        // the boot ROM / the channel snow). A no-op when nothing is armed.
        if (window.pollCartOsd) window.pollCartOsd();

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
            // The record layout and the cap come FROM THE ROM, not from literals
            // here. They used to be `25` and `12` mirrored by hand against
            // desktop.zig, with a comment as the only contract — and the ROM's own
            // clamp had drifted to a THIRD number (/17), which would have admitted
            // 17 records into a 12-record buffer the moment the host stopped
            // capping. Ask, don't mirror.
            const ENT = (rom && rom.deskDirEntryBytes) ? rom.deskDirEntryBytes() : 25;
            const MAXF = (rom && rom.deskDirMaxFiles) ? rom.deskDirMaxFiles() : 12;
            const names = Object.keys(mountedDisk.files).slice(0, MAXF);
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
                new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())),
                demo.songTune ? demo.songTune() : 0);
        }

        let anyPlane = false;
        for (let i = 0; i < nb_planes; i++) {
            if (demo.isPlaneEnabled(i)) {
                anyPlane = true;
                machine.hwRenderPlane(i);       // sealed: composite LFB[i] -> PFB
                imageDatas[i].data.set(fbView); // single copy PFB -> plane i's canvas
                contexts[i].putImageData(imageDatas[i], 0, 0);
                planeDirty[i] = true;
            } else if (planeDirty[i]) {
                contexts[i].clearRect(0, 0, fb_width, fb_height); // blank the stale layer
                planeDirty[i] = false;
            }
        }
        // No plane enabled: an ST with empty bitplanes still shows colour 0, so
        // the PFB as hwClear() left it (background, borders, BEAM writes) is the
        // picture. A zero-bitplane screen (dhs_0pxl0reg) is nothing but this.
        if (!anyPlane) {
            imageDatas[0].data.set(fbView);
            contexts[0].putImageData(imageDatas[0], 0, 0);
            planeDirty[0] = true;
        }
    };
    // The rAF chain must never die: an exception out of a cart used to stop
    // the loop for good, so no later swap could ever show a picture again.
    const loop = function (timestamp) {
        try {
            step(timestamp);
        } catch (e) {
            cartTrapped = true;
            console.error(`ZigMachine: the running cart trapped (${e.message}). Press + / - or pick another disk.`, e);
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

    // + / - change channel, like the monitor buttons — never for an app that
    // owns the keyboard (GEM rename, ST Replay), which gets the keys instead.
    if (!owns && (evt.key === "+" || evt.key === "-")) {
        evt.key === "+" ? nextChannel() : previousChannel();
        return;
    }

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

// Key RELEASE: optional on both sides. A cart that declares no inputRelease/keyUp
// is never called, so every existing disk behaves exactly as before. A scene that
// steers with a HELD key (the Union Demo hub) otherwise has to guess the release
// from the OS auto-repeat, and walks on after the key comes up.
// Direction codes are the same as demo.input (0 up, 1 down, 2 left, 3 right, 5 fire),
// with the same owns-keyboard rule as the keydown listener above.
function directionOf(key, owns) {
    if (key === "ArrowUp" || (!owns && key === "w")) return 0;
    if (key === "ArrowDown" || (!owns && key === "s")) return 1;
    if (key === "ArrowLeft" || (!owns && key === "a")) return 2;
    if (key === "ArrowRight" || (!owns && key === "d")) return 3;
    if (!owns && (key === "Enter" || key === " ")) return 5;
    return -1;
}
const heldDirs = new Set(); // directions this page has seen go down and not up
// The same for demo.keyUp's codes: a cart that owns the keyboard (a game: WASD,
// fire, Space...) must see those released on focus loss too, or they stay down.
const heldKeys = new Set();
function keyUpCode(key) {
    if (key === "Backspace") return 8;
    if (key === "Enter") return 13;
    if (key.length === 1) return key.charCodeAt(0);
    return KEY_CODES[key] !== undefined ? KEY_CODES[key] : -1;
}
// Bookkeeping only; the keydown listener above still sends demo.input. Repeats
// are counted too, so a key held across a cart swap (heldDirs cleared) is
// tracked again for blur.
window.document.body.addEventListener('keydown', function (evt) {
    if (!demo) return;
    const owns = demo.ownsKeyboard ? demo.ownsKeyboard() !== 0 : false;
    const dir = directionOf(evt.key, owns);
    if (dir >= 0) heldDirs.add(dir);
    const code = keyUpCode(evt.key);
    if (code >= 0 && demo.keyUp) heldKeys.add(code);
});
// No release while a swap is in flight (the cart window holds the next cart being
// unpacked) or after a trap (that cart is never called again).
const cartCallable = () => demo && !swapping && !cartTrapped;
window.document.body.addEventListener('keyup', function (evt) {
    if (!demo) return;
    const owns = demo.ownsKeyboard ? demo.ownsKeyboard() !== 0 : false;
    const dir = directionOf(evt.key, owns);
    // A release the cart cannot take now stays in heldDirs: if the swap fails, the
    // old cart keeps running and swapCart hands it the release (releaseAll); if
    // the swap succeeds, heldDirs is cleared for the new cart.
    if (dir >= 0 && cartCallable()) {
        heldDirs.delete(dir);
        if (demo.inputRelease) demo.inputRelease(dir);
    }
    const code = keyUpCode(evt.key);
    if (code >= 0 && cartCallable() && demo.keyUp) {
        heldKeys.delete(code);
        demo.keyUp(code);
    }
});
// Focus loss swallows the keyup: release everything still held.
function releaseAll() {
    if (cartCallable() && demo.inputRelease) for (const d of heldDirs) demo.inputRelease(d);
    heldDirs.clear();
    if (cartCallable() && demo.keyUp) for (const c of heldKeys) demo.keyUp(c);
    heldKeys.clear();
}
window.addEventListener('blur', releaseAll);
document.addEventListener('visibilitychange', () => { if (document.hidden) releaseAll(); });

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
    // grid cells: ""=empty; [label,input,repeat] — a DIRECTION, sent as input().
    const D = { "↑": [0, 1], "←": [2, 1], "→": [3, 1], "↓": [1, 1], "⏎": [5, 0] };
    // Esc is not a direction, it is a KEY, and it is forwarded exactly as the
    // keyboard forwards it so the MACHINE decides what it means (see
    // demo_main.zig: the boot ROM skips, a screen that binds keys owns it, a
    // plain scene cart falls back to the menu).
    //
    // It used to call skipBoot() and send input(6) = Back straight from here,
    // which bypassed that decision AND ownsKeyboard — so Escape did different
    // things on a touchscreen and on a keyboard: in ST Replay it went back to
    // the menu instead of stopping playback.
    const KEYS = { "␛": KEY_CODES.Escape };
    function btn(label) {
        const b = document.createElement("button");
        b.textContent = label;
        const key = KEYS[label];
        const [code, repeat] = D[label] || [0, 0];
        let timer = null;
        const press = (e) => {
            e.preventDefault();
            if (!demo) return;
            if (key !== undefined) { if (demo.key) demo.key(key); return; }
            if (!demo.input) return;
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
        if (!audioCtx.audioWorklet) {
            // AudioWorklet exists only in a secure context (https:// or localhost).
            console.warn("ZigMachine: sound needs https:// or localhost; this page was opened over plain http, so audio is off.");
            try { await audioCtx.close(); } catch (e) {}
            audioCtx = null;
            return;
        }
        // Does the browser honour the requested 44100 Hz? (A suspect for choppy streamed music.)
        console.log("audio: context sampleRate", audioCtx.sampleRate);
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
                // An SNDH can fail in ways only its own 68000 knows about, so say so.
                else if (msg.type === "sndhLoaded") {
                    const hex = (v) => "$" + (v >>> 0).toString(16);
                    console.log(msg.ok
                        ? `SNDH playing (${msg.len} bytes staged)`
                        : `SNDH REJECTED (${msg.len} bytes) stuckPc=${hex(msg.stuckPc)} trap=${hex(msg.trap)}`);
                }
                else if (msg.type === "audioState") {
                    // These write through the running cart's pointers. During a swap
                    // those addresses belong to the cart being unpacked: skip.
                    if (swapping || cartTrapped || !demo) return;
                    if (demo && demo.getYmRegsPointer) {
                        new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 16).set(msg.regs);
                    }
                    if (demo && demo.getAudioModePointer) {
                        new Uint8Array(memory.buffer, demo.getAudioModePointer(), 1)[0] = msg.mode;
                    }
                    if (demo && demo.getSongMsPointer) {
                        new Uint32Array(memory.buffer, demo.getSongMsPointer(), 1)[0] = msg.songMs | 0;
                    }
                    if (demo && demo.getScopesPointer && msg.scopes) {
                        const len = msg.scopes[0].length;
                        const flat = new Float32Array(memory.buffer, demo.getScopesPointer(), 4 * len);
                        for (let ch = 0; ch < 4; ch++) flat.set(msg.scopes[ch], ch * len);
                    }
                }
            };
        });
        // A processor that throws is DISABLED by the browser, and the exception
        // never reaches the console: the only symptom is that the sound stops.
        audioNode.onprocessorerror = (e) =>
            console.error("Audio worklet processor died — sound has stopped:", e);
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

// `bpm`: the start tempo a cart asked for with zg.requestModBpm (0 = ProTracker's 125).
async function playMod(url, gen, bpm) {
    await startAudio();
    if (!audioNode) return; // no audio in this context
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    if (gen !== undefined && gen !== songGen) return; // a newer song request (or a stop) won
    audioNode.port.postMessage({ type: "loadMod", bytes: bytes, bpm: bpm || 0 }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
async function playYm(url, gen) {
    await startAudio();
    if (!audioNode) return; // no audio in this context
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    if (gen !== undefined && gen !== songGen) return; // a newer song request (or a stop) won
    audioNode.port.postMessage({ type: "loadYm", bytes: bytes }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
async function playSndh(url, tune, gen) {
    await startAudio();
    if (!audioNode) return; // no audio in this context
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    if (gen !== undefined && gen !== songGen) return; // a newer song request (or a stop) won
    audioNode.port.postMessage({ type: "loadSndh", bytes: bytes, tune: tune || 0 }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}

// Stop a raw sample by (re)loading a tiny silent buffer onto the channel — the
// sealed chip has no raw-stop, so this overwrites it with silence.
function stopRaw() {
    if (audioNode) audioNode.port.postMessage(
        { type: "loadRaw", bytes: new Uint8Array([128, 128, 128, 128]).buffer, rate: 12517, unsigned: true });
}

async function playRaw(url, rate, unsigned, gen) {
    await startAudio();
    if (!audioNode) return; // no audio in this context
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    if (gen !== undefined && gen !== songGen) return; // a newer song request (or a stop) won
    audioNode.port.postMessage({ type: "loadRaw", bytes: bytes, rate: rate || 12517, unsigned: !!unsigned }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
// Play a scene-requested music file BY NAME (a path under music/). The extension
// picks the player — the host keeps no per-scene playlist. Name comes from wasm
// (zigos.requestSong), so reject a path escape defensively.
// Every request bumps songGen; a fetch that resolves after a newer request (a
// stop included) is dropped, so a slow earlier song can never start over it.
let songGen = 0;
function playSongByName(name, tune) {
    const gen = ++songGen;
    // "none" is the reserved stop request (zg.stopSong / zm_stop_song / stop_song):
    // the same player reset the machine does when a program ends.
    if (name === "none") { if (audioNode) audioNode.port.postMessage({ type: "reset" }); return; }
    if (!name || name.includes("..") || name.startsWith("/")) return;
    const url = "music/" + name;
    if (name.endsWith(".mod")) playMod(url, gen, tune); // a MOD's tune field is its start BPM
    else if (name.endsWith(".ymraw")) playYm(url, gen);
    // Only an SNDH has subtunes; `tune` counts from 1, 0 = the image's default.
    else if (name.endsWith(".sndh")) playSndh(url, tune, gen);
    else if (name.endsWith(".raw")) playRaw(url, 12517, false, gen);
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
