var memory = new WebAssembly.Memory({
    initial: 20 /* pages */,
    maximum: 20 /* pages */,
});

const text_decoder = new TextDecoder();
let console_log_buffer = "";
let audioContext = null;

var ZigMachine = {
    'boot': null,
    'frame': null,
    'getPhysicalFrameBufferNb': null,
    'getPhysicalFrameBufferWidth': null,
    'getPhysicalFrameBufferHeight': null,
    'getPhysicalFrameBufferPointer': null,
    'renderPhysicalFrameBuffer': null,
    'u8ArrayToF32Array': null,
    'generateAudio': null,
    'input': null,
}

var start = function() {

    var wasmMemoryArray = new Uint8Array(memory.buffer);

    console.log("Main function started");
    console.log(memory.buffer);

    // get buffer nb
    const nb_buffers = ZigMachine.getPhysicalFrameBufferNb();
    const fb_width = ZigMachine.getPhysicalFrameBufferWidth();
    const fb_height = ZigMachine.getPhysicalFrameBufferHeight();

    var loop = function() {
       
        // in case WASM grew the memory due to zig heap_page dynmaic allocation calls
        if(wasmMemoryArray == null)
            wasmMemoryArray = new Uint8Array(memory.buffer);        

        ZigMachine.frame();

        for(i=0; i<nb_buffers; i++) {
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

        // loop to next frame
        window.requestAnimationFrame(loop);
    
    };
    loop();
};

window.document.body.onload = function() {
    var imports = { 
        env: {
            // Useful for debugging on zig's side
            consoleLogJS: (arg, len) => {
                let arr8 = new Uint8Array(memory.buffer.slice(arg, arg+len));
                console.log(new TextDecoder().decode(arr8));
            },
            jsConsoleLogWrite: function (ptr, len) {
                let arr8 = new Uint8Array(memory.buffer.slice(ptr, ptr+len));
                console_log_buffer += text_decoder.decode(arr8);
            },
            jsConsoleLogFlush: function () {
                console.log(console_log_buffer);
                console_log_buffer = "";
            },   
            memory: memory,
        }
    };
    WebAssembly.instantiateStreaming(fetch("bootloader.wasm"), imports).then(result => {
        console.log("Loaded the WASM!");
        ZigMachine = result.instance.exports;

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