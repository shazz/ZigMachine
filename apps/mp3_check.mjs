// MP3 player (libs/zig/players/mp3.zig) on the real audio modules (docs/machine-audio.wasm +
// docs/demo-audio.wasm: the build the page runs, and BARD through wasm2c), fed as a cart feeds it
// (a 64 KiB ring, at most 32 KiB a feed, what it used read back from audioMp3Status(1)):
//   exact     44.1 kHz stereo and mono (apps/zig/assets/mp3/TONES44, MONO44): every output sample, a
//             side, is the reference decode >> 1 (pvmp3 alone, fpga/tools/mp3_ref.sh: the pins below),
//             no underrun, nothing dropped, ended, then silence
//   rates     32 and 48 kHz (TONES32, TONES48): converted to 44.1 (linear, not bit-exact: its output pinned): the rate
//             code, the length in output samples, and > 40 dB against the reference interpolated
//   truncated half the file, then end: the frames decoded are the reference's first frames exactly
//   starved   fed at half speed: underruns counted, every frame still decoded, the stream ends
//   node apps/mp3_check.mjs [--break lowbyte|overfeed|noend]
//     lowbyte: the low-byte channels silenced fail exact; overfeed: no flow control fails (dropped);
//     noend: never telling the player the input ended fails (it never ends)
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";

const DIR = "apps/zig/assets/mp3";
const RING = 64 * 1024, FEED = 32 * 1024, BLOCK = 735;
const PINS = { // sha256 of the reference decode >> 1 (s16le, interleaved; mono: one side), fpga/tools/mp3_ref.sh
    "TONES44.MP3": { pin: "bf403e4f2ee2e764b7a8ce2807f363206f691aad3dc6890b98b2b7d63d2516d9", frames: 308, ch: 2 },
    "MONO44.MP3": { pin: "60138c7b3326d12930690f36e4e0556c7e7b94afafd4bee93a670809e1f0ad14", frames: 155, ch: 1 },
    "TONES32.MP3": { pin: "0e2a505aa6ff835cd915d423d8ebfe6c76141e5409e89be9a0b4f43e08bdbf7d", frames: 113, ch: 2, rate: 32000, code: 1, out: "7e7c32a4a05693e44a429793df9e0ed9bf7293f37cb04b6ea5d1e57cdf5a8450" },
    "TONES48.MP3": { pin: "8a203ce6c992cf0e96c6249fcc1372dd0c6eb700a0eece00135fd6e0842e31af", frames: 168, ch: 2, rate: 48000, code: 3, out: "e2adfc7ee992bc03aef79b8c04042aa538064cc638e5dfecff7b422c9d71df06" },
};
const BREAKS = ["lowbyte", "overfeed", "noend"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

async function modules() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    return { memory, m, a };
}

/** Play `bytes` as a cart would: at most `cap` bytes a block (the ring's room by default), `stopAt` bytes fed then end. */
function play(x, bytes, { cap = FEED, stopAt = bytes.length, maxBlocks = 4000 } = {}) {
    const { a, m, memory } = x;
    a.audioMp3Ctl(0, 0);
    if (broke === "lowbyte") for (const ch of [2, 3]) m.machinePaulaSetVolume(ch, 0);
    const L = [], R = [];
    let fed = 0, ended = false, told = false;
    for (let b = 0; b < maxBlocks && !ended; b++) {
        const used = a.audioMp3Status(1) >>> 0;
        const room = broke === "overfeed" ? FEED : RING - (fed - used);
        const n = Math.min(room, cap, stopAt - fed);
        if (n > 0) {
            new Uint8Array(memory.buffer, a.audioMp3FeedPtr(), n).set(bytes.subarray(fed, fed + n));
            a.audioMp3Feed(n);
            fed += n;
        }
        if (fed >= stopAt && !told && broke !== "noend") { a.audioMp3Ctl(3, 0); told = true; }
        a.audioRender(BLOCK);
        const l = new Float32Array(memory.buffer, m.audioLeftPtr(), BLOCK), r = new Float32Array(memory.buffer, m.audioRightPtr(), BLOCK);
        for (let i = 0; i < BLOCK; i++) { L.push(Math.round(l[i] * 32768)); R.push(Math.round(r[i] * 32768)); }
        ended = (a.audioMp3Status(0) & 3) === 3;
    }
    return { L, R, ended, endAt: L.length, word: a.audioMp3Status(0) >>> 0, frames: a.audioMp3Status(2) >>> 0, dropped: a.audioMp3Dropped() >>> 0 };
}

function sha(samples) {
    return createHash("sha256").update(Buffer.from(Int16Array.from(samples).buffer)).digest("hex");
}

async function exact(name, errors, notes) {
    const p = PINS[name], bytes = new Uint8Array(await readFile(`${DIR}/${name}`));
    const o = play(await modules(), bytes);
    const n = p.frames * 1152;
    const out = [];
    for (let i = 0; i < n; i++) p.ch === 2 ? out.push(o.L[i], o.R[i]) : out.push(o.L[i]);
    const mono = p.ch === 1 && o.L.slice(0, n).every((v, i) => v === o.R[i]);
    const tail = o.L.slice(n).every((v) => v === 0) && o.R.slice(n).every((v) => v === 0);
    if (sha(out) !== p.pin) errors.push(`exact: ${name} output is not the reference >> 1 (${sha(out).slice(0, 12)})`);
    if (p.ch === 1 && !mono) errors.push(`exact: ${name} mono sides differ`);
    if (!tail) errors.push(`exact: ${name} not silent after its last frame`);
    if (o.frames !== p.frames) errors.push(`exact: ${name} ${o.frames} frames decoded, not ${p.frames}`);
    if (o.word >>> 24) errors.push(`exact: ${name} ${o.word >>> 24} underruns`);
    if (o.dropped) errors.push(`flow: ${name} ${o.dropped} bytes dropped`);
    if (!o.ended) errors.push(`end: ${name} never ended`);
    if (((o.word >> 4) & 15) !== 2) errors.push(`exact: ${name} rate code ${(o.word >> 4) & 15}, not 2`);
    notes.push(`${name}: ${o.frames} frames, ${n} samples a side = reference >> 1 (${p.pin.slice(0, 12)}...), ended, nothing dropped`);
}

