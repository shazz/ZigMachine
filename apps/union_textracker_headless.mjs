// Headless Union Demo HIDDEN SCREEN check (apps/zig/scenes/union_textracker.zig).
//
// 1. The depack: the cart must start behind the TEX loader panel (zx0.Fx.tex_loader)
//    with screens/textracker/loader.js's own text. Every frame of it shows only
//    the loader ink #C0A000 on black, and the last one has every letter of the
//    first 18 columns landed where TEXLoader.resetScroller puts them, drawn from
//    the halved loader.png font.
// 2. The screen: frame by frame with the mouse path of apps/union_textracker_replay.mjs,
//    compared pixel for pixel with the JS replay of screen.js, which in turn matches
//    the remake running in Chrome exactly (0 px over the same 13 frames).
// 3. Escape asks for the Union Demo menu's disk (pollCartRequest 1, tag union_demo).
// 4. A warm frame (cart update+render and hwRenderPlane) fits well inside 60 fps.
//
//   node apps/union_textracker_headless.mjs [outdir] [cart.wasm] [--break trail|blend]
// --break runs the replay with a wrong trail spacing (7) or a float-rounded alpha
// blend: the check must then FAIL, which is how the harness proves it can.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeReplay, mouseAt, SHOTS } from "./union_textracker_replay.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // the 320x200 window in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_textracker";
const PANEL = `${ASSETS}/loader_textracker.txt`;
const INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012;
const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at >= 0 ? argv[at + 1] : null;
if (at >= 0 && brk !== "trail" && brk !== "blend") throw new Error(`--break takes trail or blend, not ${brk}`);
const args = at >= 0 ? [...argv.slice(0, at), ...argv.slice(at + 2)] : argv;
const outDir = args[0] || "/tmp/union_textracker";
const cartPath = args[1] || "docs/demo-union_textracker.wasm";

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
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom, diskReadBlock: () => 0 }; // no disk: the screen runs silent
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

/// The 320x200 window as the host composites it, over black.
function capture(memory, machine, demo) {
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), img = new Uint8Array(320 * 200 * 3);
    machine.hwClear();
    let planes = 0;
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        planes++;
        machine.hwRenderPlane(p);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const i = ((TOP + y) * W + LEFT + x * 2) * 4, a = px[i + 3] / 255, o = (y * 320 + x) * 3;
            for (let c = 0; c < 3; c++) img[o + c] = Math.round(img[o + c] * (1 - a) + px[i + c] * a);
        }
    }
    return { img, planes };
}

