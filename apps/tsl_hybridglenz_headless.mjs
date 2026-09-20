// Headless THE SILENTS / HYBRID GLENZ driver — boots the sealed machine +
// demo-tsl_hybridglenz.wasm the way docs/sealed-loader.js does, and proves the
// two things this port is about:
//
//  1. the glenz is the BLITTER's OR minterm, so the panel carries index 3 — a
//     value no primitive ever writes, only 1 | 2 can produce it;
//  2. the two objects are INTERLACED by the halftone, so object 1's ink lands
//     only on ODD plane rows and object 2's only on EVEN ones.
//
// Reading the plane's INDEX framebuffer makes both claims direct. Geometry: an
// overscan plane, 400x280, holding a 360x283 Amiga screen cropped to 280 and
// centred at x = 20. The physical framebuffer is 800x280 with x DOUBLED.
//
//   node apps/tsl_hybridglenz_headless.mjs [outdir] [--break <what>]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk
const OFF_PAL = 0x0100, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44; // memmap.zig
// assets.zig's palette slots
const PANEL = 0, GLENZ_R = 1, GLENZ_W = 2, GLENZ_RW = 3, BG = 4, WHITE = 5, BAR = 6;
const FONT_BASE = 8, FONT_INKS = 9, TXT_BASE = 17, LOGO_BASE = 32, LOGO_N = 23;
// stage.zig's layout
const X_OFF = 20, PANEL_X = 96 + X_OFF, PANEL_Y = 85, PANEL_SIZE = 176;
const BAR_Y = 254, BAR_H = 20, TEXT_Y = 258;
const WANT_MUSIC = "hybridglenz.mod";
// timeline.zig: the cues, resolved off hybridglenz.mod itself
const P1 = 1.68, P2 = 9.12, P5 = 22.68, P6 = 17.88, P7 = 25.56;
const DT = 1000 / 60;

const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
let failures = 0;
function check(name, got, want) {
    const ok = got === want;
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}: got ${got}, want ${want}`);
}

async function boot(cart) {
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
    const cartBytes = await readFile(cart), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const { memory, machine, demo } = await boot("docs/demo-tsl_hybridglenz.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const VB = machine.hwVideoBase();
const regs = new DataView(memory.buffer, VB, OFF_PAL);
const PW = regs.getUint16(REG_FB_STRIDE, true); // 400: the whole raster
const indices = () => new Uint8Array(memory.buffer, VB + regs.getUint32(REG_FB_BASE, true), PW * H);
const palette = () => new Uint32Array(memory.buffer, VB + OFF_PAL, 256);
let clock = 0;

async function shot(path) {
    machine.hwRenderPlane(0);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const hdr = new TextEncoder().encode(`P6\n${PW} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + PW * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < PW; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * PW + x) * 3 + c] = px[(y * W + x * 2) * 4 + c];
    await writeFile(path, buf);
    console.log(`  shot: ${path} (t = ${clock.toFixed(2)} s)`);
}

/// Run to `t` seconds of the scene's wall clock, in 60 Hz steps.
function runTo(t) {
    while (clock < t - 1e-9) {
        demo.frame(DT);
        clock += DT / 1000;
    }
}

/// A histogram of the whole plane, plus where the glenz ink fell.
function census() {
    const lfb = indices();
    const n = new Array(256).fill(0);
    for (const v of lfb) n[v]++;
    let oddInk = 0, evenInk = 0, panelInk = 0, outsideInk = 0, lowest = -1;
    for (let y = 0; y < H; y++)
        for (let x = 0; x < PW; x++) {
            const v = lfb[y * PW + x];
            if (v !== BG) lowest = Math.max(lowest, y);
            if (v !== GLENZ_R && v !== GLENZ_W && v !== GLENZ_RW) continue;
            const inside = x >= PANEL_X && x < PANEL_X + PANEL_SIZE && y >= PANEL_Y && y < PANEL_Y + PANEL_SIZE;
            if (!inside) { outsideInk++; continue; }
            panelInk++;
            if (y & 1) oddInk++; else evenInk++;
        }
    return { n, oddInk, evenInk, panelInk, outsideInk, lowest };
}

