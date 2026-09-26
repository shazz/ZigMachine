// Headless REPLICANTS GARFIELD driver: boots the sealed machine + the cart the way
// sealed-loader.js does, runs N frames and writes the composited visible screen.
//
// hwRenderPlane(p) OVERWRITES the shared physical framebuffer, so each plane is
// snapshotted right after it renders and the snapshots are alpha-blended here,
// bottom plane first. The scene now uses only plane 0 (PLANES = 1); the blend
// stays so the harness still works if a plane is ever added back.
//
//   node apps/replicants_garfield_headless.mjs [--break noclear] [outdir]
//
// Frames run in the host's order (hwClear, frame, render), because hwClear is
// where the global HBL paints the border. Checked on the whole 800x280 physical
// frame: every visible line's border is colour 0 on that line (the colour at the
// window's left edge, which is always index 0 there), the three red tubes run
// edge to edge, the moving bars reach the border, and the top and bottom borders
// stay black. --break noclear skips hwClear: the border is never painted, and
// the checks must fail.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1; // the scene draws everything into plane 0

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
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const args = process.argv.slice(2);
const BREAK = args[0] === "--break" ? args[1] : null;
if (BREAK && BREAK !== "noclear") throw new Error(`unknown --break ${BREAK}`);
const out = (BREAK ? args[2] : args[0]) || "/tmp/replicants_garfield";
await mkdir(out, { recursive: true });

const { memory, machine, demo } = await boot("docs/demo-replicants_garfield.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
const X0 = 80, Y0 = 40, VW = 640, VH = 200; // the window in the 800x280 raster
let frames = 0;

// one host frame: hwClear (global HBL -> border), the cart, its plane
function step() {
    if (BREAK !== "noclear") machine.hwClear();
    demo.frame(1000 / 60);
    machine.hwRenderPlane(0);
    frames++;
}

const px = (x, y) => { const b = pfb(), i = (y * W + x) * 4; return (b[i] << 16) | (b[i + 1] << 8) | b[i + 2]; };
const hex = (c) => "#" + c.toString(16).padStart(6, "0");
const RED = new Set([0x400000, 0x600000, 0x800000, 0xa00000, 0xc00000, 0xe00000]);
const TUBES = [[0, 11], [147, 158], [192, 200]]; // visible lines, end exclusive
const onTube = (y) => TUBES.some(([a, b]) => y >= a && y < b);
const errors = [];
let barsInBorder = 0, checkedLines = 0;

function checkFrame() {
    for (let y = 0; y < H; y++) {
        const left = px(0, y), right = px(W - 1, y);
        if (left !== right) errors.push(`frame ${frames} row ${y}: left border ${hex(left)} != right ${hex(right)}`);
        const vy = y - Y0;
        if (vy < 0 || vy >= VH) {
            if (left !== 0) errors.push(`frame ${frames} row ${y}: top/bottom border ${hex(left)}, want black`);
            continue;
        }
        const edge = px(X0, y); // window x 0: index 0 on every tube and bar line
        if (onTube(vy)) {
            checkedLines++;
            if (!RED.has(edge)) errors.push(`frame ${frames} line ${vy}: tube colour ${hex(edge)} is not an ST red`);
            if (left !== edge) errors.push(`frame ${frames} line ${vy}: tube stops at the window: border ${hex(left)}, window ${hex(edge)}`);
        } else if (vy >= 30 && vy < 147) {
            checkedLines++;
            if (left !== edge) errors.push(`frame ${frames} line ${vy}: bar stops at the window: border ${hex(left)}, window ${hex(edge)}`);
            if (left !== 0) barsInBorder++;
        }
    }
}

const shots = new Set([1, 61, 151, 301]);
for (let f = 1; f <= 600; f++) {
    step();
    if (f % 7 === 0 || shots.has(f)) checkFrame();
    if (shots.has(f)) await shot(`${out}/${String(f).padStart(3, "0")}.ppm`);
}

async function shot(path) {
    // the whole physical frame, borders included, halved to 400x280
    const hdr = new TextEncoder().encode(`P6\n${W / 2} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + (W / 2) * H * 3);
    buf.set(hdr);
    const b = pfb();
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W / 2; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * (W / 2) + x) * 3 + c] = b[(y * W + x * 2) * 4 + c];
    await writeFile(path, buf);
}

if (barsInBorder === 0) errors.push("no moving bar ever reached the border");
const N = 600;
let t = performance.now();
for (let i = 0; i < N; i++) step();
const cost = (performance.now() - t) / N;

const unique = [...new Set(errors)];
if (BREAK) {
    if (unique.length === 0) { console.log(`replicants_garfield: FAIL, --break ${BREAK} was NOT caught`); process.exit(1); }
    console.log(`replicants_garfield: PASS (--break ${BREAK} caught: ${unique.length} errors, first: ${unique[0]})`);
    process.exit(0);
}
if (unique.length) {
    console.log(`replicants_garfield: WRONG`);
    for (const e of unique.slice(0, 12)) console.log("  " + e);
    process.exit(1);
}
console.log(`replicants_garfield: ${checkedLines} raster lines checked edge to edge over ${frames - N} frames: the three red tubes (ST reds) and the moving bars reach both borders, which follow colour 0 line by line; top and bottom borders black; bars in the border on ${barsInBorder} lines; ${cost.toFixed(3)} ms/frame (clear + cart + plane); shots in ${out}`);
