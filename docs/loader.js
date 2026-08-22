var memory = new WebAssembly.Memory({
    initial: 32 /* pages */,
    maximum: 32 /* pages */,
});

const text_decoder = new TextDecoder();
let console_log_buffer = "";
let audioContext = null;
let wasm_file = "bootloader.wasm"
var requestId;
var current_channel = 1;
const list_channels = [ 
    "wasm/deltaforce.wasm", 
    "wasm/the_union.wasm",
    "wasm/empire.wasm", 
    "wasm/ancool.wasm", 
    "wasm/leonard.wasm", 
    "wasm/mandelbrot.wasm", 
    "wasm/ics.wasm", 
    "wasm/bladerunners.wasm", 
    "wasm/replicants.wasm",
    "wasm/fullscreen.wasm",
    "wasm/stcs.wasm",
    "wasm/equinox.wasm",
    "wasm/maxi.wasm",
    "wasm/fallen_angels.wasm",
    "wasm/deltaforce2.wasm",
    "wasm/dbug.wasm",
    "wasm/boot.wasm"
];

var ZigMachine = {
    'boot': null,
    'frame': null,
    'getPlanesNumber': null,
    'getPhysicalFrameBufferWidth': null,
    'getPhysicalFrameBufferHeight': null,
    'getPhysicalFrameBufferPointer': null,
    'renderPhysicalFrameBuffer': null,
    'clearPhysicalFrameBuffer': null,
    "isPlaneEnabled": null,
    'u8ArrayToF32Array': null,
    'generateAudio': null,
    'input': null,
}

var change_channel = function() {

    wasm_file = list_channels[current_channel];
    onload();
}

var next_channel = function() {

    current_channel += 1;
    if(current_channel == list_channels.length) current_channel = 0;
    change_channel();
}
var previous_channel = function() {

    current_channel -= 1;
    if(current_channel <= 0) current_channel = (list_channels.length)-1;
    change_channel();
}

var start = function() {

    // clear current channel
    if(requestId) {
        window.cancelAnimationFrame(requestId);
        for(i=0; i < 4; i++){
            const canvas = document.getElementById(i);
            const context = canvas.getContext("2d");
            context.clearRect(0, 0, canvas.width, canvas.height);
        }
    }

    var last_timestamp = 0;

    console.log("Main function started");
    console.log(memory.buffer);

    // get buffer nb
    const nb_buffers = ZigMachine.getPlanesNumber();
    const fb_width = ZigMachine.getPhysicalFrameBufferWidth();
    const fb_height = ZigMachine.getPhysicalFrameBufferHeight();
    const fb_len = fb_width * fb_height * 4;

    // The physical framebuffer lives at a fixed address in wasm linear memory,
    // and linear memory never grows (initial == max pages), so we can build the
    // view and per-plane ImageData ONCE instead of every frame. This removes the
    // old per-plane, per-frame createImageData() + Uint8Array.slice() (2 allocs +
    // 2 copies of ~448KB each) that was capping multi-plane scenes at ~30fps.
    const bufferOffset = ZigMachine.getPhysicalFrameBufferPointer();
    const fbView = new Uint8Array(memory.buffer, bufferOffset, fb_len);

    const contexts = [];
    const imageDatas = [];
    for(let p = 0; p < nb_buffers; p++) {
        const canvas = document.getElementById(p);
        const ctx = canvas.getContext("2d");
        contexts.push(ctx);
        imageDatas.push(ctx.createImageData(fb_width, fb_height));
    }

    var loop = function(timestamp) {

        const elapsed_time = (timestamp - last_timestamp);
        last_timestamp = timestamp;
        document.title = "FPS:" + (1000 / elapsed_time).toFixed(2);

        ZigMachine.clearPhysicalFrameBuffer();
        ZigMachine.frame(elapsed_time);

        for(let i = 0; i < nb_buffers; i++) {
            if(ZigMachine.isPlaneEnabled(i)) {
                ZigMachine.renderPhysicalFrameBuffer(i);
                // single copy: wasm framebuffer -> this plane's ImageData
                imageDatas[i].data.set(fbView);
                contexts[i].putImageData(imageDatas[i], 0, 0);
            }
        }
        // loop to next frame
        requestId = window.requestAnimationFrame(loop);
    };
    loop();
};