const rgb = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255].join(",");
const sum = (n, from, len) => n.slice(from, from + len).reduce((a, b) => a + b, 0);

const out = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/tsl_hybridglenz";
await mkdir(out, { recursive: true });
if (W !== 800 || PW !== 400 || H !== 280) console.log(`  note: physical ${W}x${H}, plane stride ${PW}`);

const dec = new TextDecoder();
const song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
check("it asks for the screen's own ProTracker module", song, WANT_MUSIC);

// --- part1: the square flies in ------------------------------------------
// Before P1 it is parked at size 2.5 / rot -180 / x 100, a big flat white slab.
runTo(1.0);
await shot(`${out}/0-square-parked.ppm`);
let c = census();
check("the square is solid white before its cue", c.n[WHITE] > 20000, true);
check("... and the framed panel is not drawn yet", c.n[PANEL], 0);

// Mid-flight it is turned off axis, so it is neither the parked slab nor the frame.
runTo(P1 + 2);
await shot(`${out}/1-square-turning.ppm`);

// P1 + 5 ends the alpha fade: the panel is down and palette entry 0 has walked
// all the way from white to '#221133'.
runTo(P1 + 5.01);
await shot(`${out}/2-panel.ppm`);
c = census();
check("the framed panel is drawn once the square dissolves", c.n[PANEL] > 29000, true);
check("... and the white frame is a 1 px ring", c.n[WHITE], PANEL_SIZE * 4 - 4);
check("the panel colour finished its fade at '#221133'", rgb(palette()[PANEL]), "34,17,51");

// txt1 rises out of the background between P2 and P2+1.
runTo(P2 + 1.0);
await shot(`${out}/3-txt1.ppm`);
c = census();
check("txt1 is blitted", c.n[TXT_BASE] > 1000, true);
check("... as white, at the top of its fade", rgb(palette()[TXT_BASE]), "255,255,255");

// P5 drops the logo in white-hot, then lets its 22 colours fade up over 1 s.
runTo(P5 + 0.02);
await shot(`${out}/4-logo-flash.ppm`);
let hot = 0;
for (let i = 0; i < LOGO_N; i++) if (rgb(palette()[LOGO_BASE + i]).split(",").every((v) => +v >= 250)) hot++;
check("the logo arrives white-hot on all but its own '#221133'", hot, LOGO_N - 1);
runTo(P5 + 1.01);
await shot(`${out}/5-logo.ppm`);
c = census();
check("the logo is on the plane", sum(c.n, LOGO_BASE, LOGO_N) > 10000, true);
check("... and its colours have finished coming up", rgb(palette()[LOGO_BASE + 9]), "136,17,17");
check("... including the one the white overlay never covered", rgb(palette()[LOGO_BASE + 1]), "34,17,51");

// P6 slides the bar up over 5 s, from 2x y 600 (off a 568-tall canvas) to 508 —
// which lands at 22.88, AFTER the logo cue, so it is checked in that order.
runTo(P6 + 5.01);
c = census();
const lfb0 = indices();
check("the bar has landed, full raster width", lfb0[(BAR_Y + 1) * PW] === BAR && lfb0[(BAR_Y + 1) * PW + PW - 1] === BAR, true);
check("... with its white edges", lfb0[BAR_Y * PW + 200] === WHITE && lfb0[(BAR_Y + BAR_H - 1) * PW + 200] === WHITE, true);

// --- go(): the glenz ------------------------------------------------------
runTo(P7 + 0.5);
await shot(`${out}/6-glenz.ppm`);
c = census();
console.log(`  glenz: ${c.panelInk} ink px (${c.oddInk} odd rows, ${c.evenInk} even), overlap ${c.n[GLENZ_RW]}`);
check("both objects are drawn", c.panelInk > 8000, true);
check("object 1 owns the ODD plane rows", c.oddInk > 3000, true);
check("object 2 owns the EVEN ones", c.evenInk > 3000, true);
check("neither leaks outside the panel", c.outsideInk, 0);
check("the OR minterm really produced 1|2 = 3", c.n[GLENZ_RW] > 1000, true);
check("... and all three glenz inks are present", c.n[GLENZ_R] > 0 && c.n[GLENZ_W] > 0, true);
check("content reaches the opened bottom border", c.lowest >= BAR_Y + BAR_H - 1, true);

