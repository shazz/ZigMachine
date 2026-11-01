// Mind Rewind's music (docs/music/mindwind.sndh, apps/zig/assets/screens/mindwind/mw_music.s) on the
// sealed audio machine. The SNDH runs the demo's own sequencer, copied verbatim, with a new mixer, so
// the checks are about the parts that are new or that the cart relies on:
//   stereo   -- both channels play (left = voices 1+3, right = voices 2+4, interleaved bytes)
//   position -- the song position the demo's parts waited on ($771E, voice 1's event count) reaches
//               each of the demo's thresholds; the frame at which it does is printed, because the
//               cart times its parts with those frame counts (zg has no window into the 68000)
//   rewind   -- sndhCall $8001 stops the song (position frozen) and plays the rewind one-shot
//   reverse  -- sndhCall $8002 restarts the song (song 2, position from 0) on reversed samples
//
//   node apps/mindwind_music_check.mjs [--wav out.wav] [--frames N]
import { readFile, writeFile } from "node:fs/promises";

const AUDIO_PAGES = 48; // machine/sdk/audio.zig
const RATE = 44100, BLOCK = 882; // one 50 Hz frame of output
const POS = 0x771e - 0x75fe; // song position, inside the verbatim block
const THRESHOLDS = [0x4c, 0x74, 0x9c, 0xc4, 0xec, 0x114, 0x160, 0x1b6, 0x1f0, 0x20f, 0x226, 0x242];
const arg = (k, d) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : d);

const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
demo.audioInit();

const tune = new Uint8Array(await readFile("docs/music/mindwind.sndh"));
new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
if (!demo.audioLoadSndh(tune.length)) throw new Error("not an SNDH");
demo.audioSndhPlay(1);

// Where the verbatim block landed in 68000 RAM: find its first 16 bytes.
const code = new Uint8Array(await readFile("apps/zig/assets/screens/mindwind/mw_code.bin"));
const sig = [0, 4, 8, 12].map((i) => ((code[i] << 24) | (code[i + 1] << 16) | (code[i + 2] << 8) | code[i + 3]) >>> 0);
let mcode = -1;
for (let a = 0; a < 0x400000 && mcode < 0; a += 2)
    if (demo.m68k_read_memory_32(a) >>> 0 === sig[0] && sig.every((v, i) => demo.m68k_read_memory_32(a + 4 * i) >>> 0 === v)) mcode = a;
if (mcode < 0) throw new Error("the music block is not in 68000 RAM");
const pos = () => demo.m68k_read_memory_16(mcode + POS);

const L = new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK);
const R = new Float32Array(memory.buffer, machine.audioRightPtr(), BLOCK);
const wav = [];
function frame(stats) {
    demo.audioRender(BLOCK);
    for (let i = 0; i < BLOCK; i++) {
        stats.l = Math.max(stats.l, Math.abs(L[i]));
        stats.r = Math.max(stats.r, Math.abs(R[i]));
        stats.diff = Math.max(stats.diff, Math.abs(L[i] - R[i]));
        if (wav.length < RATE * 2 * 60) wav.push(L[i], R[i]);
    }
}

// A 500-byte frame the ORIGINAL mixed (Hatari, the demo's Timer A tail $752, VBL 1501, song position
// 13): the new mixer must produce it byte for byte at some frame of the same stretch of song.
const ref = new Uint8Array(await readFile("apps/zig/assets/screens/mindwind/mw_ref_mixbuf.bin"));
const bufp = demo.m68k_read_memory_32(mcode + 0x24) >>> 0; // the block's `lea $59C` now points at bufp
let matched = -1;
function matchRef(f) {
    const b = demo.m68k_read_memory_32(bufp + 4) >>> 0; // the buffer just mixed and handed to DMA
    for (let i = 0; i < ref.length; i++) if (demo.m68k_read_memory_8(b + i) !== ref[i]) return;
    matched = f;
}

const errors = [];
const first = { l: 0, r: 0, diff: 0 };
const hit = {};
const FRAMES = Number(arg("--frames", 7400));
for (let f = 0; f < FRAMES; f++) {
    frame(first);
    if (matched < 0 && pos() >= 10 && pos() <= 16) matchRef(f + 1);
    for (const t of THRESHOLDS) if (hit[t] === undefined && pos() >= t) hit[t] = f + 1;
}
console.log(`song 1: peak L ${first.l.toFixed(3)} R ${first.r.toFixed(3)}, max |L-R| ${first.diff.toFixed(3)}, position ${pos()}`);
console.log(`  position thresholds (frame): ${THRESHOLDS.map((t) => `$${t.toString(16)}@${hit[t] ?? "-"}`).join(" ")}`);
console.log(`  the original's mixed frame (position 13): ${matched < 0 ? "NOT FOUND" : `identical at frame ${matched}`}`);
if (matched < 0) errors.push("no frame equals the original mixer's output");
if (first.l < 0.02 || first.r < 0.02) errors.push("a channel is silent");
if (first.diff < 0.02) errors.push("left and right are the same signal: the interleave is lost");
for (const t of THRESHOLDS) if (hit[t] === undefined) errors.push(`position never reached $${t.toString(16)}`);

if (!demo.audioSndhCall(0x8001)) errors.push("sndhCall $8001 refused");
const atRewind = pos(), rew = { l: 0, r: 0, diff: 0 };
for (let f = 0; f < 60; f++) frame(rew);
console.log(`rewind: peak ${rew.l.toFixed(3)}, position ${atRewind} -> ${pos()}`);
if (rew.l < 0.05) errors.push("the rewind one-shot is silent");
if (pos() !== atRewind) errors.push("the song kept running under the rewind");

if (!demo.audioSndhCall(0x8002)) errors.push("sndhCall $8002 refused");
const back = { l: 0, r: 0, diff: 0 };
for (let f = 0; f < 250; f++) frame(back);
console.log(`reversed song 2: peak L ${back.l.toFixed(3)} R ${back.r.toFixed(3)}, position ${pos()}`);
if (back.l < 0.02 || back.r < 0.02) errors.push("the reversed song is silent");
if (pos() === 0 || pos() > 200) errors.push(`song 2's position ${pos()} did not restart and advance`);

const out = arg("--wav", null);
if (out) {
    const pcm = Buffer.alloc(wav.length * 2);
    wav.forEach((v, i) => pcm.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(v * 32767))), i * 2));
    const h = Buffer.alloc(44);
    h.write("RIFF", 0); h.writeUInt32LE(36 + pcm.length, 4); h.write("WAVEfmt ", 8);
    h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(2, 22); h.writeUInt32LE(RATE, 24);
    h.writeUInt32LE(RATE * 4, 28); h.writeUInt16LE(4, 32); h.writeUInt16LE(16, 34); h.write("data", 36);
    h.writeUInt32LE(pcm.length, 40);
    await writeFile(out, Buffer.concat([h, pcm]));
}
console.log(errors.length ? `=> FAIL ❌\n  ${errors.join("\n  ")}` : "=> PASS ✅ stereo, positions, rewind, reversed song");
process.exit(errors.length ? 1 : 0);
