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
            this.ymRegs = new Uint8Array(mem.buffer, inst.exports.audioYmRegsPtr(), 16);
            this.tick = 0;

            this.ready = true;
            this.port.postMessage({ type: "ready" });
        }).catch((err) => {
            this.port.postMessage({ type: "error", message: String(err) });
        });

        // control channel (test tone now; play/stop/load later)
        this.port.onmessage = (event) => {
            const msg = event.data;
            if (!this.instance) return;
            const ex = this.instance.exports;
            if (msg.type === "testTone") {
                ex.audioSetTestTone(msg.on ? 1 : 0, msg.hz);
            } else if (msg.type === "testSample") {
                ex.audioTestSample(msg.ch | 0, msg.on ? 1 : 0, msg.hz);
            } else if (msg.type === "loadMod") {
                const cap = ex.audioSongCapacity();
                const dst = new Uint8Array(ex.memory.buffer, ex.audioSongPtr(), cap);
                const src = new Uint8Array(msg.bytes);
                const len = Math.min(src.length, cap);
                dst.set(src.subarray(0, len));
                const ok = ex.audioLoadMod(len);
                if (ok) ex.audioModPlay();
                this.port.postMessage({ type: "modLoaded", ok: !!ok, len: len });
            } else if (msg.type === "loadYm") {
                const cap = ex.audioSongCapacity();
                const dst = new Uint8Array(ex.memory.buffer, ex.audioSongPtr(), cap);
                const src = new Uint8Array(msg.bytes);
                const len = Math.min(src.length, cap);
                dst.set(src.subarray(0, len));
                const ok = ex.audioLoadYm(len);
                if (ok) ex.audioYmPlay();
                this.port.postMessage({ type: "ymLoaded", ok: !!ok, len: len });
            } else if (msg.type === "modStop") {
                ex.audioModStop();
            } else if (msg.type === "loadRaw") {
                const cap = ex.audioSongCapacity();
                const dst = new Uint8Array(ex.memory.buffer, ex.audioSongPtr(), cap);
                const src = new Uint8Array(msg.bytes);
                const len = Math.min(src.length, cap);
                dst.set(src.subarray(0, len));
                ex.audioPlayRaw(len, msg.rate, msg.unsigned ? 1 : 0);
                this.port.postMessage({ type: "rawLoaded", len: len });
            } else if (msg.type === "ymStop") {
                ex.audioYmStop();
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

        // Mirror YM registers to the main thread ~every 5 blocks (~58 Hz) for the scope.
        if ((this.tick++ & 3) === 0) {
            this.port.postMessage({ type: "ymRegs", regs: Array.from(this.ymRegs.subarray(0, 14)) });
        }
        return true;
    }
}

registerProcessor("zig-audio", ZigAudioProcessor);
