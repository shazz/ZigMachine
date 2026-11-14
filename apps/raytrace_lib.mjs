// What apps/raytrace_headless.mjs checks in a RAYTRACE picture (apps/zig/scenes/raytrace/):
// boot, one host frame read back as RGB, the HUD's binary tap strip, and the picture
// tests (the scene's content, the chrome sphere's mirror, what refinement must change).
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

export const W = 320, H = 200, IMG_H = 176, HORIZON = 62;
const PAGES = 128; // SHARED_PAGES in machine/sdk/memmap.zig
const PANEL = [8, 8, 24]; // hud.zig's PANEL through the machine's 565 expansion

export async function boot(name, clock) {
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
    // hwAstro: the machine's own ASTROLABE, as docs/sealed-loader.js binds it, timed apart
    // (the stand-in for the board's ARM: its time is not the cart's frame)
    const box = { astroMs: 0 };
    env.hwAstro = (desc, count) => {
        const t = performance.now(), st = machine.hwAstro(desc, count);
        box.astroMs += performance.now() - t;
        return st;
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, get astroMs() { return box.astroMs; } };
}

// One host frame; returns the visible 320x200 RGB (physical (80,40), x doubled).
export function frame({ memory, machine, demo }) {
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

export const px = (rgb, x, y) => { const i = (y * W + x) * 3; return [rgb[i], rgb[i + 1], rgb[i + 2]]; };
const bits = (rgb, x0, n) => { let v = 0; for (let i = 0; i < n; i++) v = v * 2 + (px(rgb, x0 + i, 199)[0] > 30 ? 1 : 0); return v; };
export const readTap = (rgb) => ({ frames: bits(rgb, 255, 16), rays: bits(rgb, 271, 24), done: bits(rgb, 295, 1), rate: bits(rgb, 296, 24), pass: bits(rgb, 232, 6), convMs: bits(rgb, 200, 24) });
export const sha = (rgb) => createHash("sha256").update(rgb.subarray(0, W * IMG_H * 3)).digest("hex");
export const drawn = (rgb) => { let n = 0; for (let y = 0; y < IMG_H; y++) for (let x = 0; x < W; x++) { const p = px(rgb, x, y); if (p[0] !== PANEL[0] || p[1] !== PANEL[1] || p[2] !== PANEL[2]) n++; } return n / (W * IMG_H); };
export const ppm = (rgb) => Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]);

// Fraction of 8x8 blocks whose corners are within the dither of each other: ~1 in the level-0 preview.
export function blocky(rgb) {
    let flat = 0, n = 0;
    for (let by = 0; by < IMG_H; by += 8) for (let bx = 0; bx < W; bx += 8) {
        const a = px(rgb, bx, by), b = px(rgb, bx + 7, by + 7);
        n++; if (a.every((v, i) => Math.abs(v - b[i]) <= 12)) flat++;
    }
    return flat / n;
}

function classify([r, g, b]) {
    if (b > 2 * r && b > 1.3 * g && r < 60) return "blue";
    if (r > 150 && g < 80 && b < 80) return "red";
    if (r > 180 && g > 120 && b < 80) return "gold";
    if (g > 130 && r < 90 && b < 140) return "green";
    return "other";
}

export function checkPicture(check, name, rgb) {
    const count = {}, bump = (k) => { count[k] = (count[k] ?? 0) + 1; };
    let darkFloor = 0, skyTop = 0, skyBottomWarm = 0;
    for (let y = 0; y < IMG_H; y++) for (let x = 0; x < W; x++) {
        const p = px(rgb, x, y);
        bump(classify(p));
        if (y < 20 && p[2] > p[1] + 30 && p[0] < 200) skyTop++; // cool mauve/blue
        if (y > HORIZON + 8 && p[0] > 25 && p[0] < 95 && Math.abs(p[0] - p[1]) < 14 && Math.abs(p[1] - p[2]) < 22) darkFloor++; // shadowed cream tiles: dark grey
        if (y > HORIZON - 6 && y <= HORIZON && p[0] > 200) skyBottomWarm++;
    }
    console.log(`  ${name} colours: ${JSON.stringify(count)} skyTop=${skyTop} warmHorizon=${skyBottomWarm} shadowFloor=${darkFloor}`);
    for (const k of ["red", "gold", "blue", "green"]) check((count[k] ?? 0) > 300, `${name}: sphere colour ${k} missing (${count[k] ?? 0} px)`);
    check(skyTop > 2000, `${name}: no cool sky at the top (${skyTop})`);
    check(skyBottomWarm > 800, `${name}: no peach glow at the horizon (${skyBottomWarm})`);
    check(darkFloor > 150, `${name}: no shadow on the floor (${darkFloor})`);
}

