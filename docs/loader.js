var memory = new WebAssembly.Memory({
    initial: 20 /* pages */,
    maximum: 20 /* pages */,
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
    var wasmMemoryArray = new Uint8Array(memory.buffer);

    console.log("Main function started");
    console.log(memory.buffer);

    // get buffer nb
    const nb_buffers = ZigMachine.getPlanesNumber();
    const fb_width = ZigMachine.getPhysicalFrameBufferWidth();
    const fb_height = ZigMachine.getPhysicalFrameBufferHeight();

    var loop = function(timestamp) {
       
        elapsed_time = (timestamp - last_timestamp);
        last_timestamp = timestamp;
        fps = 1000/elapsed_time;
        document.title = "FPS:" + fps.toFixed(2);
        
        // in case WASM grew the memory due to zig heap_page dynamic allocation calls
        if(wasmMemoryArray == null)
            wasmMemoryArray = new Uint8Array(memory.buffer);        

        ZigMachine.clearPhysicalFrameBuffer();

        ZigMachine.frame(elapsed_time);

        for(i=0; i<nb_buffers; i++) {

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