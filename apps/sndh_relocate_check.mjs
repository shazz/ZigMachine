// Regression check for the SNDH image base: Mad Max's "Alloy Run - Sid" must play.
//
// The SNDH player used to load a tune at 68000 address $0, on top of the exception
// vector table. Alloy Run installs its MFP timer handlers directly at $110 (D),
// $120 (B) and $134 (A), which overwrote its own replay code: the first play call
// ran off into garbage and the tune was silent. The player now loads images at
// $10002, as AtariAudio does. This proves the tune plays every second of 30, that
// its timers are programmed and firing (volume registers written many times per
// frame), and that the replay never lost its way.
//
//   node apps/sndh_relocate_check.mjs [wasmDir]   # default docs/; pass a dir holding
//                                                 # old demo-audio + machine-audio to see it fail
import { readFile } from "node:fs/promises";

const DIR = process.argv[2] ?? "docs";
const TUNE = "docs/music/union/alloy_run.sndh";
const SECONDS = 30, SR = 44100, FRAME = 882; // one 50 Hz replay frame

const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
const machine = (await WebAssembly.instantiate(await readFile(`${DIR}/machine-audio.wasm`), { env: { memory } })).instance.exports;
const env = { memory };
for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
let volWrites = 0;
env.machineYmWrite = (r, v) => {
    if (r >= 8 && r <= 10) volWrites++;
    return machine.machineYmWrite(r, v);
};
const audio = (await WebAssembly.instantiate(await readFile(`${DIR}/demo-audio.wasm`), { env })).instance.exports;
audio.audioInit();
const bytes = new Uint8Array(await readFile(TUNE));
new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
const loaded = audio.audioLoadSndh(bytes.length);
audio.audioSndhPlay(1);

let peak = 0, secPeak = 0, silent = 0;
volWrites = 0;
for (let f = 1; f <= SECONDS * 50; f++) {
    audio.audioRender(FRAME);
    for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), FRAME)) {
        const a = Math.abs(v);
        peak = Math.max(peak, a);
        secPeak = Math.max(secPeak, a);
    }
    if (f % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
}
const timers = [0, 1, 2, 3].map((t) => audio.audioSndhTimerRate(t));
const stuck = audio.audioSndhStuckPc();
const perFrame = volWrites / (SECONDS * 50);
console.log(`alloy_run (${DIR}): loaded ${loaded}, mode ${audio.audioMode()}, peak ${peak.toFixed(4)}, silent seconds ${silent}/${SECONDS}`);
console.log(`  MFP timers A..D Hz ${timers.join(",")}, volume writes ${perFrame.toFixed(1)}/frame, stuck PC $${stuck.toString(16)}`);
// A SID tune writes its volumes from the timers, several times a frame; a plain
// once-per-play replay would write each at most once (3 per frame).
const ok = loaded && audio.audioMode() === 4 && stuck === 0 && peak > 0.01 && silent === 0 &&
    timers.filter((hz) => hz > 0).length >= 2 && perFrame > 3;
console.log(ok ? "=> PASS ✅ a tune that installs its own MFP vectors plays (image loaded above the vector table)"
               : "=> FAIL ❌ Alloy Run does not play: is the SNDH image back at $0?");
process.exit(ok ? 0 : 1);
