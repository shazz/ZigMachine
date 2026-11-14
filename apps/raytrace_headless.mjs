// Headless RAYTRACE driver -- boots the sealed machine + demo-raytrace the way
// docs/sealed-loader.js does, and runs each of its three maths (keys 1..3, the
// host's setShadeMode 0..2: Q16.16 and f32 on the cart CPU, f64 on ASTROLABE, here
// the machine's own hwAstro, as the page binds it).
//
// Each mode runs once per answer to env.hostMicros (the benchmark clock,
// apps/zig/scenes/raytrace/bench.zig):
//   none  the import left to the no-op stub (0), as on a host without a clock:
//         FIXED work, 512 samples a frame; run to the end of the 16 passes;
//   fake  a clock that moves 500 us a call: TIMED work, deterministic: 16 chunks a
//         frame (16 samples each on ZIGGY, one 64-ray batch on ASTROLABE), so the
//         frame counts, the rate and the time to converge are exact; run to the end
//         (ASTROLABE: to its first picture, its convergence is the none run's);
//   real  performance.now(): the benchmark itself, printed, not asserted; run to the
//         first picture.
//
// What is checked, per mode (row 199's tap strip, apps/zig/scenes/raytrace/hud.zig,
// carries the counters):
//   1. the first picture COMPLETES at exactly 110 frames with no clock and at
//      320*176 / chunk-a-frame with the fake one; pass 16 at 16 x that; then it stops;
//   2. it is PROGRESSIVE: frame 1 partly drawn, frame 2 the 8x8-block preview, the
//      drawn fraction never falls, the pass counter only steps by one;
//   3. the PICTURES are right: sky, both floor tones, all five spheres, a floor shadow,
//      a chrome sphere mirroring floor and sky; refinement changes the picture, softens
//      edges and adds a penumbra (raytrace_lib.mjs);
//   4. both pictures are PINNED (SHA-256 of rows 0..175), the same under every clock:
//      the per-pixel sums are integers, whatever a frame's share;
//   5. the ray count is plausible; the RATE reads 0 with no clock, exactly the fake
//      clock's (32000 / 128000 px/s), above 0 with the real one; the fake clock's
//      time to converge is exact (16 passes x frames x 8 ms);
//   6. Fire restarts the run, and a mode key restarts it in that mode;
//   7. the cart's frames fit the 60 fps budget in node (timed: alone): 99 % of them,
//      hwAstro's own time apart (the machine's stand-in for the ARM, not the cart's
//      work); a box busy with other jobs still spikes the odd frame, so the worst is printed.
// Across the modes: the first pictures agree, and so do the converged ones (mean RGB
// error under 2.5), with the same ray counts within 2 %.
//
//   node apps/raytrace_headless.mjs [outdir]            outdir gets PPMs of every mode
//   node apps/raytrace_headless.mjs --break pixel       one wrong pixel: caught
//   node apps/raytrace_headless.mjs --break clock       a clock that never moves: caught
//   node apps/raytrace_headless.mjs --break smooth      refinement that changes nothing: caught
import { mkdir, writeFile } from "node:fs/promises";
import * as R from "./raytrace_lib.mjs";

const { W, IMG_H } = R;
const MODES = ["fixed", "f32", "astro"];
const CHUNK = { fixed: 16, f32: 16, astro: 64 };
const PASSES = 16, MAX_FRAMES = 4000, FAKE_US = 500, BUDGET_US = 8000;
// Pinned fingerprints, rows 0..175 of the RGB frame: [first picture, converged].
const PINNED = {
    fixed: ["1b69c3e50cfce683ee8758a9179374b9a57f529427a01d357f8089bb5e94e230", "44b5e22c46d95da3a44d26d1dcfd9bcbe84573a07ab18c9daf808918acdd82db"],
    f32: ["721e27b54e431823a09af08b297eaf7ec0b9b4a82515ea8159c6830cf9999266", "5f7fec28104e95f128ebd498f9f961e99e61867e15dde954802e1234b0980367"],
    astro: ["9f1fbc95983a9e7b30e34a7253cbbd23692c746764917785d7541f74991fba06", "4ee076273c18f9fb7824b3b53f7b852449abbacc869089f56d309cec952479df"],
};
// The runs [mode, clock, to convergence]; a --break run takes the cheap ones that show it.
const PLAN = {
    all: [...["none", "fake", "real"].flatMap((c) => MODES.map((m) => [m, c, c === "none" || (c === "fake" && m !== "astro")]))],
    pixel: [["fixed", "none", true], ["f32", "none", true]],
    clock: [["fixed", "fake", false], ["f32", "fake", false]],
    smooth: [["f32", "none", true]],
};

