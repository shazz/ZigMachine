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
});

// --------------------------------------------------------------------------
// Audio: AudioWorklet running audio.wasm on the audio thread.
// The "Sound on" button calls main() (a user gesture, required to start audio).
// --------------------------------------------------------------------------
let audioCtx = null;
let audioNode = null;

async function main() {
    const button = document.querySelector('.sound_button');

    // toggle off
    if (audioCtx) {
        try { await audioCtx.close(); } catch (e) {}
        audioCtx = null;
        audioNode = null;
        if (button) button.textContent = "Sound on";
        return;
    }

    audioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
    const wasmBytes = await fetch("audio.wasm").then(r => r.arrayBuffer());
    await audioCtx.audioWorklet.addModule("audio-worklet.js");

    audioNode = new AudioWorkletNode(audioCtx, "zig-audio", {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2],
        processorOptions: { wasmBytes: wasmBytes },
    });
    audioNode.port.onmessage = (event) => {
        const msg = event.data;
        if (msg.type === "ready") console.log("Audio worklet ready");
        else if (msg.type === "error") console.error("Audio worklet error:", msg.message);
    };
    audioNode.connect(audioCtx.destination);
    await audioCtx.resume();

    if (button) button.textContent = "Sound off";
}
window.main = main;