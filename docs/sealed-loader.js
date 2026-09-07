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

const SHARED_PAGES = 79; // must match hw/sdk/memmap.zig SHARED_PAGES (v1.1: 2 MiB demo window + 1 MiB VRAM)

// Cache-bust every wasm fetch with the page-load time, so a rebuilt .wasm is
// always picked up on reload (mobile browsers cache the 1.9 MB blob hard and
// otherwise keep serving the stale one). See notes/zigmachine-workflow-cache.
const BUST = "?t=" + Date.now();

// Union main-screen YM tunes (depacked to docs/music/union/), keyed by the
// scene's 1-based song id (track 1 = Jess's "Sharpness Buzztone", autoplayed).
const UNION_YM = [
    "music/union/SharpnessBuzztone.ymraw",
    "music/union/150mph.ymraw",
    "music/union/Androids.ymraw",
    "music/union/Drooling.ymraw",
    "music/union/Lap33.ymraw",
    "music/union/Reality.ymraw",
];
const memory = new WebAssembly.Memory({ initial: SHARED_PAGES, maximum: SHARED_PAGES });

const text_decoder = new TextDecoder();
let console_log_buffer = "";

let machine = null;   // machine-video.wasm exports
let demo = null;      // demo.wasm exports
let demoImports = null; // env wired to machine + host — reused on cart swap
let swapping = false; // a cartridge swap (disk boot) is in flight
let sampleLoaded = false; // fed the running scene its sample yet (once per cart)
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
        files[name] = { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true) };
    }
    mountedDisk = { buf, files };
    const start = bootBlock * blockSize;
    console.log(`Mounted "${title}" — ${bootable ? "bootable" : "DATA disk"}, ${nFiles} FAT file(s)`);
    return { bootable, cart: bootable ? buf.buffer.slice(start, start + bootLen) : null };
}

// Read a named file from the mounted disk's FAT (streaming a whole file for now).
function diskFile(name) {
    if (!mountedDisk || !mountedDisk.files[name]) return null;
    const { start, len } = mountedDisk.files[name];
    return mountedDisk.buf.subarray(start, start + len);
}

// Feed a scene's sample-display buffer: prefer the mounted disk's SAMPLE.RAW,
// else fall back to the bundled samples. Only scenes with sampleBuf() react.
function loadSceneSample() {
    if (!demo.getSampleBufLen || !demo.getSampleBufPtr || demo.getSampleBufLen() === 0) return;
    const n = demo.getSampleBufLen();
    const raw = diskFile("SAMPLE.RAW");
    if (raw) {
        const dst = new Uint8Array(memory.buffer, demo.getSampleBufPtr(), n);
        for (let i = 0; i < n; i++) dst[i] = raw[Math.floor(i * raw.length / n)] ?? 128;
        console.log("ST Replay: waveform loaded from disk SAMPLE.RAW");
    } else {
        selectSample(0); // bundled fallback
    }
}

