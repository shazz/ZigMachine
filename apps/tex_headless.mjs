// Headless TEX check (CODEF screen 14): the eleven sprites follow screen.js's
// own chain, frame by frame.
//
// go() (screen.js:114-118) advances every phase by 0.04 and then draws sprite i
// at x = 305 + 306*sin(p), y = 86 + 84*cos(1.5p), p starting at 0.3*(i+1). The
// browser draws an unscaled image at the ROUNDED canvas coordinate; halved, that
// is floor(round(c) / 2). This rebuilds the expected sprite layer from those
// formulas and the .raw images and asserts, on plane 1 (logo + sprites):
//   - every sprite pixel not covered by a later sprite has the sprite's colour,
//     at several frames (the path, the draw order, the Y's column alignment),
//   - the sprites MOVE between two sampled frames (a frozen phase would pass a
//     single-frame check only if it froze at frame 1),
//   - a sprite crossing the left edge is clipped, not pinned to x = 0,
//   - the frame loop holds a 60 fps budget with headroom.
//
//   node apps/tex_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // the visible window in the physical frame (x doubled)
const FRAMES = [1, 60, 61, 200, 1234, 3600];
const ASSETS = "apps/zig/assets/screens/the_union/";
const NAMES = ["delta", "delta", "delta", "h", "o", "w", "d", "y", "delta", "delta", "delta"];

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

/// The screen.js position of sprite i after `frame` calls of go(), halved.
function spriteAt(i, frame) {
    let p = 0.3 * (i + 1);
    for (let k = 0; k < frame; k++) p += 0.04; // accumulate exactly as the JS does
    return [Math.floor(Math.round(305 + 306 * Math.sin(p)) / 2), Math.floor(Math.round(86 + 84 * Math.cos(p * 1.5)) / 2)];
}

/// Plane-1 pixel index per screen pixel for the sprite layer; -1 where no sprite.
function expectedLayer(images, frame) {
    const layer = new Int16Array(320 * 200).fill(-1);
    images.forEach((img, i) => {
        const [sx, sy] = spriteAt(i, frame);
        for (let r = 0; r < 8; r++) for (let c = 0; c < 16; c++) {
            const v = img[r * 16 + c], x = sx + c, y = sy + r;
            if (v && x >= 0 && x < 320 && y >= 0 && y < 200) layer[y * 320 + x] = v;
        }
    });
    return layer;
}

const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-tex.wasm");
const images = await Promise.all(NAMES.map((n) => readFile(`${ASSETS}${n}.raw`)));
const pal = await readFile(`${ASSETS}logo_pal.dat`);
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const errors = [];
const layers = new Map();
let frame = 0, cartMs = 0, leftClip = 0;

for (const target of FRAMES) {
    const t0 = performance.now();
    while (frame < target) { demo.frame(1000 / 60); frame++; }
    cartMs += performance.now() - t0;
    machine.hwRenderPlane(1);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const want = expectedLayer(images, frame);
    let checked = 0, wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const v = want[y * 320 + x];
        if (v < 0) continue;
        checked++;
        const o = ((y + TOP) * W + LEFT + x * 2) * 4;
        if (px[o] !== pal[v * 4] || px[o + 1] !== pal[v * 4 + 1] || px[o + 2] !== pal[v * 4 + 2]) wrong++;
    }
    if (checked < 200) errors.push(`frame ${frame}: only ${checked} sprite px on screen`);
    if (wrong) errors.push(`frame ${frame}: ${wrong}/${checked} sprite px off the screen.js path`);
    NAMES.forEach((_, i) => { if (spriteAt(i, frame)[0] < 0) leftClip++; });
    layers.set(frame, { want, checked });

    if (process.argv[2]) {
        const hdr = new TextEncoder().encode(`P6\n320 200\n255\n`);
        const buf = new Uint8Array(hdr.length + 320 * 200 * 3);
        buf.set(hdr);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) for (let c = 0; c < 3; c++)
            buf[hdr.length + (y * 320 + x) * 3 + c] = px[((y + TOP) * W + LEFT + x * 2) * 4 + c];
        await writeFile(`${process.argv[2]}/tex-plane1-${frame}.ppm`, buf);
    }
}

// the chain moves: consecutive frames place different sprite layers
const a = layers.get(60).want, b = layers.get(61).want;
if (a.every((v, i) => v === b[i])) errors.push("frames 60 and 61 carry the same sprite layer: the sprites do not move");
if (!leftClip) errors.push("no sampled frame puts a sprite past the left edge: the clip goes unchecked");

// timing: the cart's update+render per frame, which has to leave 60 fps headroom
const perFrame = cartMs / frame;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);

if (errors.length) {
    console.error(`tex: sprites WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
const px = [...layers.values()].reduce((n, l) => n + l.checked, 0);
console.log(`tex: 11 sprites on the screen.js chain at frames ${FRAMES.join(",")} (${px} px, ${leftClip} left-edge crossings), ${perFrame.toFixed(3)} ms/frame`);