function png(w, h, rgb) {
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc32 = (buf) => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) Buffer.from(rgb.buffer, rgb.byteOffset + y * w * 3, w * 3).copy(raw, y * (w * 3 + 1) + 1);
    const chunk = (type, data) => {
        const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
        const td = Buffer.concat([Buffer.from(type), data]);
        const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
        return Buffer.concat([len, td, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

/// The loader panel with every letter landed: row r's top at 8 + 8r, column c at 80 + 8c
/// (TEXLoader.resetScroller: x 168 + 16c, y 376 - 16*rows_below, midhandled, halved).
async function landedPanel() {
    const rows = (await readFile(PANEL, "utf8")).split("\n").filter((l) => l.startsWith('"')).map((l) => l.slice(1, -1));
    const font = await readFile("libs/zig/depackers/tex_loader/loader.raw"); // 80x48, 10 glyphs a row
    const ink = new Uint8Array(320 * 200);
    rows.forEach((row, r) => [...row].forEach((ch, c) => {
        const g = ch.charCodeAt(0) - 32;
        for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++)
            if (font[(Math.floor(g / 10) * 8 + y) * 80 + (g % 10) * 8 + x]) ink[(8 + 8 * r + y) * 320 + 80 + 8 * c + x] = 1;
    }));
    return { ink, cols: rows[0].length };
}

const errors = [];
await mkdir(outDir, { recursive: true });
const { memory, machine, demo } = await boot(cartPath);
const replay = makeReplay(await readFile(`${ASSETS}/screen.raw`), await readFile(`${ASSETS}/pal.dat`),
    brk === "trail" ? { trailStep: 7 } : brk === "blend" ? { mix: (s, d) => Math.round(s * 0.9 + d * 0.1) } : {});
const isMenu = (img) => { let n = 0; for (let i = 0; i < img.length; i += 3) if (img[i] === 224 && img[i + 1] === 224 && img[i + 2] === 224) n++; return n > 1000; };
const same = (a, b) => a.every((v, i) => v === b[i]);

// ---- 1. the depack behind the TEX loader panel -------------------------------
demo.pointer(...mouseAt(1), 0);
let depackFrames = 0, last = null, shot;
for (;;) {
    demo.frame(1000 / 60);
    shot = capture(memory, machine, demo);
    if (isMenu(shot.img)) break;
    depackFrames++;
    for (let i = 0; i < shot.img.length; i += 3) {
        const c = [shot.img[i], shot.img[i + 1], shot.img[i + 2]];
        if (!same(c, [0, 0, 0]) && !same(c, INK)) { errors.push(`depack frame ${depackFrames}: colour ${c} is not the loader ink`); break; }
    }
    if (depackFrames === 58) await writeFile(`${outDir}/union_textracker-depack.png`, png(320, 200, shot.img));
    last = shot.img;
    if (depackFrames > 2000) { errors.push("the screen never appeared"); break; }
}
if (depackFrames < 30) errors.push(`the depack took ${depackFrames} frames: no TEX loader panel to speak of`);
if (last) {
    const { ink, cols } = await landedPanel();
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 80; x < 80 + 8 * (cols - 2); x++) {
        const lit = last[(y * 320 + x) * 3] === INK[0];
        if (lit !== (ink[y * 320 + x] === 1)) wrong++;
    }
    if (wrong) errors.push(`last depack frame: ${wrong} px of the first ${cols - 2} panel columns differ from loader.js's text`);
}

// ---- 2. the screen against the screen.js replay ------------------------------
let cartMs = 0, renderMs = 0, timed = 0;
for (let f = 1; f <= SHOTS[SHOTS.length - 1]; f++) {
    if (f > 1) {
        demo.pointer(...mouseAt(f), 0);
        const t0 = performance.now();
        demo.frame(1000 / 60);
        const t1 = performance.now();
        shot = capture(memory, machine, demo);
        if (f > 30) { cartMs += t1 - t0; renderMs += performance.now() - t1; timed++; }
    }
    if (shot.planes !== 1) errors.push(`frame ${f}: ${shot.planes} planes enabled, the screen uses one`);
    if (!SHOTS.includes(f)) continue;
    const want = replay(f);
    let wrong = 0, first = null;
    for (let i = 0; i < want.length; i += 3) if (want[i] !== shot.img[i] || want[i + 1] !== shot.img[i + 1] || want[i + 2] !== shot.img[i + 2]) {
        wrong++;
        first ??= `(${(i / 3) % 320},${Math.floor(i / 3 / 320)}) got ${[...shot.img.subarray(i, i + 3)]} want ${[...want.subarray(i, i + 3)]}`;
    }
    if (wrong) errors.push(`frame ${f}: ${wrong} px differ from the screen.js replay, first ${first}`);
    await writeFile(`${outDir}/union_textracker-${String(f).padStart(4, "0")}.png`, png(320, 200, shot.img));
}

// ---- 3. leaving ----------------------------------------------------------------
if (demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asks for request ${req} tag "${tag}", not 1 "union_demo"`);

// ---- 4. cost ---------------------------------------------------------------------
const perFrame = cartMs / timed, perRender = renderMs / timed;
if (perFrame > 2) errors.push(`cart update+render takes ${perFrame.toFixed(3)} ms a frame`);

if (errors.length) {
    console.error(`union_textracker: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_textracker: TEX loader panel over ${depackFrames} depack frames; screen.js replay exact at frames ${SHOTS.join(",")}; ` +
    `Escape -> union_demo; warm ${perFrame.toFixed(3)} ms cart + ${perRender.toFixed(3)} ms hwRenderPlane a frame; shots in ${outDir}`);
