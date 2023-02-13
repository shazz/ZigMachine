/**
 * Global Variables
 */
let memory = new WebAssembly.Memory({
    initial: 32 /* pages */,
    maximum: 32 /* pages */,
});

/**
 * audio context
 */
const SAMPLING_RATE = 44100;
let audioContext = null;
let audioNode = null;
let audioGain = null;


// WASM
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

export let ZigMachine = {
    'boot': null,
    'frame': null,
    'getPlanesNumber': null,
    'getPhysicalFrameBufferWidth': null,
    'getPhysicalFrameBufferHeight': null,
    'getPhysicalFrameBufferPointer': null,
    'renderPhysicalFrameBuffer': null,
    'clearPhysicalFrameBuffer': null,
    "isPlaneEnabled": null,
    'input': null,
	'getLeftSoundBufferPointer': null,
	'getRightSoundBufferPointer': null,
    'generateAudio': null,	
	'getAudioBufferSize': null,
}

/**
 * Module functions
 */

/**
 * Stop Audio
 */
export async function stop_audio() {

	if(audioGain != null) audioGain.disconnect();
    if(audioNode != null) audioNode.disconnect();
	if(audioContext != null) audioContext.close();

    // force GC
	audioGain = null;
	audioNode = null;
    audioContext = null;
}

/**
 * Start Audio
 */
export async function start_audio() {

	stop_audio();

	const audio_buffer_size = ZigMachine.getAudioBufferSize();
	const f32LeftArray_ptr = ZigMachine.getLeftSoundBufferPointer();

	audioContext = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: SAMPLING_RATE });
	audioNode = audioContext.createScriptProcessor(audio_buffer_size, 0, 2);
	
	console.log("start_audio: Audio buffer ptr: 0x" + Number(f32LeftArray_ptr).toString(16));

	// feedOutCount = 0;
    let stop = false;
	console.log("add audio event listener");
    audioNode.onaudioprocess = function(ev) {

        if(stop) {
            stop_audio();
            return;
        }

		// get F32 buffer from WASM memory
		const f32LeftArray = new Float32Array(memory.buffer.slice(f32LeftArray_ptr,	f32LeftArray_ptr + (audio_buffer_size*4)));		
		
		ZigMachine.generateAudio();

		// console.log(f32Array);
		ev.outputBuffer.getChannelData(0).set(f32LeftArray);
		ev.outputBuffer.getChannelData(1).set(f32LeftArray);
	};
	audioGain = audioContext.createGain();
	audioNode.connect(audioGain);
    audioGain.connect(audioContext.destination);
	audioGain.gain.setValueAtTime(1, audioContext.currentTime);
}

/**
 * Toggle sound
 */
export async function toggle_sound() {
    if (!audioContext) {
        start_audio();
    } 
    else {
        stop_audio();
    }
}
 
/**
 * Change channel
 */
export async function change_channel() {

    wasm_file = list_channels[current_channel];
    onload();
}

/**
 * Next channel
 */
export async function next_channel() {

    current_channel += 1;
    if(current_channel == list_channels.length) current_channel = 0;
    change_channel();
}

/**
 * Previous channel
 */
export async function previous_channel() {

    current_channel -= 1;
    if(current_channel <= 0) current_channel = (list_channels.length)-1;
    change_channel();
}

/**
 * ZigMachine Start
 */
export async function start() {

    // clear current channel
    if(requestId) {
        window.cancelAnimationFrame(requestId);
        for(var i=0; i < 4; i++){
            const canvas = document.getElementById(i);
            const context = canvas.getContext("2d");
            context.clearRect(0, 0, canvas.width, canvas.height);
        }
    }

    var last_timestamp = 0;
    var wasmMemoryArray = new Uint8Array(memory.buffer);

    console.log("Main function started");
    console.log(memory.buffer);

    // get buffer nb
    const nb_buffers = ZigMachine.getPlanesNumber();
    const fb_width = ZigMachine.getPhysicalFrameBufferWidth();
    const fb_height = ZigMachine.getPhysicalFrameBufferHeight();

    var loop = function(timestamp) {
       
        var elapsed_time = (timestamp - last_timestamp);
        var last_timestamp = timestamp;
        var fps = 1000/elapsed_time;
        document.title = "FPS:" + fps.toFixed(2);
        
        // in case WASM grew the memory due to zig heap_page dynamic allocation calls
        if(wasmMemoryArray == null)
            wasmMemoryArray = new Uint8Array(memory.buffer);        

        ZigMachine.clearPhysicalFrameBuffer();

        ZigMachine.frame(elapsed_time);

        for(var i=0; i<nb_buffers; i++) {

            if(ZigMachine.isPlaneEnabled(i)) {
                const canvas = document.getElementById(i);
                const context = canvas.getContext("2d");
                const imageData = context.createImageData(canvas.width, canvas.height);
        
                ZigMachine.renderPhysicalFrameBuffer(i);
        
                const bufferOffset = ZigMachine.getPhysicalFrameBufferPointer();
                const imageDataArray = wasmMemoryArray.slice(
                    bufferOffset,
                    bufferOffset + fb_width * fb_height * 4
                );
                imageData.data.set(imageDataArray);
        
                context.putImageData(imageData, 0, 0);
            }
        }
        // loop to next frame
        requestId = window.requestAnimationFrame(loop);
    };
    loop();
};


window.document.body.onload = function() {
    const text_decoder = typeof TextDecoder !== 'undefined' && new TextDecoder();
    let console_log_buffer = "";    

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


window.toggle_sound = toggle_sound;
window.start_audio = start_audio;
window.next_channel = next_channel;
window.previous_channel = previous_channel;