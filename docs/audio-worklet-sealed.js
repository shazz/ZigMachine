// --------------------------------------------------------------------------
// ZigMachine SEALED audio worklet (audio thread).
//
// Instantiates TWO wasm modules over ONE shared WebAssembly.Memory:
//   - machine-audio.wasm : the sealed chips (Paula + YM2149). Exports machine*.
//   - demo-audio.wasm     : the open ZigOS players (MOD/YM/raw). Exports audio*.
//
// The players drive the chips only through the imported machine* ops (wired
// below). Per process() block: demo.audioRender(frames) runs the player's tick
// loop, calling the sealed chip to mix; we then copy the stereo buffers out.
// --------------------------------------------------------------------------
const AUDIO_PAGES = 48; // must match src/sdk/audio.zig AUDIO_PAGES

class ZigAudioSealedProcessor extends AudioWorkletProcessor {
    constructor(options) {
        super();
        this.ready = false;
        this.tick = 0;

        const { machineBytes, demoBytes } = options.processorOptions;
        (async () => {
            const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
            const machine = (await WebAssembly.instantiate(machineBytes, { env: { memory } })).instance;
            const mx = machine.exports;

            // Route the open players' chip imports to the sealed machine's exports.
            const demoImports = { env: {
                memory,
                machineAudioInit: mx.machineAudioInit,
                machineClear: mx.machineClear,
                machineClamp: mx.machineClamp,
                machineMixPaula: mx.machineMixPaula,
                machineRenderYm: mx.machineRenderYm,
                machineYmWrite: mx.machineYmWrite,
                machinePaulaClearScopes: mx.machinePaulaClearScopes,
                machinePaulaTrigger: mx.machinePaulaTrigger,
                machinePaulaSetStep: mx.machinePaulaSetStep,
                machinePaulaSetVolume: mx.machinePaulaSetVolume,
                machinePaulaSetPan: mx.machinePaulaSetPan,
                machinePaulaSetPos: mx.machinePaulaSetPos,
                machinePaulaSetActive: mx.machinePaulaSetActive,
            } };
            const demo = (await WebAssembly.instantiate(demoBytes, demoImports)).instance;

            this.machine = mx;
            this.demo = demo.exports;
            this.memory = memory;
            this.demo.audioInit();

            const maxFrames = mx.audioMaxFrames();
            this.left = new Float32Array(memory.buffer, mx.audioLeftPtr(), maxFrames);
            this.right = new Float32Array(memory.buffer, mx.audioRightPtr(), maxFrames);
            this.ymRegs = new Uint8Array(memory.buffer, mx.audioYmRegsPtr(), 16);
            this.scopeLen = mx.audioScopeLen();
            this.scopes = [0, 1, 2, 3].map((ch) =>
                new Float32Array(memory.buffer, mx.audioScopePtr(ch), this.scopeLen));

            this.ready = true;
            this.port.postMessage({ type: "ready" });
        })().catch((err) => this.port.postMessage({ type: "error", message: String(err) }));

        this.port.onmessage = (event) => {
            const msg = event.data;
            if (!this.demo) return;
            const d = this.demo, mem = this.memory;
            const writeSong = (bytes) => {
                const cap = d.audioSongCapacity();
                const dst = new Uint8Array(mem.buffer, d.audioSongPtr(), cap);
                const src = new Uint8Array(bytes);
                const len = Math.min(src.length, cap);
                dst.set(src.subarray(0, len));
                return len;
            };
            if (msg.type === "loadMod") {
                const len = writeSong(msg.bytes);
                const ok = d.audioLoadMod(len);
                if (ok) d.audioModPlay();
                this.port.postMessage({ type: "modLoaded", ok: !!ok, len: len });
            } else if (msg.type === "loadYm") {
                const len = writeSong(msg.bytes);
                const ok = d.audioLoadYm(len);
                if (ok) d.audioYmPlay();
                this.port.postMessage({ type: "ymLoaded", ok: !!ok, len: len });
            } else if (msg.type === "loadRaw") {
                const len = writeSong(msg.bytes);
                d.audioPlayRaw(len, msg.rate, msg.unsigned ? 1 : 0);
                this.port.postMessage({ type: "rawLoaded", len: len });
            } else if (msg.type === "modStop") {
                d.audioModStop();
            } else if (msg.type === "ymStop") {
                d.audioYmStop();
            }
        };
    }

    process(inputs, outputs) {
        if (!this.ready) return true;

        const out = outputs[0];
        const frames = out[0].length; // typically 128
        this.demo.audioRender(frames);

        out[0].set(this.left.subarray(0, frames));
        if (out.length > 1) out[1].set(this.right.subarray(0, frames));

        if ((this.tick++ & 3) === 0) {
            this.port.postMessage({
                type: "audioState",
                mode: this.demo.audioMode(),
                regs: Array.from(this.ymRegs.subarray(0, 14)),
                scopes: this.scopes.map((s) => Array.from(s)),
            });
        }
        return true;
    }
}

registerProcessor("zig-audio-sealed", ZigAudioSealedProcessor);