const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/raytrace";
const errors = [];
const fail = (m) => { errors.push(m); console.log(`  FAIL ${m}`); };
const check = (ok, m) => { if (!ok) fail(m); };

function clockFor(clock) {
    if (clock === "real") return () => Math.floor(performance.now() * 1000) >>> 0;
    if (clock === "fake") { let t = 0; return () => (t = (t + (brk === "clock" ? 0 : FAKE_US)) >>> 0) || 1; }
    return null; // left to the no-op stub, as a host without the import
}

// Frames to the first picture: 512 samples a frame with no clock, 16 chunks with the fake one.
const perFrame = (mode, clock) => (clock === "none" ? 512 : (BUDGET_US / FAKE_US) * CHUNK[mode]);
const framesToDone = (mode, clock) => (clock === "real" ? 0 : Math.ceil(56320 / perFrame(mode, clock)));

// Runs one mode to its first picture (and on to pass 16 when `full`), checking as it goes.
async function play(mode, clock, full) {
    const m = await R.boot("demo-raytrace", clockFor(clock));
    m.demo.setShadeMode(MODES.indexOf(mode));
    const s = { m, ms: [], astroMs: 0, doneAt: 0, convAt: 0, first: null, rgb: null, tap: null };
    let last = 0, lastPass = 0;
    for (let f = 1; f <= MAX_FRAMES; f++) {
        const a0 = m.astroMs, r = R.frame(m);
        s.ms.push(r.ms - (m.astroMs - a0)); s.astroMs = Math.max(s.astroMs, m.astroMs - a0);
        s.rgb = r.rgb; s.tap = R.readTap(r.rgb);
        const d = R.drawn(r.rgb);
        if (clock === "none" && f === 1) check(d > 0.2 && d < 0.9, `${mode}: frame 1 should be a partial preview (drawn ${d.toFixed(3)})`);
        if (clock === "none" && f === 2) check(R.blocky(r.rgb) > 0.9, `${mode}: frame 2 should be the 8x8-block preview (blocky ${R.blocky(r.rgb).toFixed(2)})`);
        check(d + 1e-9 >= last, `${mode}: drawn fraction fell at frame ${f}`);
        check(s.tap.pass === lastPass || s.tap.pass === lastPass + 1, `${mode}: pass counter ${lastPass} -> ${s.tap.pass} at frame ${f}`);
        last = d; lastPass = s.tap.pass;
        if (s.tap.done && !s.doneAt) { s.doneAt = f; s.first = { rgb: r.rgb, tap: s.tap }; check(s.tap.pass === 1, `${mode}: first picture done at pass ${s.tap.pass}`); }
        if (s.doneAt && !full) break;
        if (s.tap.pass >= PASSES) { s.convAt = f; break; }
    }
    return s;
}

async function run(mode, clock, full) {
    console.log(`${mode} (clock ${clock}${full ? ", 16 passes" : ""}):`);
    const s = await play(mode, clock, full);
    const { first } = s, tap = first?.tap ?? s.tap, rgb = first?.rgb ?? s.rgb;
    const ms = s.ms.sort((a, b) => a - b), p99 = ms[Math.floor(ms.length * 0.99)];
    console.log(`  first picture at frame ${s.doneAt} (rays ${tap.rays}, ${tap.rate} px/s)${full ? `, converged at ${s.convAt} (${s.tap.convMs} ms of tracing)` : ""}, cart frame p99 ${p99.toFixed(2)} ms, worst ${ms.at(-1).toFixed(2)} ms (+ hwAstro up to ${s.astroMs.toFixed(2)} ms)`);
    check(s.doneAt > 0 && (!full || s.convAt > 0), `${mode}: never ${full ? "converged" : "finished"} in ${MAX_FRAMES} frames`);
    check(R.blocky(rgb) < 0.6, `${mode}: the first picture is still blocky`);
    const want = framesToDone(mode, clock);
    if (want) check(s.doneAt === want, `${mode}: first picture at frame ${s.doneAt}, expected ${want}`);
    if (want && full) check(s.convAt === PASSES * want, `${mode}: pass ${PASSES} ends at frame ${s.convAt}, expected ${PASSES * want}`);
    check(tap.frames === s.doneAt, `${mode}: frame counter ${tap.frames}, done at ${s.doneAt}`);
    if (clock === "none") check(tap.rate === 0 && s.tap.convMs === 0, `${mode}: no clock, yet ${tap.rate} px/s, ${s.tap.convMs} ms`);
    if (clock === "fake") {
        const rate = perFrame(mode, clock) * 1e6 / BUDGET_US;
        check(tap.rate === rate, `${mode}: fake-clock rate ${tap.rate} px/s, expected ${rate}`);
        if (full) check(s.tap.convMs === PASSES * want * BUDGET_US / 1000, `${mode}: fake-clock convergence ${s.tap.convMs} ms, expected ${PASSES * want * BUDGET_US / 1000}`);
    }
    if (clock === "real") check(tap.rate > 0, `${mode}: the real clock measured no rate`);
    check(tap.rays > 56320 * 1.3 && tap.rays < 56320 * 2.5, `${mode}: ray count ${tap.rays} implausible`);
    check(p99 < 16.6, `${mode}: 1 % of the cart frames took over ${p99.toFixed(2)} ms, over the 60 fps budget`);
    if (brk === "pixel") rgb[(40 * W + 40) * 3] ^= 0x40;
    R.checkPicture(check, mode, rgb);
    R.checkChrome(check, mode, rgb);
    const hashes = [R.sha(rgb)];
    let conv = null;
    if (full) {
        const after = R.frame(s.m).rgb; // a converged run traces nothing more
        check(R.readTap(after).frames === s.tap.frames, `${mode}: frame counter moved after the last pass`);
        check(R.sha(after) === R.sha(s.rgb), `${mode}: the picture changed after the last pass`);
        conv = brk === "smooth" ? first.rgb : s.rgb;
        if (brk === "pixel") conv[(40 * W + 40) * 3] ^= 0x40;
        R.checkRefined(check, mode, rgb, conv);
        hashes.push(R.sha(conv));
    }
    console.log(`  fingerprints ${hashes.join(" ")}`);
    hashes.forEach((h, i) => check(h === PINNED[mode][i], `${mode}: ${["first", "converged"][i]} fingerprint ${h.slice(0, 16)} != pinned ${PINNED[mode][i].slice(0, 16)}`));
    if (clock === "fake") checkRestart(mode, s.m, s.rgb);
    if (clock === "none") {
        await writeFile(`${outdir}/raytrace-${mode}-first.ppm`, R.ppm(rgb));
        if (conv) await writeFile(`${outdir}/raytrace-${mode}-converged.ppm`, R.ppm(conv));
    }
    return { rgb, conv, tap };
}

