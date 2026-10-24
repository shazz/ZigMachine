// Headless RAYTRACE driver -- boots the sealed machine + demo-raytrace (Q16.16)
// and demo-raytrace_f32 the way docs/sealed-loader.js does, runs each to the
// end of its progressive render, and checks the picture and the benchmark.
//
// Each cart runs three times, one per answer to env.hostMicros (the benchmark
// clock, apps/zig/scenes/raytrace/bench.zig):
//   none  the import left to the no-op stub (0), as on a host without a clock:
//         FIXED work, 512 px a frame;
//   fake  a clock that moves 500 us a call: TIMED work, deterministic, so the
//         frame count and the measured rate are exact;
//   real  performance.now(): the benchmark itself, printed, not asserted.
//
// What is checked, per cart:
//   1. the render COMPLETES: the cart's own done flag (read off the binary
//      strip on row 199, apps/zig/scenes/raytrace/hud.zig) rises at exactly
//      ceil(320*176 / 512) = 110 frames with no clock, and at 320*176 / 256 =
//      220 with the fake one (16 checks of 16 px fill the 8 ms budget);
//   2. it is PROGRESSIVE: after frame 2 the picture is partly drawn and the
//      drawn fraction only ever grows (no clock);
//   3. the PICTURE is right: sky above the horizon, both floor tones, all five
//      spheres, a shadow on the floor (dark floor shades), the chrome sphere
//      holds a mirrored floor and a mirrored sky, and a SHA-256 fingerprint of
//      the finished frame is pinned per cart -- the SAME under all three
//      clocks, since every pixel is traced once whatever a frame's share;
//   4. the ray count is plausible (1 primary per pixel, shadows, reflections);
//   5. the RATE: no clock reads 0; the fake clock reads exactly 32000 px/s
//      (256 px per 8000 us); the real one is above 0;
//   6. Fire restarts the run: frame counter back to 1, picture cleared;
//   7. the cart frame stays inside the 60 fps budget in node (timed: alone).
// Across the two carts: the fixed-point picture matches the f32 one (mean RGB
// error under 2.5 levels; dither and Q16 rounding are the only differences).
//
// The f32 cart then REFINES (refine.zig): PASSES - 1 more samples a pixel, one
// pass per 110 frames with no clock, so the tap's pass counter (row 199, x 232)
// reaches 16 at exactly frame 16 x 110 (x 220 with the fake clock), and it
// stops there. Its first picture is the one pinned above; the converged one
// has its own pin, the same under all three clocks, and must differ the ways
// refinement promises (raytrace_refine_lib.mjs): a penumbra appears on the
// floor, silhouettes and tile edges become coverage dithers,
// and every pixel is still a palette colour.
//
//   node apps/raytrace_headless.mjs [outdir]            outdir gets PPMs of both
//   node apps/raytrace_headless.mjs --break pixel       one wrong pixel: caught
//   node apps/raytrace_headless.mjs --break clock       a clock that never moves: caught
//   node apps/raytrace_headless.mjs --break smooth      refinement that changes nothing: caught
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { checkRefined } from "./raytrace_refine_lib.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200, IMG_H = 176, HORIZON = 62;
const FRAMES_TO_DONE = { none: 110, fake: 220 };
const FAKE_RATE = 32000; // px/s: 256 px per 8000 fake us
const MAX_FRAMES = 6000;
const PASSES = { "demo-raytrace": 1, "demo-raytrace_f32": 16 };
// Pinned fingerprints of the finished PICTURE, rows 0..175 of the RGB frame
// (printed by every run). The HUD below it carries each run's own counters and
// rate, so it is read off the tap strip instead of being hashed.
const PINNED = {
    "demo-raytrace": "e03b7477be51699b0b2b50536f63293844e3fe1a7dd8d3e0e5d2f906a4a15646",
    "demo-raytrace_f32": "4f7e751848b5f65f1db89f0782dee3cb0aaee0084d923fbb0c09995d3a399d89",
};
// (The f32 cart's converged picture is pinned in raytrace_refine_lib.mjs.)

