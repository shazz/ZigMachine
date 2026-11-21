// Headless check: the stereo PCM stream (system table 1.27, libs/zig/audio_stereo.zig, decisions.md 2026-11-20).
//
// The real worklet (docs/audio-worklet-sealed.js, a stand-in AudioWorkletProcessor) over the real
// demo-audio.wasm + machine-audio.wasm, driven by the messages docs/sealed-loader.js posts:
//   1. stereo: a 1 kHz tone fed on the LEFT side only comes out of the left speaker, the right is
//      exactly 0; then the same tone on the RIGHT only, the left is exactly 0; both sides at once
//      come out the same size, each with its own tone (their correlation is ~0).
//   2. the sample counter (zg.audioStreamPlayed): after N rendered samples it equals
//      floor(N * step / 65536), step = rate * 65536 / 44100 (the channel's own 16.16 step), for the
//      stereo and the mono stream, it is in the worklet's audioState, and it reads 0 after a stop.
//   3. the mono stream is unchanged: a mono feed plays the same on both sides (centred).
//   4. old carts: the loader's env has every 1.27 import; a cart built before them imports none.
//
//   node apps/stereo_stream_check.mjs [--break swap]   # --break: the worklet's feedRing swaps L and R
import { readFile } from "node:fs/promises";

const RATE = 22050, RING = 32768, BLOCK = 128;
const BREAK = process.argv.includes("--break");
const errors = [];
const expect = (ok, what) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) errors.push(what); };

async function bootWorklet() { // as apps/st_replay_outputs_check.mjs
    let Proc;
    const posted = [];
    globalThis.AudioWorkletProcessor = class { constructor() { this.port = { postMessage: (m) => posted.push(m) }; } };
    globalThis.registerProcessor = (_name, cls) => { Proc = cls; };
    await import("../docs/audio-worklet-sealed.js");
    const p = new Proc({ processorOptions: {
        machineBytes: await readFile("docs/machine-audio.wasm"), demoBytes: await readFile("docs/demo-audio.wasm") } });
    for (let i = 0; i < 200 && !p.ready; i++) await new Promise((r) => setTimeout(r, 10));
    if (!p.ready) throw new Error("the worklet never came up");
    if (BREAK) { // the mutant: every frame's two sides written into the other side's ring
        const feed = p.feedRing;
        p.feedRing = function (src, stereo) {
            if (!stereo) return feed.call(this, src, stereo);
            const sw = new Uint8Array(src.length);
            for (let i = 0; i + 1 < src.length; i += 2) { sw[i] = src[i + 1]; sw[i + 1] = src[i]; }
            return feed.call(this, sw, stereo);
        };
    }
    const send = (data) => p.port.onmessage({ data });
    const render = (blocks) => { // `blocks` of 128 frames, both sides
        const L = new Float32Array(blocks * BLOCK), R = new Float32Array(blocks * BLOCK);
        const l = new Float32Array(BLOCK), r = new Float32Array(BLOCK);
        for (let b = 0; b < blocks; b++) { p.process([], [[l, r]]); L.set(l, b * BLOCK); R.set(r, b * BLOCK); }
        return { L, R };
    };
    return { p, send, render, posted };
}

const tone = (n, period, amp) => Int8Array.from({ length: n }, (_, i) => (Math.floor(i / (period / 2)) & 1 ? amp : -amp));
function frames(left, right) { // interleaved L,R signed 8-bit, as zg.audioFeedStereo takes them
    const out = new Uint8Array(2 * left.length);
    for (let i = 0; i < left.length; i++) { out[2 * i] = left[i] & 0xff; out[2 * i + 1] = right[i] & 0xff; }
    return out;
}
const peak = (a) => a.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
const energy = (a) => a.reduce((s, v) => s + v * v, 0);
const corr = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0) / Math.sqrt(energy(a) * energy(b) || 1);

function startStereo(w, left, right) {
    w.send({ type: "streamStart", rate: RATE, channels: 2 });
    w.send({ type: "streamFeed", bytes: frames(left, right).buffer, channels: 2 });
}

