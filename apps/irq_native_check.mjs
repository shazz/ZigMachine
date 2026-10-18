// A handler-only native driver in the browser's own audio modules (apps/sndh_native_lib.mjs,
// libs/zig/players/digi_irq.zig): the tune's timer interrupt in Zig, its init and play on the
// 68000. Its samples must be the 68000's, bit for bit.
//
// 1. Loaded, the tune is recognised (audioSndhNative = --status).
// 2. Natively (mode 2, the default) its samples are the 68000's over --seconds.
// 3. Switched 2-1-2-1-2 mid-tune, the samples do not change.
//
//   node apps/irq_native_check.mjs --song union/thalion_forever.sndh --status 8 --seconds 60
//   ... [--tune n] --break [--mutant 6]   (mutant 5, the default: the steps play patches into the handler
//                  frozen when it was armed; 6: the stream handler's registers 9 and 10 swapped; 8: the one-byte
//                  handler's pointer kept in Zig past play's rewind.
//                  The check must fail, then exits 0)
import { firstDifference, render } from "./sndh_native_lib.mjs";

const arg = (name, dflt) => {
    const i = process.argv.indexOf(`--${name}`);
    return i > 0 ? process.argv[i + 1] : dflt;
};
const SONG = arg("song");
const STATUS = Number(arg("status"));
const SECONDS = Number(arg("seconds", "30")), B = 50, BLOCKS = SECONDS * B;
const BREAK = process.argv.includes("--break");
const MUTANT = Number(arg("mutant", "5"));
const TUNE = Number(arg("tune", "1"));
const TAG = `irq_native ${SONG}`;
if (!SONG || !STATUS) {
    console.log("usage: irq_native_check.mjs --song <file> --status <n> [--seconds s] [--break]");
    process.exit(2);
}

async function check(mutant) {
    const errors = [];
    const ref = await render(SONG, false, BLOCKS, {}, 0, TUNE);
    if (ref.status !== 4) errors.push(`with native replays off, audioSndhNative says ${ref.status}, not 4`);
    const nat = await render(SONG, true, BLOCKS, {}, mutant, TUNE);
    if (nat.status !== STATUS) errors.push(`audioSndhNative says ${nat.status}, not ${STATUS}`);
    const d = firstDifference(ref.out, nat.out);
    if (d >= 0) errors.push(`native differs from the 68000 from block ${d} (${(d / B).toFixed(2)} s)`);
    const flip = await render(SONG, true, 6 * B, { [B]: 1, [2 * B]: 2, [3 * B]: 1, [4 * B]: 2 }, mutant, TUNE);
    if (flip.got.join() !== "1,2,1,2") errors.push(`modes 1/2/1/2 answered ${flip.got}`);
    if (firstDifference(ref.out.subarray(0, flip.out.length), flip.out) >= 0) errors.push("switching between modes 1 and 2 changed the samples");
    return errors;
}

const errors = await check(BREAK ? MUTANT : 0);
if (BREAK) {
    if (errors.some((e) => e.startsWith("native differs"))) {
        console.log(`${TAG} --break: caught (${errors[0]})`);
        process.exit(0);
    }
    console.log(`${TAG} --break: FAILED -- mutant ${MUTANT} went unnoticed`);
    process.exit(1);
}
if (errors.length) {
    console.log(`${TAG}: FAILED -- ${errors.join("; ")}`);
    process.exit(1);
}
console.log(`${TAG}: OK -- native handler = 68000 bit for bit over ${SECONDS} s, modes 2-1-2-1-2 unbroken`);
