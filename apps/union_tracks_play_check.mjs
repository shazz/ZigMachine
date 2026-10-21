// The Union cracktro's six tunes (keys 1-6, apps/zig/scenes/union/tracks.zig) all
// PLAY, loaded one after the other into ONE audio instance, as a viewer pressing
// 1, 2, 3, 4, 5, 6 makes the worklet do (docs/audio-worklet-sealed.js writeSong +
// load + play). Why: keys 3+ "crashed" (Matt, 2026-10-20). audioLoadYm left the
// autoplayed SNDH active over the dump just staged on its 68000 RAM, so the dump
// never played and PLAY ran over its bytes until the 8 M-cycle runaway limit:
// seconds of Musashi on BARD. Each tune must take the player of its extension
// (SNDH mode 4, YM dump mode 2), leave no runaway 68000, and make a sound.
//
//   node apps/union_tracks_play_check.mjs
import { readFile } from "node:fs/promises";

const TRACKS = ["sharpness_buzztone.sndh", "150_mph.sndh", "androids.sndh", "drooling_505.sndh", "lap_33.sndh", "reality.sndh"];
const BLOCK = 1024, BLOCKS = 43; // one second a tune

const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // AUDIO_PAGES
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
const d = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
d.audioInit();

let failed = false;
for (const [i, name] of TRACKS.entries()) {
    const bytes = new Uint8Array(await readFile(`docs/music/union/${name}`));
    const cap = d.audioSongCapacity(), len = Math.min(bytes.length, cap);
    new Uint8Array(memory.buffer, d.audioSongPtr(), cap).set(bytes.subarray(0, len));
    const ym = name.endsWith(".ymraw");
    const ok = ym ? d.audioLoadYm(len) : d.audioLoadSndh(len);
    if (ok) ym ? d.audioYmPlay() : d.audioSndhPlay(0);
    const stuckBefore = d.audioSndhStuckPc();
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK);
    let peak = 0;
    for (let b = 0; b < BLOCKS; b++) { d.audioRender(BLOCK); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
    const want = ym ? 2 : 4, ran = d.audioSndhStuckPc() !== stuckBefore;
    // 505's Drooling is an STE DMA replay (FLAG ~ey): the machine has no DMA sound yet, so
    // it loads and runs (mode 4, no runaway) but is silent. Matt's choice, 2026-10-20.
    const silentOk = name === "drooling_505.sndh";
    const good = !!ok && d.audioMode() === want && !ran && (silentOk || peak > 0.01);
    console.log(`  ${good ? "ok  " : "FAIL"} key ${i + 1} ${name}: loaded ${!!ok}, mode ${d.audioMode()} (want ${want}), ` +
        `${ran ? `68000 RAN AWAY at $${d.audioSndhStuckPc().toString(16)}, ` : ""}peak ${peak.toFixed(3)}`);
    if (!good) failed = true;
}
console.log(failed ? "=> FAIL ❌ a Union tune does not play after the one before it"
    : "=> PASS ✅ keys 1-6: every Union tune plays, each after the one before");
process.exit(failed ? 1 : 0);