// Fire (input 5) restarts the run on the next frame; so does a mode key, in its mode: the
// counters start again and the picture is the coarse preview again, not the finished one.
function checkRestart(mode, m, done) {
    for (const [what, act] of [["Fire", () => m.demo.input(5)], ["the next mode's key", () => m.demo.setShadeMode((MODES.indexOf(mode) + 1) % 3)]]) {
        act();
        const r = R.frame(m), tap = R.readTap(r.rgb);
        let same = 0;
        for (let i = 0; i < W * IMG_H * 3; i++) same += r.rgb[i] === done[i];
        check(tap.frames === 1 && !tap.done && tap.pass === 0, `${mode}: ${what} did not restart the run (frames ${tap.frames}, pass ${tap.pass})`);
        check(same < 0.7 * W * IMG_H * 3, `${mode}: ${what} left the finished picture up (${(same / (W * IMG_H * 3)).toFixed(3)} the same)`);
    }
}

function compare(runs) {
    for (const [a, b] of [["fixed", "f32"], ["f32", "astro"], ["fixed", "astro"]]) for (const k of ["rgb", "conv"]) {
        const x = runs[`${a}/none`][k], y = runs[`${b}/none`][k];
        let err = 0;
        for (let i = 0; i < W * IMG_H * 3; i++) err += Math.abs(x[i] - y[i]);
        const mean = err / (W * IMG_H * 3);
        console.log(`${a} vs ${b} (${k === "rgb" ? "first" : "converged"}): mean abs RGB error ${mean.toFixed(3)}`);
        check(mean < 2.5, `${a} and ${b} pictures drift apart (mean error ${mean.toFixed(2)})`);
    }
    for (const [a, b] of [["fixed", "f32"], ["f32", "astro"]]) {
        const r = [runs[`${a}/none`].tap.rays, runs[`${b}/none`].tap.rays];
        check(Math.abs(r[0] - r[1]) < 0.02 * r[1], `ray counts differ: ${a} ${r[0]}, ${b} ${r[1]}`);
    }
}

await mkdir(outdir, { recursive: true });
const runs = {};
for (const [mode, clock, full] of PLAN[brk ?? "all"]) runs[`${mode}/${clock}`] = await run(mode, clock, full);
if (!brk) {
    console.log(`benchmark (node, real clock, first picture): ${MODES.map((m) => `${m} ${runs[`${m}/real`].tap.rate} px/s`).join(", ")}`);
    compare(runs);
}
if (brk) { // a --break run PASSES when the harness caught the damage
    console.log(errors.length ? `raytrace: PASS (--break ${brk} caught: ${errors.length} failures)` : `raytrace: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
if (errors.length) { console.log(`${errors.length} FAILURE(S)`); process.exit(1); }
console.log("raytrace: OK");
