// Monty's native replay in the browser's own audio modules (apps/sndh_native_lib.mjs): TEX NEO
// SHOW's tune, Mad Max's "Auf Weidersehen Monty - digidrums", must sound the same natively as on
// the 68000 (libs/zig/players/digi_monty.zig).
//
// 1. Loaded, the tune is recognised as Monty (audioSndhNative 5), and mode 3 (PCM) answers 2.
// 2. Natively (mode 2, the default) its samples are the 68000's, bit for bit, over 50 s:
//    the drums come in at 38.4 s, so this hears the Timer D handler as well as the sequencer.
// 3. Switched 2-1-2-1-2 mid-tune (one switch inside the drums), the samples do not change.
//
//   node apps/monty_native_check.mjs
//   node apps/monty_native_check.mjs --break   (mutant 3: volume C written over the drums;
//                                                the check must fail, and this then exits 0)
import { BLOCK, firstDifference, render } from "./sndh_native_lib.mjs";

const SONG = "auf_weidersehen_monty_digi.sndh";
const SECONDS = 50, BLOCKS = SECONDS * 50;
const DRUMS = 38 * 50; // the first drum's block, about (b848353: 38.4 s)
const BREAK = process.argv.includes("--break");

/** The checks; a list of what failed. */
async function check(mutant) {
    const errors = [];
    const ref = await render(SONG, false, BLOCKS);
    if (ref.status !== 4) errors.push(`with native replays off, audioSndhNative says ${ref.status}, not 4`);
    let peak = 0;
    for (let i = DRUMS * BLOCK; i < ref.out.length; i++) peak = Math.max(peak, Math.abs(ref.out[i]));
    if (peak < 0.05) errors.push(`the 68000's render is silent after the drums come in (peak ${peak.toFixed(3)})`);
    const nat = await render(SONG, true, BLOCKS, { 0: 3 }, mutant);
    if (nat.status !== 5) errors.push(`audioSndhNative says ${nat.status}, not 5 (Monty)`);
    if (nat.got.join() !== "2") errors.push(`mode 3 answered ${nat.got}, not 2 (Monty has no PCM path)`);
    const d = firstDifference(ref.out, nat.out);
    if (d >= 0) errors.push(`native differs from the 68000 from block ${d} (${(d / 50).toFixed(2)} s)`);
    const flip = await render(SONG, true, BLOCKS, { 400: 1, 900: 2, 2000: 1, 2200: 2 }, mutant); // 2200: inside the drums
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
