// Gate: pt2-clone plays on the machine's four HARDWARE Paula channels (HW 1.14.0, decisions.md
// 2026-11-02 "Paula channels for carts"). The committed cart docs/demo-pt2.wasm boots off its floppy
// (apps/ports_machine.mjs) with env.hostPaula* wired to the real audio worklet (apps/paula_lib.mjs),
// loads RONKEN.MOD (DISK OP, the second file; HYBRID.MOD, the first, opens on one pad for 20 s) and
// PLAYs it: 3 channels, ~45 notes in the 5.3 s checked. Then:
//   claim     pt2 claims the channels at its first audio block and stops feeding the stream ring
//   plays     the worklet's output is not silent; its writes landed, none refused, dropped or late
//   pattern   the hardware's sound follows the SOFTWARE mixer's (the same run with the claim refused,
//             kestrel_paula.c): loudness envelopes correlate, and the band spectra match (the pitch)
//   owner     a song request while the cart holds the channels is refused; chip RAM is untouched
//
//   node apps/pt2_paula_headless.mjs [--break pitch|latch|upload|owner]
// --break passes only if a check notices: pitch (every period doubled on the way: an octave down),
// latch (paula.zig mutant 2: LC/LEN taken at once, not at the wrap: one-shots cut), upload (no sample
// reaches chip RAM), owner (the worklet's refusal bypassed: the song is let in).
import { readFile } from "node:fs/promises";
import { boot, step, DT } from "./ports_machine.mjs";
import { RATE, bootWorklet, paulaEnv, envelope, bestCorr, bandSpectrum, cosine } from "./paula_lib.mjs";

const CART = "docs/demo-pt2.wasm", DISK = "docs/demo-pt2.zmd", FRAMES = 520, PLAY = 200, SW_RATE = 24000;
const BREAKS = ["pitch", "latch", "upload", "owner"];
const isPer = (a) => a >= 0xdff0a0 && a < 0xdff0e0 && (a & 15) === 6; // AUDxPER
const args = process.argv.slice(2), broke = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (broke && !BREAKS.includes(broke)) throw new Error(`--break ${broke}: one of ${BREAKS.join(", ")}`);

// ports_headless.mjs pt2's clicks: DISK OP, the second file (RONKEN.MOD: rows of 6 from y 34), PLAY
// (pt2's coordinates; pointer() takes x doubled and y in the visible window, 28 rows down).
const click = (x, y, b) => (d) => d.pointer(x * 2, y - 28, b);
const press = (f, x, y) => [[f - 1, click(x, y, 0)], [f, click(x, y, 1)], [f + 6, click(x, y, 0)]];
const EVENTS = [...press(100, 212, 38), ...press(130, 100, 42), ...press(PLAY, 150, 5)];

let failures = 0;
const check = (name, ok, detail = "") => {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
};

// One run: `hw` lends the channels (the worklet renders each frame's 735 samples after it), else the
// claim is refused and the software mixer's 8-bit stream is kept.
async function run(hw) {
    const disk = await readFile(DISK);
    let m = null, w = null, pe = null, fedAtClaim = -1;
    if (hw) {
        w = await bootWorklet();
        if (broke === "latch") w.d.audioHipMutant(2);
        const tamper = {
            dropUploads: broke === "upload",
            batch: broke === "pitch" ? (dv, n) => { for (let i = 0; i < n; i++) if (isPer(dv.getUint32(16 * i + 4, true))) dv.setUint32(16 * i + 8, Math.min(0xffff, dv.getUint32(16 * i + 8, true) * 2), true); } : null,
        };
        pe = paulaEnv(() => m.memory, w, tamper);
    }
    const env = hw ? { ...pe.env, hostPaulaClaim: (lead) => { fedAtClaim = m ? m.audio.n : 0; return pe.env.hostPaulaClaim(lead); } } : { keepAudio: true };
    m = await boot(CART, disk, 0, env);
    let owed = 0;
    for (let f = 1; f <= FRAMES; f++) {
        for (const [ef, fn] of EVENTS) if (ef === f) fn(m.demo);
        step(m);
        if (!hw) continue;
        owed += RATE * DT / 1000;
        const blocks = Math.floor(owed / 128);
        w.render(blocks);
        owed -= blocks * 128;
    }
    return { m, w, pe, fedAtClaim };
}