// The chrome sphere (centre ~ pixel (160, 78)) mirrors BOTH the floor and the sky.
export function checkChrome(check, name, rgb) {
    let cream = 0, sky = 0;
    for (let y = 40; y < 100; y++) for (let x = 130; x < 200; x++) {
        const [r, g, b] = px(rgb, x, y);
        if (r > 190 && g > 180 && b > 150 && Math.abs(r - g) < 25) cream++;
        if (b > 80 && b > r + 30) sky++;
    }
    check(cream > 40, `${name}: chrome sphere shows no mirrored floor (${cream})`);
    check(sky > 40, `${name}: chrome sphere shows no mirrored sky (${sky})`);
}

// Colours present in the picture, on a 2x2 box filter (so the 565 dither's own texture
// does not count): a point-sampled edge is one step, an anti-aliased one a ramp.
function smoothColours(rgb) {
    const seen = new Set();
    for (let y = 0; y < IMG_H - 1; y += 2) for (let x = 0; x < W - 1; x += 2) {
        const a = [px(rgb, x, y), px(rgb, x + 1, y), px(rgb, x, y + 1), px(rgb, x + 1, y + 1)];
        seen.add([0, 1, 2].map((c) => (a[0][c] + a[1][c] + a[2][c] + a[3][c]) >> 4).join());
    }
    return seen.size;
}

// Penumbra: cream floor pixels lit by between 45 and 85 % of the sun. colour.zig's floor
// is mix(CREAM * q, HORIZON, fog): a least-squares fit of the pixel onto s * CREAM +
// f * HORIZON (a small residual: cream, not a tile edge or a sphere) gives q = s / (1 - f).
// A point-sampled shadow is q 80/256 or 1 and nothing between (the 565 dither moves q by
// a few %); averaged samples of a soft one fill the band between.
const CREAM = [236, 226, 204], PEACH = [255, 168, 112];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
function penumbra(rgb) {
    const a11 = dot(CREAM, CREAM), a12 = dot(CREAM, PEACH), a22 = dot(PEACH, PEACH), det = a11 * a22 - a12 * a12;
    let n = 0;
    for (let y = HORIZON + 4; y < IMG_H; y++) for (let x = 0; x < W; x++) {
        const m = px(rgb, x, y);
        const b1 = dot(CREAM, m), b2 = dot(PEACH, m), s = (b1 * a22 - b2 * a12) / det, f = (a11 * b2 - a12 * b1) / det;
        const res = Math.hypot(...m.map((v, c) => s * CREAM[c] + f * PEACH[c] - v));
        const q = s / (1 - f);
        if (res < 10 && s > 0 && f >= 0 && f < 0.8 && q > 0.45 && q < 0.85) n++;
    }
    return n;
}

// What the 15 refinement passes must change: the picture, its edges (anti-aliasing: more
// smooth colours), its shadows (a penumbra); the scene stays the scene.
export function checkRefined(check, name, first, conv) {
    let diff = 0;
    for (let i = 0; i < W * IMG_H; i++) if (first[i * 3] !== conv[i * 3] || first[i * 3 + 1] !== conv[i * 3 + 1] || first[i * 3 + 2] !== conv[i * 3 + 2]) diff++;
    const col = [smoothColours(first), smoothColours(conv)], pen = [penumbra(first), penumbra(conv)];
    console.log(`  refined: ${diff} px changed, smooth colours ${col.join(" -> ")}, penumbra ${pen.join(" -> ")}`);
    check(diff > 0.03 * W * IMG_H, `${name}: refinement changed only ${diff} px`);
    check(col[1] > 1.2 * col[0], `${name}: edges did not soften (smooth colours ${col.join(" -> ")})`);
    check(pen[0] < 50 && pen[1] > 500, `${name}: no soft-shadow penumbra (${pen.join(" -> ")})`);
    checkPicture(check, `${name} converged`, conv);
    checkChrome(check, `${name} converged`, conv);
}