const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/raytrace";
const errors = [];
const fail = (m) => { errors.push(m); console.log(`  FAIL ${m}`); };
const check = (ok, m) => { if (!ok) fail(m); };

async function boot(name, clock) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(`docs/${name}.wasm`);
    const noop = () => {};
    const env = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit, ...machine, ...rom };
    if (clock) env.hostMicros = clock;
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// One host frame; returns the visible 320x200 RGB (physical (80,40), x doubled).
function frame({ memory, machine, demo }) {
    machine.hwClear();
    const t = performance.now();
    demo.frame(16.6);
    const ms = performance.now() - t;
    machine.hwRenderPlane(0);
    const pw = machine.hwPhysWidth();
    const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), pw * machine.hwPhysHeight() * 4);
    const rgb = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const s = ((40 + y) * pw + 80 + x * 2) * 4, d = (y * W + x) * 3;
        rgb[d] = pfb[s]; rgb[d + 1] = pfb[s + 1]; rgb[d + 2] = pfb[s + 2];
    }
    return { rgb, ms };
}

const px = (rgb, x, y) => { const i = (y * W + x) * 3; return [rgb[i], rgb[i + 1], rgb[i + 2]]; };
const bits = (rgb, x0, n) => { let v = 0; for (let i = 0; i < n; i++) v = v * 2 + (px(rgb, x0 + i, 199)[0] > 30 ? 1 : 0); return v; };
const readTap = (rgb) => ({ frames: bits(rgb, 255, 16), rays: bits(rgb, 271, 24), done: bits(rgb, 295, 1), rate: bits(rgb, 296, 24), pass: bits(rgb, 232, 6) });
const sha = (rgb) => createHash("sha256").update(rgb.subarray(0, W * IMG_H * 3)).digest("hex");
const drawn = (rgb) => { let n = 0; for (let y = 0; y < IMG_H; y++) for (let x = 0; x < W; x++) { const p = px(rgb, x, y); if (p[0] !== 12 || p[1] !== 12 || p[2] !== 28) n++; } return n / (W * IMG_H); };

// Fraction of 8x8 blocks that are one flat colour: ~1 in the level-0 preview.
function blocky(rgb) {
    let flat = 0, n = 0;
    for (let by = 0; by < IMG_H; by += 8) for (let bx = 0; bx < W; bx += 8) {
        const a = px(rgb, bx, by), b = px(rgb, bx + 7, by + 7);
        n++; if (a[0] === b[0] && a[1] === b[1] && a[2] === b[2]) flat++;
    }
    return flat / n;
}

// Class of a pixel by its colour, from the palette layout in palette.zig.
function classify([r, g, b]) {
    if (b > 2 * r && b > 1.3 * g && r < 60) return "blue";
    if (r > 150 && g < 80 && b < 80) return "red";
    if (r > 180 && g > 120 && b < 80) return "gold";
    if (g > 130 && r < 90 && b < 140) return "green";
    return "other";
}

function checkPicture(name, rgb) {
    const count = {}, bump = (k) => { count[k] = (count[k] ?? 0) + 1; };
    let darkFloor = 0, skyTop = 0, skyBottomWarm = 0;
    for (let y = 0; y < IMG_H; y++) for (let x = 0; x < W; x++) {
        const p = px(rgb, x, y);
        bump(classify(p));
        if (y < 20 && p[2] > p[1] + 30 && p[0] < 200) skyTop++; // cool mauve/blue
        if (y > HORIZON + 8 && p[0] > 25 && p[0] < 95 && Math.abs(p[0] - p[1]) < 12 && Math.abs(p[1] - p[2]) < 20) darkFloor++; // shadowed cream tiles: dark grey
        if (y > HORIZON - 6 && y <= HORIZON && p[0] > 200) skyBottomWarm++;
    }
    console.log(`  ${name} colours: ${JSON.stringify(count)} skyTop=${skyTop} warmHorizon=${skyBottomWarm} shadowFloor=${darkFloor}`);
    for (const k of ["red", "gold", "blue", "green"]) check((count[k] ?? 0) > 300, `${name}: sphere colour ${k} missing (${count[k] ?? 0} px)`);
    check(skyTop > 2000, `${name}: no cool sky at the top (${skyTop})`);
    check(skyBottomWarm > 800, `${name}: no peach glow at the horizon (${skyBottomWarm})`);
    check(darkFloor > 150, `${name}: no shadow on the floor (${darkFloor})`);
}