const sw = await run(false), hw = await run(true);
const d = hw.w.d;
console.log(`pt2 on the hardware Paula channels: ${CART} + ${DISK}${broke ? ` (--break ${broke})` : ""}`);
check("claim", hw.pe.st.claims === 1 && d.audioPaulaClaimed() === 1, `${hw.pe.st.claims} claim, the worklet holds it: ${d.audioPaulaClaimed()}`);
check("no stream once claimed", hw.m.audio.n === hw.fedAtClaim && hw.m.audio.stops >= 1,
    `${hw.m.audio.n} bytes fed in all (${hw.fedAtClaim} before the claim), ${hw.m.audio.stops} stream stop`);

// The music: from PLAY to the end, on both sides.
const hwAll = hw.w.samples(), hwMus = hwAll.subarray(Math.floor(PLAY * RATE * DT / 1000));
const swAll = Float32Array.from(sw.m.audio.keep.flatMap((c) => Array.from(c)), (v) => v / 128);
const swMus = swAll.subarray(Math.floor(PLAY * SW_RATE * DT / 1000));
const rms = Math.sqrt(hwMus.reduce((s, v) => s + v * v, 0) / hwMus.length);
check("plays", rms > 0.02, `rms ${rms.toFixed(4)} over ${(hwMus.length / RATE).toFixed(2)} s after PLAY`);
const applied = d.audioPaulaApplied(), refused = d.audioPaulaRefused(), dropped = d.audioPaulaDropped(), resyncs = d.audioPaulaResyncs();
check("writes land", applied > 200 && refused === 0 && dropped === 0 && resyncs === 0,
    `${hw.pe.st.entries} sent in ${hw.pe.st.writes} batches, ${applied} applied, ${refused} refused, ${dropped} dropped, ${resyncs} resyncs; ${hw.pe.st.uploads} uploads, ${d.audioPaulaLatches()} latches`);

// 20 ms windows on each side; the lag absorbs the two leads (both 125 ms) and the frame edges.
const eHw = envelope(hwMus, RATE / 50), eSw = envelope(swMus, SW_RATE / 50);
const best = bestCorr(eSw, eHw, 15);
check("follows the software mixer (loudness)", best.c > 0.85, `envelope correlation ${best.c.toFixed(3)} at ${best.lag * 20} ms`);
const spec = cosine(bandSpectrum(hwMus, RATE), bandSpectrum(swMus, SW_RATE));
// Semitone bands: 0.89 measured (the software path point-samples at 24 kHz through the A500 filter), an
// octave off 0.56.
check("follows the software mixer (pitch)", spec > 0.75, `semitone-band spectra cosine ${spec.toFixed(3)}`);

// A song request while the cart holds the channels: refused, chip RAM as it was.
const chip = () => new Uint8Array(hw.w.p.memory.buffer, d.audioPaulaChipPtr(), d.audioPaulaChipSize());
const before = chip().slice(), saidBefore = hw.w.said.length;
if (broke === "owner") hw.w.p.demo = { ...d, audioPaulaClaimed: () => 0 }; // the guard sees no claim
hw.w.send({ type: "loadMod", bytes: (await readFile("docs/music/hybridglenz.mod")).buffer });
hw.w.p.demo = d;
const refusedMsg = hw.w.said.slice(saidBefore).some((s) => s.type === "paulaRefused");
const same = chip().every((v, i) => v === before[i]);
check("owner: a song is refused while the cart holds the channels", refusedMsg && same && d.audioPaulaClaimed() === 1,
    `refused: ${refusedMsg}, chip RAM untouched: ${same}`);

if (broke) {
    console.log(failures ? `\npt2_paula: PASS (--break ${broke} was caught)` : `\npt2_paula: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\npt2_paula: ${failures} FAILED` : "\npt2_paula: PASS");
process.exit(failures ? 1 : 0);
