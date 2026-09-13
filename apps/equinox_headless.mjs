// Headless EQUINOX check: the seven dragons hatch, live and go back to the egg.
//
// The dragons (plane 2) once drew one dragon and six eggs on an invented sine
// path and never changed shape — the morph of CODEF wab screen 015 was simply
// missing, and nothing errors when that happens. This re-derives the original's
// sprite layer independently from screen.js — the trajectory (152-185), the
// morph state machine (morphSprite, 216-268) and the draw (301-306) — and
// asserts that plane 2 is EXACTLY those seven blits at several phases:
//   - every sampled frame matches the expected pixels (shape, position, colour),
//   - the expected morph frame per phase is egg / hatching / dragon / egg,
//   - the pixel set of the egg and of the dragon differ (the morph changes shape).
//
//   node apps/equinox_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // the visible window in the physical frame (x doubled)
const DRAGONS = 7, TRAIL = 18, DW = 32, DH = 26;
// frame -> the morph frame screen.js shows there (7 = egg, 0 = dragon)
const PHASES = [[300, 7], [640, 3], [700, 0], [1000, 2], [1530, 5], [2000, 7]];
const ASSETS = "apps/zig/assets/screens/equinox";

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

    const noop = () => {};
    const cartBytes = await readFile(cart);
    const env = {
        memory,
        hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
        hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree,
        ...rom,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// screen.js:152-185, on the 640-wide canvas, halved to ST pixels
function trajectory() {
    const xs = [], ys = [];
    let fx = 0, fy = 0;
    for (let i = 0; i < 1500; i++) {
        if (i < 125 || i >= 950) { fx += 0.05; fy += 0.05; }
        else if (i < 220) { fx += 0.03; fy += 0.035; }
        else if (i < 480) { fx += 0.06; fy += 0.03; }
        else if (i < 630) { fx += 0.045; fy += 0.035; }
        else { fx += 0.02; fy += 0.045; }
        xs[i] = Math.floor((320 - 64 / 2 + ((256 - 64 / 2 - 5.0) * Math.cos(fx))) / 2);
        ys[i] = Math.floor((200 - 52 / 2 + 30 + ((128 - 52 / 2 - 10.0) * Math.sin(fy))) / 2);
    }
    return { xs, ys };
}

// morphSprite(), screen.js:216-268: the morph frame after `frames` go() calls
function morphFrameAt(frames) {
    let state = "in_egg", type = 7, inc = 1, ticks = 0;
    for (let f = 1; f <= frames; f++) {
        if (f % 10) continue;
        ticks++;
        if (state === "in_egg") { type = 7; if (ticks === 60) { state = "morphing"; ticks = 0; } }
        else if (state === "morphing") { if (type > 0) type--; if (ticks === 20) { state = "alive"; ticks = 0; } }
        else if (state === "alive") {
            if (type === 0) inc = 1; else if (type === 3) inc = -1;
            type += inc;
            if (ticks === 70) { state = "demorphing"; ticks = 0; }
        } else { if (type < 7) type++; if (ticks === 20) { state = "in_egg"; ticks = 0; } }
    }
    return type;
}

// the expected 320x200 index image of plane 2 after `frames` frames (-1 = clear)
function expected(frames, dragons, path) {
    const img = new Int16Array(320 * 200).fill(-1);
    const sprite = dragons[morphFrameAt(frames)];
    const tabpos = frames - 1;
    for (let n = 0; n < DRAGONS; n++) {
        const i = tabpos + n * TRAIL, x0 = path.xs[i % 940], y0 = path.ys[i % 964];
        for (let y = 0; y < DH; y++) for (let x = 0; x < DW; x++) {
            const p = sprite[y * DW + x], X = x0 + x, Y = y0 + y;
            if (p && X >= 0 && X < 320 && Y >= 0 && Y < 200) img[Y * 320 + X] = p;
        }
    }
    return img;
}

const outdir = process.argv[2];
const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-equinox.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const size = W * H * 4;
const pal = await readFile(`${ASSETS}/bobs_pal.dat`);
const dragons = [];
for (let i = 1; i <= 8; i++) dragons.push(await readFile(`${ASSETS}/bob${i}.raw`));
const path = trajectory();
const errors = [], inked = {};

let f = 0;
for (const [frame, want] of PHASES) {
    const got = morphFrameAt(frame);
    if (got !== want) errors.push(`frame ${frame}: reference morph frame ${got}, table says ${want}`);
    const layers = [];
    while (f < frame) {
        machine.hwClear();
        demo.frame(1000 / 60);
        f++;
    }
    for (let p = 0; p < 4; p++) {
        machine.hwRenderPlane(p);
        layers.push(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), size).slice());
    }
    const exp = expected(frame, dragons, path), px = layers[2];
    let wrong = 0, ink = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const o = ((y + TOP) * W + LEFT + 2 * x) * 4, e = exp[y * 320 + x];
        if (px[o + 3]) ink++;
        if (e < 0 ? px[o + 3] !== 0 : (px[o + 3] === 0 || px[o] !== pal[e * 4] || px[o + 1] !== pal[e * 4 + 1] || px[o + 2] !== pal[e * 4 + 2])) wrong++;
    }
    if (wrong) errors.push(`frame ${frame} (morph frame ${want}): ${wrong} dragon px differ from screen.js`);
    inked[frame] = ink;
    if (outdir) await shot(`${outdir}/equinox-${frame}.ppm`, layers);
}
// the morph must change SHAPE, not just position: egg and dragon differ in ink
const egg = dragons[7].filter(Boolean).length, dragon = dragons[0].filter(Boolean).length;
if (egg === dragon) errors.push(`egg and dragon both carry ${egg} px per sprite`);
if (inked[300] === inked[700]) errors.push(`plane 2 carries ${inked[300]} px as egg and as dragon`);

// the visible 320x200, planes blended bottom first, halved horizontally
async function shot(file, layers) {
    const hdr = new TextEncoder().encode(`P6\n320 200\n255\n`);
    const buf = new Uint8Array(hdr.length + 320 * 200 * 3);
    buf.set(hdr);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const o = ((y + TOP) * W + LEFT + 2 * x) * 4, d = hdr.length + (y * 320 + x) * 3;
        for (const l of layers) if (l[o + 3]) for (let c = 0; c < 3; c++) buf[d + c] = l[o + c];
    }
    await writeFile(file, buf);
}

if (errors.length) {
    console.error(`equinox: dragon morph WRONG\n  ${errors.join("\n  ")}`);
    process.exit(1);
}
console.log(`equinox: 7 dragons match screen.js at ${PHASES.length} phases (egg ${inked[300]} px, dragon ${inked[700]} px)`);
