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
        this.ringWrite = 0; // streamFeed write cursor into the 32 KiB ring at SONG_BASE

        const { machineBytes, demoBytes } = options.processorOptions;
        (async () => {
            const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
            const machine = (await WebAssembly.instantiate(machineBytes, { env: { memory } })).instance;
            const mx = machine.exports;

            // Route the open players' chip imports to the sealed machine's exports.
            //
            // Spread by PREFIX rather than listing the names. This was a
            // hand-maintained list, and it desynced the moment the audio ABI grew
            // a function (machineAudioReset): the open module imported a name the
            // list did not provide, so demo-audio.wasm failed to LINK and ALL
            // sound died -- "Import #7 env machineAudioReset: requires a callable".
            // Nothing else broke and nothing else reported, which is why it read
            // as "audio is gone" rather than as a build error. apps/sndh_headless.mjs
            // already built its imports this way, which is exactly why the gate
            // stayed green while the browser was silent: the harness could not
            // reproduce a mistake it was structurally incapable of making.
            const demoImports = { env: { memory } };
            for (const name of Object.keys(mx)) {
                if (name.startsWith("machine")) demoImports.env[name] = mx[name];
            }
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
                // A start BPM other than ProTracker's 125 (zg.requestModBpm); 0 = 125.
                if (ok && msg.bpm) d.audioModPlayBpm(msg.bpm);
                else if (ok) d.audioModPlay();
                this.port.postMessage({ type: "modLoaded", ok: !!ok, len: len });
            } else if (msg.type === "loadYm") {
                const len = writeSong(msg.bytes);
                const ok = d.audioLoadYm(len);
                if (ok) d.audioYmPlay();
                this.port.postMessage({ type: "ymLoaded", ok: !!ok, len: len });
            } else if (msg.type === "loadSndh") {
                // An SNDH is 68000 code; the cart depacks it (Pack-Ice) and runs
                // it on its own CPU. Subtune numbers count from 1.
                const len = writeSong(msg.bytes);
                const ok = d.audioLoadSndh(len);
                if (ok) d.audioSndhPlay(msg.tune || 0);
                this.port.postMessage({ type: "sndhLoaded", ok: !!ok, len: len,
                                        stuckPc: d.audioSndhStuckPc(), trap: d.audioSndhUnhandledTrap() });
            } else if (msg.type === "loadRaw") {
                const len = writeSong(msg.bytes);
                d.audioPlayRaw(len, msg.rate, msg.unsigned ? 1 : 0);
                this.port.postMessage({ type: "rawLoaded", len: len });
            } else if (msg.type === "streamStart") {
                d.audioStreamStart(msg.rate);
                this.ringWrite = 0;
            } else if (msg.type === "streamStop") {
                d.audioStreamStop();
                this.ringWrite = 0;
            } else if (msg.type === "streamFeed") {
                // Append signed-8-bit bytes into the ring at SONG_BASE, wrapping at
                // RING (must match STREAM_RING in demo_audio_main.zig).
                const RING = 32768;
                const ring = new Uint8Array(mem.buffer, d.audioSongPtr(), RING);
                const src = new Uint8Array(msg.bytes);
                for (let i = 0; i < src.length; i++) {
                    ring[this.ringWrite] = src[i];
                    this.ringWrite = (this.ringWrite + 1) % RING;
                }
            } else if (msg.type === "modStop") {
                d.audioModStop();
            } else if (msg.type === "ymStop") {
                d.audioYmStop();
            } else if (msg.type === "beep") {
                // Boot-sector "bo-bip!": YM2149 channel A plays a low note then a higher
                // one, ~80 ms each, then auto-silences. process() advances the timing.
                const m = this.machine;
                m.machineYmWrite(0, 0x70); m.machineYmWrite(1, 0x04); // note 1 (low): period ~0x470
                m.machineYmWrite(7, 0x3e);                            // mixer: tone A on, noise off
                m.machineYmWrite(8, 0x0c);                            // amplitude (fixed)
                this.beep = true; this.bip = 0; this.bipNote = 1;
            } else if (msg.type === "reset") {
                // The machine reclaiming the sound chip when a program ends.
                // Sent by the host on every cart instantiation.
                d.audioReset();
            } else if (msg.type === "beepStop") {
                this.machine.machineYmWrite(8, 0); // silence channel A
                this.beep = false;
            }
        };
    }

    process(inputs, outputs) {
        if (!this.ready) return true;

        const out = outputs[0];
        const frames = out[0].length; // typically 128
        if (this.beep) {
            // "bo-bip!": render ONLY the PSG (no song player) from our YM regs. Advance
            // the two-note timing: note 2 (higher) after ~80 ms, silence after ~160 ms.
            const m = this.machine;
            if (this.bip >= 3600 && this.bipNote === 1) { // ~80 ms @ 44.1 kHz
                m.machineYmWrite(0, 0x30); m.machineYmWrite(1, 0x02); // note 2 (high): period ~0x230
                this.bipNote = 2;
            }
            m.machineClear(frames);
            m.machineRenderYm(0, frames);
            m.machineClamp(frames);
            this.bip += frames;
            if (this.bip >= 7200) { m.machineYmWrite(8, 0); this.beep = false; } // ~160 ms → done
        } else {
            this.demo.audioRender(frames);
        }

        out[0].set(this.left.subarray(0, frames));
        // YM is mono → feed both channels from left while beeping.
        if (out.length > 1) out[1].set((this.beep ? this.left : this.right).subarray(0, frames));

        if ((this.tick++ & 3) === 0) {
            this.port.postMessage({
                type: "audioState",
                mode: this.demo.audioMode(),
                regs: Array.from(this.ymRegs.subarray(0, 14)),
                songMs: this.demo.audioSndhPositionMs ? this.demo.audioSndhPositionMs() : 0,
                scopes: this.scopes.map((s) => Array.from(s)),
            });
        }
        return true;
    }
}

registerProcessor("zig-audio-sealed", ZigAudioSealedProcessor);
