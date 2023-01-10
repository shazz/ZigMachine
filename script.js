
var memory = new WebAssembly.Memory({
    initial: 21 /* pages */,
    maximum: 21 /* pages */,
});

const text_decoder = new TextDecoder();
let console_log_buffer = "";
let audioContext = null;

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

function allocateTo(alloced, size) {
    const mod = alloced % size;
    if (mod != 0){
		alloced += size - mod;
    }
    return alloced;
}

async function main(){
    var sampleRate = 44100;
    audioContext = new AudioContext({sampleRate});
}

WebAssembly.instantiateStreaming(fetch("bootloader.wasm"), importObject).then((result) => {
    var wasmMemoryArray = new Uint8Array(memory.buffer);
    var audioContext;
    var bufferSource;
    var u8Array;
    var f32Array;
    var audioBuffer;

    var sampleRate = 44100;
    var secondsLength = 1/50;

    const initSoundBuffer = () => {
		let allocatorIndex=0;
		
        audioContext = new AudioContext({sampleRate});
        allocatorIndex = allocateTo(allocatorIndex, 2);

        u8Array = new Uint8Array(memory.buffer, allocatorIndex, audioContext.sampleRate * secondsLength);
        console.log("Created U8 array in WASM memory of " + u8Array.length + " bytes. Expected " + (audioContext.sampleRate * secondsLength) + " bytes from offset " + allocatorIndex);
        allocatorIndex += u8Array.length;

        allocatorIndex = allocateTo(allocatorIndex, 4);
        f32Array = new Float32Array(memory.buffer, allocatorIndex, audioContext.sampleRate * secondsLength);
        console.log("Created F32 array in WASM memory of " + f32Array.length + " bytes. Expected " + (audioContext.sampleRate * secondsLength) + " bytes from offset " + allocatorIndex);
        allocatorIndex += f32Array.length * 4;
        
        audioBuffer = audioContext.createBuffer(
            1,
            audioContext.sampleRate * secondsLength,
            audioContext.sampleRate
        );

        // 
        bufferSource = audioContext.createBufferSource();
        bufferSource.buffer = audioBuffer;
        bufferSource.connect(audioContext.destination);
        bufferSource.start();

        bufferSource.onended = () => {
            console.log("buffer source ended.");
        };        
    }

    const generateSoundBuffer = () => {

        //console.log("Generate audio for " + u8Array.length + " bytes");
        // Ask zig to create the samples
        result.instance.exports.generateAudio(
            u8Array.byteOffset, u8Array.length,
        );

        // console.log(u8Array);
        
        // copy the sound to Float 32 because webassembly faster we can't just pass the audioBuffer's buffer directly because
        // webassembly can only access memory it owns
        result.instance.exports.u8ArrayToF32Array(
            u8Array.byteOffset, u8Array.length,
            f32Array.byteOffset, f32Array.length);


        audioBuffer = audioContext.createBuffer(
            1,
            audioContext.sampleRate * secondsLength,
            audioContext.sampleRate
        );

        // copy the Float 32 to the audio context
        audioBuffer.getChannelData(0).set(f32Array);
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


    // Init sound buffer 
    initSoundBuffer();

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
        generateSoundBuffer();
    }, 20);
});