// Swap the running cartridge: the menu launcher asks to boot a scene's floppy
// (req 1 + a tag), a scene asks to return to the menu (req -1). We mount the disk
// and re-instantiate the demo module over the SAME shared memory (audio untouched);
// scenes skip the boot ROM. The render loop keeps drawing the old cart until this
// resolves, so there's no black frame.
async function swapCart(req) {
    if (swapping) return;
    swapping = true;
    try {
        let url;
        if (req === 1) {
            const tag = text_decoder.decode(
                new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
            url = "demo-" + tag + ".zmd";
        } else {
            url = "demo.zmd"; // back to the menu
        }
        const { bootable, cart } = await mountDisk(url);
        // A data disk (e.g. ST Replay) isn't bootable — bring up GEM, which opens
        // its app + reads its files. A bootable disk runs its own cart.
        const bytes = bootable ? cart : await fetch("demo-gem.wasm" + BUST).then((r) => r.arrayBuffer());
        demo = (await WebAssembly.instantiate(bytes, demoImports)).instance.exports;
        machine.hwInit();
        demo.boot();
        if (req === 1) demo.skipBoot(); // scene or data-disk→GEM: straight in (no boot ROM)
        sampleLoaded = false;           // the loop feeds the new cart its sample when ready
    } catch (e) {
        console.error("cart swap failed:", e);
    }
    swapping = false;
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

    // The demo imports the machine's hwVideoBase (to discover the region) + console.
    demoImports = {
        env: {
            memory,
            jsConsoleLogWrite: consoleWrite,
            jsConsoleLogFlush: consoleFlush,
            jsThrowError: throwError,
            consoleLogJS: consoleLogJS,
            hwVideoBase: machine.hwVideoBase,
            hwBlit: machine.hwBlit, // sealed 2D blitter (execute COMMAND register)
            audioPlay: () => playRaw(SAMPLES[curSample].url, SAMPLES[curSample].rate, false), // PLAY -> real sound
            audioStop: stopRaw,
            loadSample: (id) => selectSample(id), // File > Load: switch the current sample
        },
    };
    // What to boot: ?disk=X.zmd boots a cart from a ZigMachine disk image (see
    // docs/FLOPPY_DISK.md); ?demo=X.wasm loads a raw cart; default is demo.wasm.
    const params = new URLSearchParams(window.location.search);
    const diskUrl = params.get("disk");
    let demoMod;
    if (diskUrl) {
        const { bootable, cart } = await mountDisk(diskUrl);
        if (bootable) {
            demoMod = await WebAssembly.instantiate(cart, demoImports);
            console.log("Booted cart from disk:", diskUrl);
        } else {
            // A data disk isn't bootable — bring up the OS (GEM); the disk stays
            // mounted so GEM can open its app + read its files (e.g. SAMPLE.RAW).
            demoMod = await WebAssembly.instantiateStreaming(fetch("demo-gem.wasm" + BUST), demoImports);
            console.log("Data disk inserted → booting GEM");
        }
    } else {
        const demoWasm = params.get("demo") || "demo.wasm";
        demoMod = await WebAssembly.instantiateStreaming(fetch(demoWasm + BUST), demoImports);
        console.log("Open demo.wasm loaded");
    }
    demo = demoMod.instance.exports;

    machine.hwInit();
    demo.boot();

    // The sample is fed by the render loop once the running cart exposes its
    // buffer (after the boot ROM / immediately on a scene swap) — see the loop.
    start();
}

// The selectable samples (File > Load in ST Replay) + the current one.
const SAMPLES = [
    { name: "SMP1.RAW", url: "music/smp1.raw", rate: 12517 },
    { name: "SMP2.RAW", url: "music/smp2.raw", rate: 12517 },
];
let curSample = 0;

function selectSample(id) {
    curSample = (id >= 0 && id < SAMPLES.length) ? id : 0;
    if (demo && demo.getSampleBufLen && demo.getSampleBufLen() > 0)
        loadSampleForDisplay(SAMPLES[curSample].url, demo.getSampleBufLen());
}

// Fetch a raw 8-bit sample and down-sample it into the scene's display buffer.
async function loadSampleForDisplay(url, n) {
    try {
        const raw = new Uint8Array(await (await fetch(url)).arrayBuffer());
        const dst = new Uint8Array(memory.buffer, demo.getSampleBufPtr(), n);
        for (let i = 0; i < n; i++) dst[i] = raw[Math.floor(i * raw.length / n)] ?? 128;
    } catch (e) { console.warn("sample display load failed:", e); }
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

        // Feed a sample-displaying scene (ST Replay) its waveform once its buffer
        // is live (after the boot ROM, or straight away on a swap).
        if (!sampleLoaded && demo.getSampleBufLen && demo.getSampleBufLen() > 0) {
            loadSceneSample();
            sampleLoaded = true;
        }

        // Song-request bridge: once audio is running, let the active scene pick a
        // YM tune (union main autoplays track 1, keys 1-6 switch).
        if (audioCtx && demo.pollSongRequest) {
            const song = demo.pollSongRequest();
            if (song > 0 && UNION_YM[song - 1]) playYm(UNION_YM[song - 1]);
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

window.document.body.addEventListener('keydown', function (evt) {
    if (!demo) return;
    // Stop the browser's default for keys we handle (Space scrolling the page,
    // Enter re-triggering the focused "Sound on" button, arrows scrolling).
    if (["Escape", "Enter", " ", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(evt.key)) {
        evt.preventDefault();
    }
    // ESC skips the boot screen (if still booting) and returns from a running
    // scene to the menu (Back = 6).
    if (evt.key === "Escape") {
        if (demo.skipBoot) demo.skipBoot();
        if (demo.input) demo.input(6);
        return;
    }
    if ((evt.key == "w") || (evt.key == "ArrowUp")) demo.input(0);
    if ((evt.key == "s") || (evt.key === "ArrowDown")) demo.input(1);
    if ((evt.key === "a") || (evt.key === "ArrowLeft")) demo.input(2);
    if ((evt.key === "d" || evt.key === "ArrowRight")) demo.input(3);
    // Enter/Space = Fire (5): launch the highlighted menu entry.
    if (evt.key === "Enter" || evt.key === " ") demo.input(5);

    // Keys 1-7: give the running scene first refusal on a shading/mode switch;
    // setShadeMode returns whether it consumed the key. If not (e.g. music_debug,
    // which has no mode switch), fall back to the audio player shortcuts.
    if ("1234567".includes(evt.key)) {
        const handled = demo.setShadeMode ? demo.setShadeMode(Number(evt.key) - 1) : false;
        if (!handled) {
            if (evt.key === "1") playMod("music/lollapalooza.mod");
            if (evt.key === "2") playYm("music/concerto.ymraw");
            if (evt.key === "3") playRaw("music/smp1.raw", 12517, false);
        }
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
        await audioCtx.audioWorklet.addModule("audio-worklet-sealed.js");
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
    })();
    return audioReady;
}

async function main() {
    const button = document.querySelector('.sound_button');
    if (audioCtx) {
        try { await audioCtx.close(); } catch (e) {}
        audioCtx = null; audioNode = null; audioReady = null;
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
window.playMod = playMod;
window.playYm = playYm;
window.playRaw = playRaw;
