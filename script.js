var memory = new WebAssembly.Memory({
    initial: 25 /* pages */,
    maximum: 25 /* pages */,
});

var importObject = {
    env: {
        consoleLog: (arg) => console.log(arg), // Useful for debugging on zig's side
        memory: memory,
    },
};

WebAssembly.instantiateStreaming(fetch("bootloader.wasm"), importObject).then((result) => {
    const wasmMemoryArray = new Uint8Array(memory.buffer);

    const drawframebuffer = (canvas_id) => {
        const fb_width = 256;
        const fb_height = 256;

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

    // Check memory
    console.log(memory.buffer);

    // Start the VBL loop
    setInterval(() => {
        drawframebuffer("0");
        drawframebuffer("1");
    }, 20);
});