window.document.body.onload = function() {
    var imports = { 
        env: {
            // Useful for debugging on zig's side
            consoleLogJS: (arg, len) => {
                let arr8 = new Uint8Array(memory.buffer.slice(arg, arg+len));
                console.log(text_decoder.decode(arr8));
            },
            jsConsoleLogWrite: function (ptr, len) {
                let arr8 = new Uint8Array(memory.buffer.slice(ptr, ptr+len));
                console_log_buffer += text_decoder.decode(arr8);
            },
            jsConsoleLogFlush: function () {
                console.log(console_log_buffer);
                console_log_buffer = "";
            }, 
            jsThrowError: function (ptr, len) {
                let arr8 = new Uint8Array(memory.buffer.slice(ptr, ptr+len));
                const message = text_decoder.decode(arr8);
                throw new Error(message)
              },              
            memory: memory,
        }
    };
    WebAssembly.instantiateStreaming(fetch(wasm_file), imports).then(result => {
        console.log("Loaded the WASM!");
        ZigMachine = result.instance.exports;
        console.log(ZigMachine);

        // boot the Zig Machine
        ZigMachine.boot();

        start();
    });
};

window.document.body.addEventListener('keydown', function(evt){

    if ((evt.key == "w") || (evt.key == "ArrowUp"))
	    ZigMachine.input(0);
    if ((evt.key == "s") || (evt.key === "ArrowDown"))
	    ZigMachine.input(1);
    if ((evt.key === "a") || (evt.key === "ArrowLeft"))
	    ZigMachine.input(2);
    if ((evt.key === "d" || evt.key === "ArrowRight"))
	    ZigMachine.input(3);

    // Music debug: 1/2/3 test MOD / YM / sample (starts audio on first press).
    if (evt.key === "1") playMod("music/lollapalooza.mod");
    if (evt.key === "2") playYm("music/concerto.ymraw");
    if (evt.key === "3") playRaw("music/smp1.raw", 12517, false);
});

// --------------------------------------------------------------------------
// Audio: AudioWorklet running audio.wasm on the audio thread.
// The "Sound on" button calls main() (a user gesture, required to start audio).
// --------------------------------------------------------------------------
let audioCtx = null;
let audioNode = null;
let audioReady = null; // promise, resolves once the worklet is ready

// Start the AudioContext + worklet once (idempotent). Must be called from a user
// gesture (button click or keydown). Does NOT auto-play anything.
function startAudio() {
    if (audioReady) return audioReady;
    audioReady = (async () => {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
        const wasmBytes = await fetch("audio.wasm").then(r => r.arrayBuffer());
        await audioCtx.audioWorklet.addModule("audio-worklet.js");
        audioNode = new AudioWorkletNode(audioCtx, "zig-audio", {
            numberOfInputs: 0,
            numberOfOutputs: 1,
            outputChannelCount: [2],
            processorOptions: { wasmBytes: wasmBytes },
        });
        await new Promise((resolve) => {
            audioNode.port.onmessage = (event) => {
                const msg = event.data;
                if (msg.type === "ready") { console.log("Audio worklet ready"); resolve(); }
                else if (msg.type === "error") console.error("Audio worklet error:", msg.message);
                else if (msg.type === "audioState") {
                    // mirror chip regs + player mode + per-channel scopes into the scene
                    if (ZigMachine.getYmRegsPointer) {
                        new Uint8Array(memory.buffer, ZigMachine.getYmRegsPointer(), 16).set(msg.regs);
                    }
                    if (ZigMachine.getAudioModePointer) {
                        new Uint8Array(memory.buffer, ZigMachine.getAudioModePointer(), 1)[0] = msg.mode;
                    }
                    if (ZigMachine.getScopesPointer && msg.scopes) {
                        const len = msg.scopes[0].length;
                        const flat = new Float32Array(memory.buffer, ZigMachine.getScopesPointer(), 4 * len);
                        for (let ch = 0; ch < 4; ch++) flat.set(msg.scopes[ch], ch * len);
                    }
                } else if (msg.type === "modLoaded" || msg.type === "ymLoaded" || msg.type === "rawLoaded")
                    console.log(msg.type, msg);
            };
        });
        audioNode.connect(audioCtx.destination);
        await audioCtx.resume();
    })();
    return audioReady;
}

// "Sound on" button: toggle audio; when turning on, default to the MOD.
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

// Play helpers — each ensures audio is started first, so they work straight from
// a keypress. Players are exclusive (loading one stops the others).
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
// Stream a raw 8-bit PCM file (guess rate by ear). unsigned=true for 0..255 data.
async function playRaw(url, rate, unsigned) {
    await startAudio();
    const bytes = await fetch(url).then(r => r.arrayBuffer());
    audioNode.port.postMessage({ type: "loadRaw", bytes: bytes, rate: rate || 12517, unsigned: !!unsigned }, [bytes]);
    const b = document.querySelector('.sound_button'); if (b) b.textContent = "Sound off";
}
window.playMod = playMod;
window.playYm = playYm;
window.playRaw = playRaw;