// Headless RAYTRACE driver -- boots the sealed machine + demo-raytrace (Q16.16)
// and demo-raytrace_f32 the way docs/sealed-loader.js does, runs each to the
// end of its progressive render, and checks the picture and the benchmark.
//
// What is checked, per cart:
//   1. the render COMPLETES: the cart's own done flag (read off the binary
//      strip on row 199, apps/zig/scenes/raytrace/hud.zig) rises at exactly
//      ceil(320*176 / 512) = 110 frames, and not before;
//   2. it is PROGRESSIVE: after frame 2 the picture is partly drawn and the
//      drawn fraction only ever grows;
//   3. the PICTURE is right: sky above the horizon, both floor tones, all five
//      spheres, a shadow on the floor (dark floor shades), the chrome sphere
//      holds a mirrored floor and a mirrored sky, and a SHA-256 fingerprint of
//      the finished frame is pinned per cart;
//   4. the ray count is plausible (1 primary per pixel, shadows, reflections);
//   5. the cart frame stays inside the 60 fps budget in node (timed: alone).
// Across the two carts: the fixed-point picture matches the f32 one (mean RGB
// error under 2.5 levels; dither and Q16 rounding are the only differences).
//
//   node apps/raytrace_headless.mjs [outdir]            outdir gets PPMs of both
//   node apps/raytrace_headless.mjs --break pixel       one wrong pixel: caught
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200, IMG_H = 176, HORIZON = 62;
const FRAMES_TO_DONE = 110;
// Pinned fingerprints of the finished 320x200 RGB frame (printed by every run).
const PINNED = {
    "demo-raytrace": "5c7c0b66fb2701b401ce784741431adc16ba2382fa2fee020239c24d0b09a07c",
    "demo-raytrace_f32": "149630b0ccf67422d662479da38f85a1c351524cf087152916afdbcaa0616f59",
};

const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/raytrace";
const errors = [];
const fail = (m) => { errors.push(m); console.log(`  FAIL ${m}`); };
const check = (ok, m) => { if (!ok) fail(m); };

async function boot(name) {
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
const readTap = (rgb) => ({ frames: bits(rgb, 256, 16), rays: bits(rgb, 272, 24), done: bits(rgb, 296, 1) });
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

async function runCart(name) {
    console.log(`${name}:`);
    const m = await boot(name);
    let last = 0, ms = 0, frames = 0, tap = null, rgb = null, doneAt = 0;
    for (let f = 1; f <= 140; f++) {
        const r = frame(m);
        ms = Math.max(ms, r.ms); rgb = r.rgb; frames = f;
        tap = readTap(rgb);
        const d = drawn(rgb);
        if (f === 1) check(d > 0.2 && d < 0.9, `${name}: frame 1 should be a partial preview (drawn ${d.toFixed(3)})`);
        if (f === 2) check(blocky(rgb) > 0.9, `${name}: frame 2 should be the 8x8-block preview (blocky ${blocky(rgb).toFixed(2)})`);
        if (f === 110) check(blocky(rgb) < 0.5, `${name}: the final frame is still blocky`);
        check(d + 1e-9 >= last, `${name}: drawn fraction fell at frame ${f}`);
        last = d;
        if (tap.done && !doneAt) doneAt = f;
    }
    console.log(`  done at frame ${doneAt}, tap frames=${tap.frames} rays=${tap.rays}, worst cart frame ${ms.toFixed(2)} ms`);
    check(doneAt === FRAMES_TO_DONE, `${name}: completes at frame ${doneAt}, expected ${FRAMES_TO_DONE}`);
    check(tap.frames === FRAMES_TO_DONE, `${name}: frame counter ${tap.frames}`);
    check(tap.rays > 56320 * 1.3 && tap.rays < 56320 * 2.5, `${name}: ray count ${tap.rays} implausible`);
    check(ms < 16.6, `${name}: a frame took ${ms.toFixed(2)} ms, over the 60 fps budget`);
    if (brk === "pixel") rgb[(40 * W + 40) * 3] ^= 0x40;
    checkPicture(name, rgb);
    checkChrome(name, rgb);
    const hash = createHash("sha256").update(rgb).digest("hex");
    console.log(`  fingerprint ${hash}`);
    if (PINNED[name]) check(hash === PINNED[name], `${name}: fingerprint ${hash.slice(0, 16)} != pinned ${PINNED[name].slice(0, 16)}`);
    await writeFile(`${outdir}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]));
    return { rgb, tap, doneAt };
}

await mkdir(outdir, { recursive: true });
const fixed = await runCart("demo-raytrace");
const f32 = await runCart("demo-raytrace_f32");
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
