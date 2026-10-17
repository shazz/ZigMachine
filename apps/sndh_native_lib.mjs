// The browser's own audio modules (docs/demo-audio.wasm on docs/machine-audio.wasm) playing one
// SNDH, natively or on the 68000: what monty_native_check.mjs and wow_native_check.mjs compare.
import { readFile } from "node:fs/promises";

const AUDIO_PAGES = 48; // machine/sdk/audio.zig
export const BLOCK = 882; // 50 blocks a second at 44.1 kHz

/** The audio modules with `song` (under docs/music) loaded and started; native replays on or off. */
async function start(song, native) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    audio.audioSndhNativeEnable(native);
    const bytes = new Uint8Array(await readFile(`docs/music/${song}`));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) throw new Error(`${song}: audioLoadSndh refused it`);
    audio.audioSndhPlay(1);
    return { memory, machine, audio };
}

/** `blocks` blocks, left channel, with `modes` {block: mode} asked before their block. */
export async function render(song, native, blocks, modes = {}, mutant = 0) {
    const { memory, machine, audio } = await start(song, native);
    audio.audioSndhNativeMutant(mutant);
    const out = new Float32Array(blocks * BLOCK), got = [];
    for (let b = 0; b < blocks; b++) {
        if (b in modes) got.push(audio.audioSndhMode(modes[b]));
        audio.audioRender(BLOCK);
        out.set(new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK), b * BLOCK);
    }
    if (audio.audioSndhStuckPc()) throw new Error(`stuck at $${audio.audioSndhStuckPc().toString(16)}`);
    return { out, got, status: audio.audioSndhNative() };
}

/** The first block where two renders differ (from block `from`), or -1. */
export function firstDifference(a, b, from = 0) {
    for (let i = from * BLOCK; i < a.length; i++) if (a[i] !== b[i]) return Math.floor(i / BLOCK);
    return -1;
}

export function correlation(a, b) {
    const ma = a.reduce((s, x) => s + x, 0) / a.length, mb = b.reduce((s, x) => s + x, 0) / b.length;
    let ab = 0, aa = 0, bb = 0;
    for (let i = 0; i < a.length; i++) { const x = a[i] - ma, y = b[i] - mb; ab += x * y; aa += x * x; bb += y * y; }
    return ab / Math.sqrt(aa * bb);
}