// The chrome sphere (centre ~ pixel (160+..., 78)) must mirror BOTH the floor
// and the sky: its disc holds floor-tone cream AND deep sky blue pixels.
function checkChrome(name, rgb) {
    let cream = 0, sky = 0;
    for (let y = 40; y < 100; y++) for (let x = 130; x < 200; x++) {
        const [r, g, b] = px(rgb, x, y);
        if (r > 190 && g > 180 && b > 150 && Math.abs(r - g) < 25) cream++;
        if (b > 80 && b > r + 30) sky++;
    }
    check(cream > 40, `${name}: chrome sphere shows no mirrored floor (${cream})`);
    check(sky > 40, `${name}: chrome sphere shows no mirrored sky (${sky})`);
}

function clockFor(mode) {
    if (mode === "real") return () => Math.floor(performance.now() * 1000) >>> 0;
    if (mode === "fake") { let t = 0; return () => (t = (t + (brk === "clock" ? 0 : 500)) >>> 0) || 1; }
    return null; // left to the no-op stub, as a host without the import
}

async function runCart(name, mode) {
    console.log(`${name} (clock ${mode}):`);
    const m = await boot(name, clockFor(mode));
    const passes = PASSES[name];
    let last = 0, ms = 0, tap = null, rgb = null, doneAt = 0, convAt = 0, lastPass = 0, first = null;
    for (let f = 1; f <= MAX_FRAMES && !convAt; f++) {
        const r = frame(m);
        ms = Math.max(ms, r.ms); rgb = r.rgb;
        tap = readTap(rgb);
        const d = drawn(rgb);
        if (mode === "none" && f === 1) check(d > 0.2 && d < 0.9, `${name}: frame 1 should be a partial preview (drawn ${d.toFixed(3)})`);
        if (mode === "none" && f === 2) check(blocky(rgb) > 0.9, `${name}: frame 2 should be the 8x8-block preview (blocky ${blocky(rgb).toFixed(2)})`);
        check(d + 1e-9 >= last, `${name}: drawn fraction fell at frame ${f}`);
        check(tap.pass === lastPass || tap.pass === lastPass + 1, `${name}: pass counter ${lastPass} -> ${tap.pass} at frame ${f}`);
        last = d; lastPass = tap.pass;
        if (tap.done && !doneAt) { doneAt = f; first = { rgb, tap }; check(tap.pass === 1, `${name}: first picture done at pass ${tap.pass}`); }
        if (tap.pass >= passes) convAt = f;
    }
    // A converged cart traces nothing more: the frame after leaves tap and picture alone.
    const after = frame(m).rgb;
    check(readTap(after).frames === tap.frames, `${name}: frame counter moved after the last pass (${tap.frames} -> ${readTap(after).frames})`);
    check(sha(after) === sha(rgb), `${name}: the picture changed after the last pass`);
    const conv = brk === "smooth" && first ? first.rgb : rgb;
    if (first) ({ rgb, tap } = first);
    const nsPx = tap.rate ? (1e9 / tap.rate).toFixed(0) : "-";
    console.log(`  done at frame ${doneAt}, tap frames=${tap.frames} rays=${tap.rays} rate=${tap.rate} px/s (${nsPx} ns/px), worst cart frame ${ms.toFixed(2)} ms`);
    check(doneAt > 0, `${name}: never completed in ${MAX_FRAMES} frames`);
    check(blocky(rgb) < 0.5, `${name}: the final frame is still blocky`);
    if (FRAMES_TO_DONE[mode]) check(doneAt === FRAMES_TO_DONE[mode], `${name}: completes at frame ${doneAt}, expected ${FRAMES_TO_DONE[mode]}`);
    if (FRAMES_TO_DONE[mode]) check(convAt === passes * FRAMES_TO_DONE[mode], `${name}: pass ${passes} ends at frame ${convAt}, expected ${passes * FRAMES_TO_DONE[mode]}`);
    check(tap.frames === doneAt, `${name}: frame counter ${tap.frames}, done at ${doneAt}`);
    if (mode === "none") check(tap.rate === 0, `${name}: no clock, yet a rate of ${tap.rate} px/s`);
    if (mode === "fake") check(tap.rate === FAKE_RATE, `${name}: fake-clock rate ${tap.rate} px/s, expected ${FAKE_RATE}`);
    if (mode === "real") check(tap.rate > 0, `${name}: the real clock measured no rate`);
    check(tap.rays > 56320 * 1.3 && tap.rays < 56320 * 2.5, `${name}: ray count ${tap.rays} implausible`);
    check(ms < 16.6, `${name}: a frame took ${ms.toFixed(2)} ms, over the 60 fps budget`);
    if (brk === "pixel") { rgb[(40 * W + 40) * 3] ^= 0x40; conv[(40 * W + 40) * 3] ^= 0x40; }
    checkPicture(name, rgb);
    checkChrome(name, rgb);
    const hash = sha(rgb);
    console.log(`  fingerprint ${hash}`);
    if (PINNED[name]) check(hash === PINNED[name], `${name}: fingerprint ${hash.slice(0, 16)} != pinned ${PINNED[name].slice(0, 16)}`);
    if (passes > 1) checkRefined({ check, sha, checkPicture, checkChrome }, name, rgb, conv, convAt);
    if (mode === "fake") checkRestart(name, m);
    if (mode === "none") await writeFile(`${outdir}/${name}.ppm`, ppm(rgb));
    if (mode === "none" && passes > 1) await writeFile(`${outdir}/${name}-converged.ppm`, ppm(conv));
    return { rgb, tap, doneAt };
}

