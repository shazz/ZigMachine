// sndh_pcm.mjs TUNE.sndh SUBTUNE SECONDS OUT.f32 -- render an SNDH on the sealed YM (the
// worktree's docs/*-audio.wasm, as ymlog.mjs) to raw float32 mono at 44.1 kHz, for
// comparing what it sounds like with a Hatari recording of the original (audio_cmp.py).
import { readFile, writeFile } from "node:fs/promises";

const [path, sub, seconds, out] = process.argv.slice(2);
const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
const env = { memory };
for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
demo.audioInit();
const tune = new Uint8Array(await readFile(path));
new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
if (!demo.audioLoadSndh(tune.length)) throw new Error("not an SNDH");
demo.audioSndhPlay(Number(sub));
const n = Math.round(Number(seconds) * 44100);
const pcm = new Float32Array(n);
for (let at = 0; at < n; at += 1024) {
    demo.audioRender(1024);
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), 1024);
    pcm.set(left.subarray(0, Math.min(1024, n - at)), at);
}
await writeFile(out, Buffer.from(pcm.buffer));
console.log(`${path} #${sub}: ${seconds} s`);
