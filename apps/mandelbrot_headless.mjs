// Headless MANDELBROT driver: boots the sealed machine + demo-mandelbrot the way
// docs/sealed-loader.js does and proves, on the composited picture:
//   1. the f32 default draws a real fractal (many grey levels, a white interior
//      that is neither nothing nor everything) top to bottom, 4 rows a frame;
//   2. F switches the escape loop to Q5.27 integers LIVE: the picture restarts
//      its draw-in, ends up a rounding-edge away from the f32 one (reported as
//      pixel counts), and is still a fractal;
//   3. F twice is the f32 picture again, byte for byte, frame by frame when
//      pressed before the first frame and after a full redraw when pressed late.
//
//   node apps/mandelbrot_headless.mjs [--break fkey]
// --break fkey never presses F: the "F switches the path" checks must then fail.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const K_F = 0x66;
const DONE = 80; // 280 rows / 4 per frame = 70 frames, with margin
const argv = process.argv.slice(2);
const breakF = argv.includes("--break") && argv[argv.indexOf("--break") + 1] === "fkey";

async function boot() {
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
    const cartBytes = await readFile("docs/demo-mandelbrot.wasm");
    const env = {
        memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
        hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree, hwRamAlloc: machine.hwRamAlloc,
        hwRamMark: machine.hwRamMark, hwRamRelease: machine.hwRamRelease,
        hwRamAllocFailures: machine.hwRamAllocFailures,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree, ...rom,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), machine.hwPhysWidth() * machine.hwPhysHeight() * 4);
    return {
        demo, machine,
        // one host frame; returns a copy of the composited picture
        frame(keys = []) {
            for (const k of keys) demo.key(k);
            machine.hwClear();
            demo.frame(16.6);
            machine.hwRenderPlane(0);
            return pfb.slice();
        },
    };
}

// Run n frames, pressing keys[f] before frame f; return the pictures by frame.
async function play(keys, n) {
    const m = await boot();
    const shots = [];
    for (let f = 1; f <= n; f++) shots[f] = m.frame(keys[f] ?? []);
    return shots;
}
const same = (a, b) => Buffer.compare(a, b) === 0;
const diffPx = (a, b) => { let n = 0; for (let i = 0; i < a.length; i += 4) if (a[i] !== b[i]) n++; return n; };
function stats(img) {
    const levels = new Set();
    let lit = 0, white = 0, total = 0;
    for (let i = 0; i < img.length; i += 4) {
        if (img[i + 3] === 0) continue; // transparent: not drawn
        total++; levels.add(img[i]);
        if (img[i] > 0) lit++;
        if (img[i] === 255) white++;
    }
    return { levels: levels.size, lit, white, total };
}
const fail = (m) => { throw new Error(`mandelbrot: ${m}`); };
const F = breakF ? [] : [K_F];

async function checks() {
    var base = await play({}, 200);
    const s = stats(base[DONE]);
    console.log(`  f32 at frame ${DONE}: ${s.levels} grey levels, ${s.white} white (interior) of ${s.total} px`);
    if (s.levels < 40 || s.white < s.total * 0.02 || s.white > s.total * 0.5) fail("the f32 picture is not a fractal");
    const half = stats(base[35]);
    if (!(half.lit > 0 && half.lit < s.lit * 0.7)) fail("the picture does not draw in top to bottom");
    if (!same(base[DONE], base[200])) fail("the finished picture keeps changing");

    // F pressed at frame 40, mid draw-in: the draw restarts with the integer loop.
    const fx = await play({ 40: F }, 200);
    if (same(fx[45], base[45])) fail("F did not switch the path: frame 45 is the f32 one (a restart was expected)");
    const sf = stats(fx[160]);
    const d = diffPx(fx[160], base[160]);
    console.log(`  Q5.27 vs f32, full image: ${d} of ${sf.total} px differ (${(100 * d / sf.total).toFixed(3)} %), ` +
        `${sf.levels} grey levels, ${sf.white} white`);
    if (sf.levels < 40 || sf.white < sf.total * 0.02) fail("the fixed-point picture is not a fractal");
    if (d === 0) fail("fixed and f32 are byte-identical: F changed nothing");
    if (d > sf.total * 0.02) fail("the fixed-point picture is not the f32 one (over 2 % of pixels differ)");

    // F twice: before the first frame it is the f32 cart frame by frame; late, after a redraw, the same picture.
    const tw = await play({ 1: [...F, ...F] }, 120);
    for (let f = 1; f <= 120; f += 7) if (!same(tw[f], base[f])) fail(`F twice before frame 1 differs at frame ${f}`);
    const late = await play({ 90: [...F, ...F] }, 180);
    if (!same(late[180], base[180])) fail("F twice after a full draw does not return to the f32 picture");
    const lateF = await play({ 90: F, 100: F }, 200);
    if (!same(lateF[200], base[200])) fail("F at 90 and again at 100 does not return to the f32 picture");
}
try {
    await checks();
} catch (e) {
    if (!breakF) throw e;
    console.log(`mandelbrot: PASS (--break fkey was caught: ${e.message})`);
    process.exit(0);
}
if (breakF) fail("--break fkey was NOT caught");
console.log("mandelbrot: PASS");