const ppm = (rgb) => Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]);

// Fire (input 5) restarts the run on the next frame: counter 1, picture cleared.
function checkRestart(name, m) {
    m.demo.input(5);
    const r = frame(m), tap = readTap(r.rgb);
    check(tap.frames === 1 && !tap.done, `${name}: Fire did not restart the run (frames ${tap.frames}, done ${tap.done})`);
    check(drawn(r.rgb) < 0.9, `${name}: the restarted run did not clear the picture (drawn ${drawn(r.rgb).toFixed(3)})`);
}

await mkdir(outdir, { recursive: true });
const runs = {};
for (const mode of ["none", "fake", "real"])
    for (const name of Object.keys(PINNED)) runs[`${name}/${mode}`] = await runCart(name, mode);
const fixed = runs["demo-raytrace/none"], f32 = runs["demo-raytrace_f32/none"];
console.log(`benchmark (node, real clock): fixed ${runs["demo-raytrace/real"].tap.rate} px/s, f32 ${runs["demo-raytrace_f32/real"].tap.rate} px/s`);
let err = 0;
for (let i = 0; i < W * IMG_H * 3; i++) err += Math.abs(fixed.rgb[i] - f32.rgb[i]);
const mean = err / (W * IMG_H * 3);
console.log(`fixed vs f32: mean abs RGB error ${mean.toFixed(3)}, rays ${fixed.tap.rays} vs ${f32.tap.rays}`);
check(mean < 2.5, `fixed-point picture drifts from the f32 one (mean error ${mean.toFixed(2)})`);
check(Math.abs(fixed.tap.rays - f32.tap.rays) < 0.02 * f32.tap.rays, `ray counts differ: ${fixed.tap.rays} vs ${f32.tap.rays}`);
if (brk) { // a --break run PASSES when the harness caught the damage
    console.log(errors.length ? `raytrace: PASS (--break ${brk} caught: ${errors.length} failures)` : `raytrace: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
if (errors.length) { console.log(`${errors.length} FAILURE(S)`); process.exit(1); }
console.log("raytrace: OK");
