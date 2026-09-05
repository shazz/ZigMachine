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

const SHARED_PAGES = 48; // must match src/sdk/memmap.zig SHARED_PAGES
const memory = new WebAssembly.Memory({ initial: SHARED_PAGES, maximum: SHARED_PAGES });

const text_decoder = new TextDecoder();
let console_log_buffer = "";

let machine = null;   // machine-video.wasm exports
let demo = null;      // demo.wasm exports
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
    const machineMod = await WebAssembly.instantiateStreaming(fetch("machine-video.wasm"), machineImports);
    machine = machineMod.instance.exports;
    console.log("Sealed machine-video.wasm loaded, HW version 0x" + machine.hwVersion().toString(16));

    // The demo imports the machine's hwVideoBase (to discover the region) + console.
    const demoImports = {
        env: {
            memory,
            jsConsoleLogWrite: consoleWrite,
            jsConsoleLogFlush: consoleFlush,
            jsThrowError: throwError,
            consoleLogJS: consoleLogJS,
            hwVideoBase: machine.hwVideoBase,
            hwBlit: machine.hwBlit, // sealed 2D blitter (execute COMMAND register)
        },
    };
    // Which open scene to load: ?demo=demo-scroll.wasm etc. (default demo.wasm),
    // so one page can show any of the compiled scenes in a separate tab.
    const demoWasm = new URLSearchParams(window.location.search).get("demo") || "demo.wasm";
    const demoMod = await WebAssembly.instantiateStreaming(fetch(demoWasm), demoImports);
    demo = demoMod.instance.exports;
    console.log("Open demo.wasm loaded");

    machine.hwInit();
    demo.boot();
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
        const ctx = canvas.getContext("2d");
        contexts.push(ctx);
        imageDatas.push(ctx.createImageData(fb_width, fb_height));
    }

    let last_timestamp = 0;
    const loop = function (timestamp) {
        const elapsed_time = (timestamp - last_timestamp);
        last_timestamp = timestamp;
        document.title = "Sealed HW — FPS:" + (1000 / elapsed_time).toFixed(1);

        machine.hwClear();          // sealed: clear PFB + global HBL
        demo.frame(elapsed_time);   // open: scene draws into shared LFBs (+ overscan poke)

        for (let i = 0; i < nb_planes; i++) {
            if (demo.isPlaneEnabled(i)) {
                machine.hwRenderPlane(i);       // sealed: composite LFB[i] -> PFB
                imageDatas[i].data.set(fbView); // single copy PFB -> plane i's canvas
                contexts[i].putImageData(imageDatas[i], 0, 0);
            }
        }
        requestId = window.requestAnimationFrame(loop);
    };
    loop();
}

window.document.body.onload = boot;

window.document.body.addEventListener('keydown', function (evt) {
    if (!demo) return;
    if ((evt.key == "w") || (evt.key == "ArrowUp")) demo.input(0);
    if ((evt.key == "s") || (evt.key === "ArrowDown")) demo.input(1);
    if ((evt.key === "a") || (evt.key === "ArrowLeft")) demo.input(2);
    if ((evt.key === "d" || evt.key === "ArrowRight")) demo.input(3);

    // Keys 1-4: if the active scene exposes a shading/mode switch, drive that;
    // otherwise fall back to the audio player shortcuts (music_debug etc.).
    if (demo && demo.setShadeMode && "1234567".includes(evt.key)) {
        demo.setShadeMode(Number(evt.key) - 1);
    } else {
        if (evt.key === "1") playMod("music/lollapalooza.mod");
        if (evt.key === "2") playYm("music/concerto.ymraw");
        if (evt.key === "3") playRaw("music/smp1.raw", 12517, false);
    }
});

// --------------------------------------------------------------------------
// Pointer input: map mouse events on the (scaled) canvas to the 320x200 visible
// area and forward to demo.pointer(x, y, buttons) — for GEM-style windowed apps.
// The physical framebuffer is 400x280 with a 40px border, so visible = phys - 40.
// --------------------------------------------------------------------------
(function () {
    const HB = 40, VB = 40;                 // border widths (see memmap)
    const surface = window.document.getElementById("3"); // topmost stacked canvas
    surface.style.pointerEvents = "auto";   // re-enable: .overlay sets pointer-events:none
    surface.style.userSelect = "none";      // no text selection while dragging windows
    surface.draggable = false;              // stop the browser "grab the image" drag-ghost
    surface.addEventListener('dragstart', function (e) { e.preventDefault(); });
    let buttons = 0;
    function send(evt) {
        if (!demo || !demo.pointer) return;
        const r = surface.getBoundingClientRect();
        const px = (evt.clientX - r.left) * (400 / r.width);
        const py = (evt.clientY - r.top) * (280 / r.height);
        demo.pointer(Math.round(px - HB), Math.round(py - VB), buttons);
    }
    surface.addEventListener('mousemove', send);
    surface.addEventListener('mousedown', function (e) { buttons = 1; send(e); e.preventDefault(); });
    // Defer the release by one animation frame so a fast click (down+up within a
    // single frame) is still seen as "pressed" for at least one render.
    window.addEventListener('mouseup', function (e) {
        send(e);
        window.requestAnimationFrame(function () { buttons = 0; });
    });
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
            fetch("machine-audio.wasm").then(r => r.arrayBuffer()),
            fetch("demo-audio.wasm").then(r => r.arrayBuffer()),
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
    await playMod("music/lollapalooza.mod");
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
async function playRaw(url, rate, unsigned) {
    await startAudio();
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    audioNode.port.postMessage({ type: "loadRaw", bytes: bytes, rate: rate || 12517, unsigned: !!unsigned }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
window.playMod = playMod;
window.playYm = playYm;
window.playRaw = playRaw;
