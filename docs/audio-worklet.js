// --------------------------------------------------------------------------
// ZigMachine audio worklet
//
// Runs on the dedicated audio thread. It instantiates audio.wasm HERE (the wasm
// bytes are handed in via processorOptions) so all DSP happens off the main
// thread and stays glitch-free even when a heavy demo pegs the main thread.
//
// Each process() call asks the Zig engine to render exactly `frames` stereo
// samples, then copies them straight out of wasm linear memory to the outputs.
// --------------------------------------------------------------------------
class ZigAudioProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super();
        this.ready = false;
        this.instance = null;
        this.left = null;
        this.right = null;

        const bytes = options.processorOptions.wasmBytes;
        // audio.wasm owns its memory and has no host imports.
        WebAssembly.instantiate(bytes, {}).then((result) => {
            const inst = result.instance;
            this.instance = inst;
            inst.exports.audioInit();

            const mem = inst.exports.memory;
            const maxFrames = inst.exports.audioMaxFrames();
            this.left = new Float32Array(mem.buffer, inst.exports.audioLeftPtr(), maxFrames);
            this.right = new Float32Array(mem.buffer, inst.exports.audioRightPtr(), maxFrames);

            this.ready = true;
            this.port.postMessage({ type: "ready" });
        }).catch((err) => {
            this.port.postMessage({ type: "error", message: String(err) });
        });

        // control channel (test tone now; play/stop/load later)
        this.port.onmessage = (event) => {
            const msg = event.data;
            if (!this.instance) return;
            if (msg.type === "testTone") {
                this.instance.exports.audioSetTestTone(msg.on ? 1 : 0, msg.hz);
            }
        };
    }

    process(inputs, outputs) {
        if (!this.ready) return true;

        const out = outputs[0];
        const frames = out[0].length; // typically 128
        this.instance.exports.audioRender(frames);

        out[0].set(this.left.subarray(0, frames));
        if (out.length > 1) {
            out[1].set(this.right.subarray(0, frames));
        }
        return true;
    }
}

registerProcessor("zig-audio", ZigAudioProcessor);
