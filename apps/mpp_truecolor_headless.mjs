// Headless MPP TRUECOLOR check: per-line palettes really put more colours on
// screen than one palette can, for every picture in the gallery.
//
// For each picture (Fire, as Space sends it, steps to the next) and each mode
// (setShadeMode 0/1/2) it composites the enabled planes the way the host does
// (hwClear, frame, hwRenderPlane per enabled plane) and asserts:
//   - every mode shows exactly the distinct colours its caption claims (p<P>_counts.bin),
//   - PER-LINE shows more than GLOBAL, and 4 PLANES at least as many as PER-LINE,
//   - 4 PLANES is lossless: the picture's RGB hashes to the source's (FNV-1a in counts),
//   - after the last picture, Fire wraps to picture 0 and the frame (caption included)
//     is byte-identical to the first pass, in two modes: the depack buffer is not stale.
// A handler that missed lines, a plane split that left a pixel opaque in two planes
// or in none, or a palette decoded wrong changes a count or a hash; nothing would error.
// Each switch depacks one packed blob; the slowest switch is reported.
//
//   node apps/mpp_truecolor_headless.mjs [outdir] [cart.wasm]
//   (outdir: writes mpp-<picture>-mode<N>.ppm, the picture area at 320x180)
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // first visible physical row / column (low res is doubled)
const IMG_W = 320, IMG_H = 180; // the picture; the caption band is below it
const WARMUP = 30, FRAMES = 60; // per mode: untimed, then timed, then the shot
const ASSETS = "apps/zig/assets/screens/mpp_truecolor";

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
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// One host-loop frame (docs/sealed-loader.js): each enabled plane is rendered
// into the PFB and copied to ITS OWN canvas; the page stacks those canvases, so
// palette alpha 0 shows the planes below. `layer` (when given) replays that
// stacking: plane pixels with alpha != 0 cover what is under them. Returns the
// ms spent in frame + plane rendering (the copies excluded).
function hostFrame(memory, machine, demo, layer) {
    const size = machine.hwPhysWidth() * machine.hwPhysHeight() * 4;
    const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), size);
    let ms = 0, t = performance.now();
    machine.hwClear();
    demo.frame(1000 / 60);
    ms += performance.now() - t;
    layer?.set(pfb()); // the background under every plane
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        t = performance.now();
        machine.hwRenderPlane(p);
        ms += performance.now() - t;
        if (!layer) continue;
        const px = pfb();
        for (let i = 0; i < size; i += 4) if (px[i + 3] !== 0) layer.set(px.subarray(i, i + 4), i);
    }
    return ms;
}

// The picture area of the stacked planes, one RGB sample per logical pixel.
function picture(layer, W) {
    const rgb = new Uint8Array(IMG_W * IMG_H * 3);
    for (let y = 0; y < IMG_H; y++)
        for (let x = 0; x < IMG_W; x++) {
            const i = ((TOP + y) * W + LEFT + x * 2) * 4, o = (y * IMG_W + x) * 3;
            rgb[o] = layer[i]; rgb[o + 1] = layer[i + 1]; rgb[o + 2] = layer[i + 2];
        }
    return rgb;
}

function distinct(rgb) {
    const seen = new Set();
    for (let i = 0; i < rgb.length; i += 3) seen.add((rgb[i] << 16) | (rgb[i + 1] << 8) | rgb[i + 2]);
    return seen.size;
}

function fnv1a(bytes) {
    let h = 0x811c9dc5;
    for (const b of bytes) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h;
}

const [outdir, cart = "docs/demo-mpp_truecolor.wasm"] = process.argv.slice(2);
const { memory, machine, demo } = await boot(cart);
const NAMES = ["GLOBAL", "PER-LINE", "4 PLANES"];
const PICTURES = ["spheres", "parrot", "sunset", "halo", "hills"]; // the scene's order; Fire steps to the next
const FIRE = 5; // demo_main Direction.Fire, what the host sends for Space
const W = machine.hwPhysWidth();
const layer = new Uint8Array(W * machine.hwPhysHeight() * 4);
const errors = [];
const firstPass = []; // picture 0's whole-frame hash per mode
let slowest = 0;

// A switch (Fire or a mode key) depacks one blob; time it, then shoot the frame.
function shoot(action) {
    const t = performance.now();
    action();
    slowest = Math.max(slowest, performance.now() - t);
    for (let f = 0; f < WARMUP; f++) hostFrame(memory, machine, demo, null); // JIT warm-up
    let ms = 0;
    for (let f = 0; f < FRAMES; f++) ms += hostFrame(memory, machine, demo, null);
    hostFrame(memory, machine, demo, layer);
    return ms / FRAMES;
}

for (let p = 0; p < PICTURES.length; p++) {
    const name = PICTURES[p];
    const counts = new Uint32Array((await readFile(`${ASSETS}/p${p}_counts.bin`)).buffer.slice(0, 20));
    const measured = [];
    let frameMs = 0;
    if (p > 0) shoot(() => demo.input(FIRE)); // keeps the mode (4 PLANES); timed like any switch
    for (let m = 0; m < 3; m++) {
        frameMs = Math.max(frameMs, shoot(() => demo.setShadeMode(m)));
        const rgb = picture(layer, W);
        measured.push(distinct(rgb));
        if (p === 0) firstPass.push(fnv1a(layer));
        if (measured[m] !== counts[m + 1]) errors.push(`${name} ${NAMES[m]}: ${measured[m]} colours on screen, caption claims ${counts[m + 1]}`);
        if (m === 2 && fnv1a(rgb) !== counts[4]) errors.push(`${name} 4 PLANES: not the source picture (hash mismatch)`);
        if (outdir) {
            const hdr = new TextEncoder().encode(`P6\n${IMG_W} ${IMG_H}\n255\n`);
            await writeFile(`${outdir}/mpp-${name}-mode${m + 1}.ppm`, Buffer.concat([hdr, rgb]));
        }
    }
    if (measured[1] <= measured[0]) errors.push(`${name}: PER-LINE ${measured[1]} not above GLOBAL ${measured[0]}`);
    if (measured[2] < measured[1]) errors.push(`${name}: 4 PLANES ${measured[2]} below PER-LINE ${measured[1]}`);
    console.log(`mpp_truecolor: ${name.padEnd(7)} ${measured.join(" / ")} colours (source ${counts[0]}), ${frameMs.toFixed(2)} ms/frame max`);
}

// Wrap: Fire from the last picture lands on picture 0 in 4 PLANES (the mode stays),
// then GLOBAL; both frames must match the first pass byte for byte.
shoot(() => demo.input(FIRE));
if (fnv1a(layer) !== firstPass[2]) errors.push("wrap to spheres: 4 PLANES frame differs from the first pass");
shoot(() => demo.setShadeMode(0));
if (fnv1a(layer) !== firstPass[0]) errors.push("wrap to spheres: GLOBAL frame differs from the first pass");
console.log(`mpp_truecolor: ${PICTURES.length} pictures, 4 PLANES lossless, wrap identical; slowest switch (depack) ${slowest.toFixed(1)} ms`);
if (errors.length) {
    console.error(`mpp_truecolor: FAILED\n  ${errors.join("\n  ")}`);
    process.exit(1);
}
