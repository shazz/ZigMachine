
var memory = new WebAssembly.Memory({
    initial: 16 /* pages */,
    maximum: 16 /* pages */,
});

const text_decoder = new TextDecoder();
let console_log_buffer = "";

var importObject = {
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
    },
};

WebAssembly.instantiateStreaming(fetch("bootloader.wasm"), importObject).then((result) => {
    var wasmMemoryArray = new Uint8Array(memory.buffer);

    const runFrame = () => {
        result.instance.exports.frame();
    }

    const drawframebuffers = (nb_buffers) => {
        const fb_width = 320;
        const fb_height = 200;

        // in case WASM grew the memory due to zig heap_page dynmaic allocation calls
        if(wasmMemoryArray == null)
            wasmMemoryArray = new Uint8Array(memory.buffer);        

        result.instance.exports.frame();

        for(i=0; i<nb_buffers; i++) {
            const canvas = document.getElementById(i);
            const context = canvas.getContext("2d");
            const imageData = context.createImageData(canvas.width, canvas.height);
            // context.clearRect(0, 0, canvas.width, canvas.height);
    
            result.instance.exports.renderPhysicalFrameBuffer(i);
    
            const bufferOffset = result.instance.exports.getPhysicalFrameBufferPointer();
            const imageDataArray = wasmMemoryArray.slice(
                bufferOffset,
                bufferOffset + fb_width * fb_height * 4
            );
            imageData.data.set(imageDataArray);
    
            // context.clearRect(0, 0, canvas.width, canvas.height);
            context.putImageData(imageData, 0, 0);
        }
    
    };

    // Check memory
    console.log(memory.buffer);

    // boot the Zig Machine
    result.instance.exports.boot();

    // get buffer nb
    const nb_buffers = result.instance.exports.getPhysicalFrameBufferNb();

    // draw the first FB
    drawframebuffers(nb_buffers);

    // Start the VBL loop
    setInterval(() => {
        drawframebuffers(nb_buffers);
    }, 20);
});
