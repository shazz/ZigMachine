// render.mjs TUNE.sndh SUBTUNE SECONDS OUT.wav -- play an SNDH on the sealed YM (the worktree's
// docs/*.wasm, as apps/sndh_headless.mjs boots them) and write the left channel as a 16-bit
// 44.1 kHz mono WAV. Also prints the MFP timer rates and whether the 68000 got stuck.
import { readFile, writeFile } from "node:fs/promises";

const AUDIO_PAGES = 48;
const [path, sub, seconds, out] = process.argv.slice(2);
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
const BLOCK = 1024, RATE = 44100;
const n = Math.floor(Number(seconds) * RATE / BLOCK) * BLOCK;
const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK);
const pcm = new Int16Array(n);
for (let at = 0; at < n; at += BLOCK) {
    demo.audioRender(BLOCK);
    for (let i = 0; i < BLOCK; i++) pcm[at + i] = Math.max(-32768, Math.min(32767, Math.round(left[i] * 32767)));
}
const head = Buffer.alloc(44);
head.write("RIFF", 0); head.writeUInt32LE(36 + n * 2, 4); head.write("WAVEfmt ", 8);
head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22);
head.writeUInt32LE(RATE, 24); head.writeUInt32LE(RATE * 2, 28); head.writeUInt16LE(2, 32);
head.writeUInt16LE(16, 34); head.write("data", 36); head.writeUInt32LE(n * 2, 40);
await writeFile(out, Buffer.concat([head, Buffer.from(pcm.buffer)]));
const timers = [0, 1, 2, 3].map((t) => `${"ABCD"[t]}=${demo.audioSndhTimerRate(t)}Hz`).join(" ");
console.log(`${out}: ${n / RATE} s, timers ${timers}, stuck=${demo.audioSndhStuckPc().toString(16)}, mode=${demo.audioMode()}`);
