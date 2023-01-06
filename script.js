
var memory = new WebAssembly.Memory({
    initial: 50 /* pages */,
    maximum: 100 /* pages */,
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

    const drawframebuffer = (canvas_id) => {
        const fb_width = 320;
        const fb_height = 200;

        // in case WASM grew the memory due to zig heap_page dynmaic allocation calls
        if(wasmMemoryArray == null)
            wasmMemoryArray = new Uint8Array(memory.buffer);        

        const canvas = document.getElementById(canvas_id);
        const context = canvas.getContext("2d");
        const imageData = context.createImageData(canvas.width, canvas.height);
        context.clearRect(0, 0, canvas.width, canvas.height);

        result.instance.exports.renderPhysicalFrameBuffer(parseInt(canvas_id));

        const bufferOffset = result.instance.exports.getPhysicalFrameBufferPointer();
        const imageDataArray = wasmMemoryArray.slice(
            bufferOffset,
            bufferOffset + fb_width * fb_height * 4
        );
        imageData.data.set(imageDataArray);

        context.clearRect(0, 0, canvas.width, canvas.height);
        context.putImageData(imageData, 0, 0);
    };

    // boot the Zig Machine
    result.instance.exports.boot();

    // draw the first FB
    drawframebuffer("0");
    runFrame();

    // Check memory
    console.log(memory.buffer);

    // Start the VBL loop
    setInterval(() => {
        runFrame();
        drawframebuffer("0");
        drawframebuffer("1");
        drawframebuffer("2");
        drawframebuffer("3");
    }, 20);
});
