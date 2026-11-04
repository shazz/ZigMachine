// kt_cost: where the klystrack (.kt) player spends BARD's cycles, without a Verilator sim. The
// demo-audio module is instrumented as apps/frame_cost.mjs instruments a cart (a counter per
// straight-line segment, apps/perf/instrument.mjs) and runs a song for warmup + N 60 Hz frames
// (735 samples each, audioRender as the board calls it); the exact op counts become an
// ESTIMATE through ZIGGY's cost model (apps/perf/cost_model.mjs: BARD is the same VexRiscv
// family, without the FPU), ranked by function and loop. Use a names build for function names:
//   zig build -Drelease=true -Dwasm -Dnames=true -p zig-out/perf-names/zig-out
//   node apps/kt_cost.mjs <song.kt> [--row N] [--frames 12] [--warmup 6] [--top 25]
//        [--audio zig-out/perf-names/docs/demo-audio.wasm]
// The estimate ranks the hot code; snd-bench (fpga/cycles/sound.mk) is the measurement.
import { readFile } from "node:fs/promises";
import { instrument } from "./perf/instrument.mjs";
import { Profile } from "./perf/profile.mjs";
import { hotRegions } from "./perf/report.mjs";
import { twinNames } from "./perf/names.mjs";

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const song = process.argv[2];
if (!song || song.startsWith("--")) throw new Error("usage: node apps/kt_cost.mjs <song.kt> [--row N] [--frames N] [--warmup N] [--top N] [--audio F]");
const row = Number(arg("--row", 0)), frames = Number(arg("--frames", 12)), warmup = Number(arg("--warmup", 6));
const top = Number(arg("--top", 25)), audioPath = arg("--audio", "zig-out/perf-names/docs/demo-audio.wasm");

const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
const I = instrument(await readFile(audioPath), { probes: false });
const inst = (await WebAssembly.instantiate(I.bytes, { env })).instance;
const a = inst.exports, P = new Profile("audio", I.plan, a.__fc);
a.audioInit();
const bytes = new Uint8Array(await readFile(song));
new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
if (!a.audioLoadKt(bytes.length)) throw new Error(`refused: error ${a.audioKtError()}`);
a.audioKtPlay(row);
P.frame(false);
const series = [];
for (let f = 0; f < warmup + frames; f++) {
    a.audioRender(735);
    const c = P.frame(f >= warmup);
    if (f >= warmup) series.push(c);
}
const avg = series.reduce((x, y) => x + y, 0) / series.length;
console.log(`${song} row ${row}: est ${(avg / 1e6).toFixed(2)} Mc a frame (${Math.round((100 * avg) / 1.667e6)} % of 1.67), ${frames} frames`);
const { src } = twinNames(audioPath, audioPath.replace(/\/[^/]*$/, ""));
for (const h of hotRegions([P], top)) console.log(`  ${h.mc.toFixed(3).padStart(7)} Mc  ${h.func}${h.loop >= 0 ? ` loop@${h.at}` : ""}  x${h.iters}  ${h.cause}  ${src(parseInt(h.at, 16)) ?? ""}`);