function checkSides(w) {
    const n = 8000, quiet = new Int8Array(n), a = tone(n, 22, 90), b = tone(n, 14, 90); // ~1 kHz, ~1.6 kHz
    startStereo(w, a, quiet);
    let o = w.render(100);
    expect(peak(o.L) > 0.2 && o.R.every((v) => v === 0), `left only: the left plays (peak ${peak(o.L).toFixed(3)}), the right is exactly 0 (peak ${peak(o.R).toFixed(3)})`);
    startStereo(w, quiet, a);
    o = w.render(100);
    expect(peak(o.R) > 0.2 && o.L.every((v) => v === 0), `right only: the right plays (peak ${peak(o.R).toFixed(3)}), the left is exactly 0 (peak ${peak(o.L).toFixed(3)})`);
    startStereo(w, a, b);
    o = w.render(100);
    const ratio = energy(o.L) / (energy(o.R) || 1);
    expect(ratio > 0.8 && ratio < 1.25 && Math.abs(corr(o.L, o.R)) < 0.3,
        `both: the two sides as loud (${ratio.toFixed(3)}), each its own tone (correlation ${corr(o.L, o.R).toFixed(3)})`);
}

function checkCounter(w) {
    const step = Math.floor(RATE * 65536 / 44100), n = 40 * BLOCK;
    startStereo(w, tone(RING, 22, 50), tone(RING, 22, 50));
    w.render(40);
    const d = w.p.demo;
    expect(d.audioStreamPlayed() === Math.floor(n * step / 65536), `stereo counter: ${d.audioStreamPlayed()} after ${n} samples = floor(n x ${step} / 65536)`);
    let st = null, now = -1; // the block that posts an audioState: its counter is the one after that block
    for (let b = 0; b < 4 && !st; b++) {
        w.posted.length = 0;
        w.render(1);
        st = w.posted.find((m) => m.type === "audioState") || null;
        now = d.audioStreamPlayed();
    }
    expect(st && st.streamPlayed === now && now > 0, `the counter is in the worklet's audioState (${st?.streamPlayed} = ${now})`);
    w.send({ type: "streamStop" });
    w.render(4);
    expect(d.audioStreamPlayed() === 0, "after a stop the counter reads 0");
    const mono = Math.trunc(Math.fround(Math.fround(RATE / 44100) * 65536)); // demo_audio_raw.zig's f32 step
    w.send({ type: "streamStart", rate: RATE });
    w.render(10);
    expect(d.audioStreamPlayed() === Math.floor(10 * BLOCK * mono / 65536), `mono counter: ${d.audioStreamPlayed()} after ${10 * BLOCK} samples`);
    w.send({ type: "streamStart", rate: 500, channels: 2 }); // outside 1000..50066: nothing starts
    w.render(4);
    expect(d.audioStreamPlayed() === 0 && d.audioMode() === 0, "a stereo rate outside 1000..50066 starts nothing (counter 0, mode 0)");
}

function checkMono(w) {
    w.send({ type: "streamStart", rate: RATE });
    w.send({ type: "streamFeed", bytes: Uint8Array.from(tone(8000, 22, 90), (v) => v & 0xff).buffer });
    const o = w.render(100);
    expect(peak(o.L) > 0.2 && o.L.every((v, i) => v === o.R[i]), "mono: the one ring plays the same on both sides (centred)");
    w.send({ type: "streamStop" });
}

async function checkImports() {
    const loader = await readFile("docs/sealed-loader.js", "utf8");
    const names = ["hostAudioStreamStartStereo", "hostAudioFeedStereo", "hostAudioStreamPlayed"];
    expect(names.every((n) => loader.includes(`${n}: (`)), "the loader's env has the three 1.27 imports");
    const imports = async (f) => WebAssembly.Module.imports(new WebAssembly.Module(await readFile(f))).map((i) => i.name);
    const mono = await imports("docs/demo-st_replay.wasm"); // a mono streamer that never calls the 1.27 API
    expect(mono.includes("hostAudioFeed") && !names.some((n) => mono.includes(n)),
        "a mono cart (st_replay) imports the 1.1 stream only: it still runs on a 1.26 system");
    const stereo = await imports("docs/demo-stream.wasm"); // STREAM's S key (the board check)
    expect(names.every((n) => stereo.includes(n)), "the STREAM cart (its S key) imports the three 1.27 entries");
}

const w = await bootWorklet();
checkSides(w);
checkCounter(w);
checkMono(w);
await checkImports();
if (BREAK) { // the mutant must be caught: a FAIL here is the pass
    const hit = errors.some((e) => e.startsWith("left only") || e.startsWith("right only"));
    console.log(hit ? "stereo_stream: PASS (--break swap caught)" : "stereo_stream: FAILED -- --break swap not caught");
    process.exit(hit ? 0 : 1);
}
if (errors.length) {
    console.log(`FAIL: ${errors.length} check(s)`);
    process.exit(1);
}
console.log("stereo stream: L and R come out on their own sides, the counter follows the channel ✅");
