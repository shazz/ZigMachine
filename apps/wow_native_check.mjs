// Wow Scroller's native replay in the browser's own audio modules (apps/sndh_native_lib.mjs): the
// Union Demo's TCB2 WOW!-SCROLLER tune (MAN Cool, Timer A digi at 7585 Hz) must sound the same
// natively as on the 68000 (libs/zig/players/digi_wow.zig), and mode 3 must follow it on PCM.
//
// 1. Loaded, the tune is recognised (audioSndhNative 6).
// 2. Natively (mode 2, the default) its samples are the 68000's, bit for bit, over 40 s: past
//    the playlist's wrap at 33.4 s.
// 3. Switched 2-1-2-1-2 mid-tune, the samples do not change.
// 4. Mode 3 plays the samples on PCM, following the YM path (correlation > 0.8), and back in
//    mode 2 the output is the YM path's again, on the same sample.
//
//   node apps/wow_native_check.mjs
//   node apps/wow_native_check.mjs --break   (mutant 4: Beat Dis's handler, its addi.b #$80,
//                                              reused for Wow; the check must fail, then exits 0)
import { BLOCK, correlation, firstDifference, render } from "./sndh_native_lib.mjs";

const SONG = "union/wow_scroller.sndh";
const SECONDS = 40, BLOCKS = SECONDS * 50, B = 50;
const BREAK = process.argv.includes("--break");

/** The checks; a list of what failed. */
async function check(mutant) {
    const errors = [];
    const ref = await render(SONG, false, BLOCKS);
    if (ref.status !== 4) errors.push(`with native replays off, audioSndhNative says ${ref.status}, not 4`);
    const nat = await render(SONG, true, BLOCKS, {}, mutant);
    if (nat.status !== 6) errors.push(`audioSndhNative says ${nat.status}, not 6 (Wow Scroller)`);
    const d = firstDifference(ref.out, nat.out);
    if (d >= 0) errors.push(`native differs from the 68000 from block ${d} (${(d / 50).toFixed(2)} s)`);
    const flip = await render(SONG, true, 6 * B, { [B]: 1, [2 * B]: 2, [3 * B]: 1, [4 * B]: 2 }, mutant);
    if (flip.got.join() !== "1,2,1,2") errors.push(`modes 1/2/1/2 answered ${flip.got}`);
    if (firstDifference(ref.out.subarray(0, 6 * B * BLOCK), flip.out) >= 0) errors.push("switching between modes 1 and 2 changed the samples");
    const hq = await render(SONG, true, 6 * B, { [2 * B]: 3, [4 * B]: 2 }, mutant);
    if (hq.got.join() !== "3,2") errors.push(`modes 3/2 answered ${hq.got}`);
    const at = (r, b0, b1) => r.out.subarray(b0 * BLOCK, b1 * BLOCK);
    const r = correlation(at(hq, 2 * B, 4 * B), at(ref, 2 * B, 4 * B));
    if (!(r > 0.8)) errors.push(`mode 3 does not follow the YM path (correlation ${r.toFixed(2)})`);
    if (firstDifference(at(hq, 4 * B + 5, 6 * B), at(ref, 4 * B + 5, 6 * B)) >= 0) errors.push("back in mode 2, the output is not the YM path's");
    return { errors, r };
}

const { errors, r } = await check(BREAK ? 4 : 0);
if (BREAK) {
    if (errors.some((e) => e.startsWith("native differs"))) {
        console.log(`wow_native --break: caught (${errors[0]})`);
        process.exit(0);
    }
    console.log("wow_native --break: FAILED -- Beat Dis's handler on Wow's bytes went unnoticed");
    process.exit(1);
}
if (errors.length) {
    console.log(`wow_native: FAILED -- ${errors.join("; ")}`);
    process.exit(1);
}
console.log(`wow_native: OK -- native = 68000 bit for bit over ${SECONDS} s, modes 2-1-2-1-2 unbroken, mode 3 follows the YM path (${r.toFixed(2)}) and hands back`);
