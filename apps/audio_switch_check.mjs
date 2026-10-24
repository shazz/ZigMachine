// A tune loaded while an SNDH plays must take over cleanly, in ONE audio instance, as a
// screen switching tunes makes the worklet do (writeSong + load + play). The loads stage
// the new file in song RAM, which is the playing SNDH's 68000 RAM: a load that leaves the
// SNDH active lets it render first and run its PLAY/EXIT over the new bytes (the Union
// cracktro's "keys 3+ crash" for a YM dump, 2026-10-20; the same hole in the SAP load).
// For each kind: SNDH playing -> load + play the other file -> its mode, no runaway
// 68000, a sound; then back to an SNDH, which must play again.
//
//   node apps/audio_switch_check.mjs
import { readFile } from "node:fs/promises";

const SNDH = "docs/music/union/150_mph.sndh";
const KINDS = [
    { file: "docs/music/Gauntlet.sap", mode: 5, load: (d, n) => d.audioLoadSap(n), play: (d) => d.audioSapPlay(0) },
    { file: "docs/music/shaolin_title.hip", mode: 1, load: (d, n) => d.audioLoadHip(n), play: (d) => d.audioHipPlay(1) },
    { file: "docs/music/union/Drooling.ymraw", mode: 2, load: (d, n) => d.audioLoadYm(n), play: (d) => d.audioYmPlay() },
];
const BLOCK = 1024, SECOND = 43;

const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // AUDIO_PAGES
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
const d = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
d.audioInit();
const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK);

async function stage(path) {
    const bytes = new Uint8Array(await readFile(path));
    const cap = d.audioSongCapacity(), len = Math.min(bytes.length, cap);
    new Uint8Array(memory.buffer, d.audioSongPtr(), cap).set(bytes.subarray(0, len));
    return len;
}
function second() {
    let peak = 0;
    for (let b = 0; b < SECOND; b++) { d.audioRender(BLOCK); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
    return peak;
}
async function sndh() {
    const ok = d.audioLoadSndh(await stage(SNDH));
    if (ok) d.audioSndhPlay(0);
    return ok && d.audioMode() === 4 && second() > 0.01;
}

let failed = false;
const ok = (good, msg) => { console.log(`  ${good ? "ok  " : "FAIL"} ${msg}`); if (!good) failed = true; };
for (const k of KINDS) {
    ok(await sndh(), `${SNDH} plays first (mode 4)`);
    const stuck = d.audioSndhStuckPc();
    const t0 = performance.now();
    const loaded = k.load(d, await stage(k.file));
    if (loaded) k.play(d);
    const peak = second();
    const ran = d.audioSndhStuckPc() !== stuck, ms = performance.now() - t0;
    ok(!!loaded && d.audioMode() === k.mode && !ran && peak > 0.01,
        `${k.file} over it: loaded ${!!loaded}, mode ${d.audioMode()} (want ${k.mode}), ` +
        `${ran ? `68000 RAN AWAY at $${d.audioSndhStuckPc().toString(16)}, ` : ""}peak ${peak.toFixed(3)}, ${ms.toFixed(0)} ms`);
}
ok(await sndh(), `and an SNDH plays again after them`);
console.log(failed ? "audio_switch_check: FAILED" : "audio_switch_check: PASS");
process.exit(failed ? 1 : 0);