async function rates(name, errors, notes) {
    const p = PINS[name], bytes = new Uint8Array(await readFile(`${DIR}/${name}`));
    const ref = new Int16Array((await readFile(`prototypes/mp3_bard_re/ref/${name.replace(".MP3", ".raw")}`).catch(() => null))?.buffer ?? new ArrayBuffer(0));
    const o = play(await modules(), bytes);
    const want = Math.floor(p.frames * 1152 * 44100 / p.rate);
    const last = o.endAt; // the end was seen after this render: the last sample is in its block
    if (((o.word >> 4) & 15) !== p.code) errors.push(`rates: ${name} rate code ${(o.word >> 4) & 15}, not ${p.code}`);
    if (last < want || last - want > BLOCK + 2) errors.push(`rates: ${name} ended after ${last} output samples, not in the block after ${want}`);
    if (!o.ended || o.frames !== p.frames) errors.push(`rates: ${name} ended ${o.ended}, ${o.frames} frames`);
    const conv = [];
    for (let i = 0; i < want; i++) conv.push(o.L[i], o.R[i]);
    const got = sha(conv); // the converter's output, pinned: integer code, the same on every host
    if (got !== p.out) errors.push(`rates: ${name} converted output ${got} is not the pin`);
    let snr = "no local reference";
    if (ref.length) { // the reference >> 1, interpolated at the output's times (a local check, not pinned)
        let s = 0, e = 0;
        for (let i = 0; i < want - 2; i++) {
            const t = (i * p.rate) / 44100, k = Math.floor(t), f = t - k;
            const v = ((ref[2 * k] >> 1) * (1 - f) + (ref[2 * k + 2] >> 1) * f);
            s += v * v; e += (o.L[i] - v) ** 2;
        }
        const db = 10 * Math.log10(s / Math.max(1, e));
        if (db < 40) errors.push(`rates: ${name} ${db.toFixed(1)} dB against the reference`);
        snr = `${db.toFixed(1)} dB`;
    }
    notes.push(`${name}: pin ${got.slice(0, 12)}..., rate code ${p.code}, ${want} samples at 44.1 (ended in the block to ${last}), ${o.frames} frames, ${snr}`);
}

async function truncated(errors, notes) {
    const p = PINS["TONES44.MP3"], bytes = new Uint8Array(await readFile(`${DIR}/TONES44.MP3`));
    const o = play(await modules(), bytes, { stopAt: bytes.length >> 1 });
    const prefix = await prefixPin(o.frames);
    const out = [];
    for (let i = 0; i < o.frames * 1152; i++) out.push(o.L[i], o.R[i]);
    if (!o.ended) errors.push("truncated: never ended");
    if (o.frames < 100 || o.frames >= p.frames) errors.push(`truncated: ${o.frames} frames decoded`);
    if (prefix && sha(out) !== prefix) errors.push("truncated: the frames decoded are not the reference's first");
    notes.push(`truncated: half the file, ${o.frames} frames${prefix ? " = the reference's first" : ""}, ended`);
}

async function prefixPin(frames) { // the local reference's first frames, when there is one
    const raw = await readFile("prototypes/mp3_bard_re/ref/TONES44.raw").catch(() => null);
    if (!raw) return null;
    const r = new Int16Array(raw.buffer, raw.byteOffset, frames * 1152 * 2);
    return sha(Array.from(r, (v) => v >> 1));
}

async function starved(errors, notes) {
    const bytes = new Uint8Array(await readFile(`${DIR}/TONES44.MP3`));
    // 130 bytes a 735-sample block: half the 128 kbps stream's 267
    const o = play(await modules(), bytes, { cap: 130, maxBlocks: 4000 });
    if (!(o.word >>> 24)) errors.push("starved: no underrun counted");
    if (!o.ended || o.frames !== PINS["TONES44.MP3"].frames) errors.push(`starved: ended ${o.ended}, ${o.frames} frames`);
    notes.push(`starved: ${o.word >>> 24} underruns counted, all ${o.frames} frames decoded, ended`);
}

const errors = [], notes = [];
for (const n of ["TONES44.MP3", "MONO44.MP3"]) await exact(n, errors, notes);
if (!broke) {
    for (const n of ["TONES32.MP3", "TONES48.MP3"]) await rates(n, errors, notes);
    await truncated(errors, notes);
    await starved(errors, notes);
}
for (const n of notes) console.log(`  ${n}`);
// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (broke) {
    const want = { lowbyte: "exact:", overfeed: "flow:", noend: "end:" }[broke];
    const hit = errors.find((e) => e.startsWith(want));
    console.log(hit ? `mp3_check: PASS (--break ${broke} caught: ${hit})` : `mp3_check: FAILED -- --break ${broke} not caught (${errors.length} other errors)`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `mp3_check: FAILED -- ${errors.join("; ")}` : "mp3_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