// A frame later the object has turned: a static picture would be identical.
const before = Array.from(indices().subarray(PANEL_Y * PW, (PANEL_Y + PANEL_SIZE) * PW));
runTo(P7 + 0.5 + (broke === "spin" ? 0 : 1.0));
const after = indices().subarray(PANEL_Y * PW, (PANEL_Y + PANEL_SIZE) * PW);
let moved = 0;
for (let i = 0; i < before.length; i++) if (before[i] !== after[i]) moved++;
check("the objects rotate", moved > 2000, true);

// The 21 s morph chain: 5 s in, the two objects are walking to DIFFERENT sets
// (MORPH1 -> SLAB, MORPH2 -> SPIKE), so their silhouettes must differ.
runTo(P7 + 6.0);
await shot(`${out}/7-morphed.ppm`);
c = census();
console.log(`  after the first morph: ${c.panelInk} ink px, odd ${c.oddInk} even ${c.evenInk}`);
// The text opens on 65 spaces (23 of padding, 42 of its own), so at 1.65 px a
// frame the first '*' only reaches the window a few hundred frames in.
const fontPx = sum(c.n, FONT_BASE, FONT_INKS);
let fontTop = 1e9, fontBottom = -1;
{ const lfb = indices();
  for (let y = 0; y < H; y++) for (let x = 0; x < PW; x++) {
      const v = lfb[y * PW + x];
      if (v >= FONT_BASE && v < FONT_BASE + FONT_INKS) { fontTop = Math.min(fontTop, y); fontBottom = Math.max(fontBottom, y); } } }
console.log(`  scroller: ${fontPx} ink px on rows ${fontTop}..${fontBottom}`);
check("the scrolltext is drawing", fontPx > 500, true);
// An OR that strayed onto the white frame would make 5|1 = 5 or 5|2 = 7, and 7
// is an index the palette never defines: black, on a screen with no black.
const known = new Set([PANEL, GLENZ_R, GLENZ_W, GLENZ_RW, BG, WHITE, BAR]);
for (let i = 0; i < FONT_INKS; i++) known.add(FONT_BASE + i);
for (let i = 0; i < 3; i++) known.add(TXT_BASE + i);
for (let i = 0; i < LOGO_N; i++) known.add(LOGO_BASE + i);
const stray = c.n.reduce((a, v, i) => a + (known.has(i) ? 0 : v), 0);
check("no pixel carries an index the palette does not define", stray, 0);
check("... inside the bar, which is rows " + BAR_Y + ".." + (BAR_Y + BAR_H - 1), fontTop >= BAR_Y + 1 && fontBottom <= BAR_Y + BAR_H - 2, true);
check("the two objects morph apart (different areas)", Math.abs(c.oddInk - c.evenInk) > 200, true);

// Warm frame cost in go(), the expensive half: 48 blitter triangles, a full
// plane fill, the logo, the bar and the scroller, every frame.
const N = 400;
let bestCart = Infinity, bestPlane = Infinity;
for (let i = 0; i < 5; i++) {
    let t = process.hrtime.bigint();
    for (let k = 0; k < N; k++) demo.frame(DT);
    bestCart = Math.min(bestCart, Number(process.hrtime.bigint() - t) / 1e6 / N);
    t = process.hrtime.bigint();
    for (let k = 0; k < N; k++) machine.hwRenderPlane(0);
    bestPlane = Math.min(bestPlane, Number(process.hrtime.bigint() - t) / 1e6 / N);
}
console.log(`  frame cost: cart ${bestCart.toFixed(3)} ms, plane ${bestPlane.toFixed(3)} ms`);
check("the cart fits a 16.6 ms frame with room to spare", bestCart + bestPlane < 8, true);

if (broke) {
    const ok = failures > 0;
    console.log(ok ? `\ntsl_hybridglenz: PASS (--break ${broke} was caught)` : `\ntsl_hybridglenz: FAILED — --break ${broke} was not caught`);
    process.exit(ok ? 0 : 1);
}
console.log(failures ? `\ntsl_hybridglenz: ${failures} FAILED` : "\ntsl_hybridglenz: PASS");
process.exit(failures ? 1 : 0);
