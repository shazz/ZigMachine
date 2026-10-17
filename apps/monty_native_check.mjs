// Monty's native replay in the browser's own audio modules (docs/demo-audio.wasm on
// docs/machine-audio.wasm): TEX NEO SHOW's tune, Mad Max's "Auf Weidersehen Monty -
// digidrums", must sound the same natively as on the 68000 (libs/zig/players/digi_monty.zig).
//
// 1. Loaded, the tune is recognised as Monty (audioSndhNative 5), and mode 3 (PCM) answers 2.
// 2. Natively (mode 2, the default) its samples are the 68000's, bit for bit, over 50 s:
//    the drums come in at 38.4 s, so this hears the Timer D handler as well as the sequencer.
// 3. Switched 2-1-2-1-2 mid-tune (one switch inside the drums), the samples do not change.
//
//   node apps/monty_native_check.mjs
//   node apps/monty_native_check.mjs --break   (mutant 3: volume C written over the drums;
//                                                the check must fail, and this then exits 0)
import { readFile } from "node:fs/promises";

const AUDIO_PAGES = 48; // machine/sdk/audio.zig
const SONG = "auf_weidersehen_monty_digi.sndh";
const BLOCK = 882, SECONDS = 50, BLOCKS = SECONDS * 50; // 50 blocks a second at 44.1 kHz
const DRUMS = 38 * 50; // the first drum's block, about (b848353: 38.4 s)
const BREAK = process.argv.includes("--break");

/** The audio modules with Monty loaded and started; native replays on or off. */
async function start(native) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    audio.audioSndhNativeEnable(native);
    const bytes = new Uint8Array(await readFile(`docs/music/${SONG}`));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) throw new Error(`${SONG}: audioLoadSndh refused it`);
    audio.audioSndhPlay(1);
    return { memory, machine, audio };
}

/** BLOCKS blocks, left channel, with `modes` {block: mode} asked before their block. */
async function render(native, modes = {}, mutant = 0) {
    const { memory, machine, audio } = await start(native);
    audio.audioSndhNativeMutant(mutant);
    const out = new Float32Array(BLOCKS * BLOCK), got = [];
    for (let b = 0; b < BLOCKS; b++) {
        if (b in modes) got.push(audio.audioSndhMode(modes[b]));
        audio.audioRender(BLOCK);
        out.set(new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK), b * BLOCK);
    }
    if (audio.audioSndhStuckPc()) throw new Error(`stuck at $${audio.audioSndhStuckPc().toString(16)}`);
    return { out, got, status: audio.audioSndhNative() };
}

/** The first block where two renders differ, or -1. */
function firstDifference(a, b) {
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return Math.floor(i / BLOCK);
    return -1;
}

/** The checks; a list of what failed. */
async function check(mutant) {
    const errors = [];
    const ref = await render(false);
    if (ref.status !== 4) errors.push(`with native replays off, audioSndhNative says ${ref.status}, not 4`);
    let peak = 0;
    for (let i = DRUMS * BLOCK; i < ref.out.length; i++) peak = Math.max(peak, Math.abs(ref.out[i]));
    if (peak < 0.05) errors.push(`the 68000's render is silent after the drums come in (peak ${peak.toFixed(3)})`);
    const nat = await render(true, { 0: 3 }, mutant);
    if (nat.status !== 5) errors.push(`audioSndhNative says ${nat.status}, not 5 (Monty)`);
    if (nat.got.join() !== "2") errors.push(`mode 3 answered ${nat.got}, not 2 (Monty has no PCM path)`);
    const d = firstDifference(ref.out, nat.out);
    if (d >= 0) errors.push(`native differs from the 68000 from block ${d} (${(d / 50).toFixed(2)} s)`);
    const flips = { 400: 1, 900: 2, 2000: 1, 2200: 2 }; // 2200: inside the drums
    const flip = await render(true, flips, mutant);
    if (flip.got.join() !== "1,2,1,2") errors.push(`modes 1/2/1/2 answered ${flip.got}`);
    const f = firstDifference(ref.out, flip.out);
    if (f >= 0) errors.push(`switching between modes 1 and 2 changed the samples from block ${f}`);
    return errors;
}

const errors = await check(BREAK ? 3 : 0);
if (BREAK) {
    if (errors.some((e) => e.startsWith("native differs"))) {
        console.log(`monty_native --break: caught (${errors[0]})`);
        process.exit(0);
    }
    console.log("monty_native --break: FAILED -- volume C written over the drums went unnoticed");
    process.exit(1);
}
if (errors.length) {
    console.log(`monty_native: FAILED -- ${errors.join("; ")}`);
    process.exit(1);
}
console.log(`monty_native: OK -- native = 68000 bit for bit over ${SECONDS} s (drums from ~38 s), modes 2-1-2-1-2 unbroken, mode 3 answers 2`);
