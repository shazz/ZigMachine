// ymlog.mjs TUNE.sndh SUBTUNE FRAMES OUT.bin -- run an SNDH on the sealed YM
// (the worktree's docs/*.wasm) and write the 14 YM registers after every 50 Hz
// frame (882 samples) to OUT.bin, 14 bytes a frame. Run from the repo root.
import { readFile, writeFile } from "node:fs/promises";

const AUDIO_PAGES = 48;
const [path, sub, frames, out] = process.argv.slice(2);
const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
demo.audioInit();
const tune = new Uint8Array(await readFile(path));
new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
if (!demo.audioLoadSndh(tune.length)) throw new Error("not an SNDH");
demo.audioSndhPlay(Number(sub));
const regs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);
const n = Number(frames);
const log = new Uint8Array(n * 14);
for (let f = 0; f < n; f++) {
    demo.audioRender(882);
    log.set(regs.subarray(0, 14), f * 14);
}
await writeFile(out, log);
console.log(`${path} #${sub}: ${n} frames, stuck=${demo.audioSndhStuckPc().toString(16)}`);
