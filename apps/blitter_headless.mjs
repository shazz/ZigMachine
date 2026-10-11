// Headless BLITTER DEMO driver: boots the sealed machine + demo-blitter.wasm
// TWICE, the way docs/sealed-loader.js does, presses B on the second one, and
// proves key B's promise -- the CPU draws exactly what the blitter draws:
//
//  1. every effect (1-7) gives the same plane-0 indices and palette on both,
//     frame after frame, outside the corner label;
//  2. the label says BLITTER on the first, CPU on the second;
//  3. the CPU one issues NO hwBlit() at all, the blitter one some every frame
//     (RUBBER's merged runs: well under its old 200 a frame);
//  4. B again goes back to the blitter (whole frame equal, label included),
//     and Escape asks for the menu.
//
//   node apps/blitter_headless.mjs [outdir] [--break pixel|nokey]
//     --break pixel   the CPU frame gets one pixel wrong: must be caught
//     --break nokey   B is never pressed: must be caught
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk
const OFF_PAL = 0x0100, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44; // memmap.zig
const W = 320, H = 200, FRAMES = 30, TEXT_COL = 202; // effects.zig
const LABEL = { x0: 254, x1: 310, y0: 184, y1: 192 }; // blitter_demo.zig: 8x8 text, right edge at 310
const CPU_X0 = 286; // "CPU" starts here; "BLITTER" 32 px further left
const NAMES = ["FLAT", "LIT", "HALFTONE", "GLENZ", "RUBBER", "TILE", "DELAY"];
const K_ESC = 0xE012;

const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
const failures = [];
function check(name, ok, detail = "") {
    if (!ok) failures.push(name);
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const blits = { n: 0 };
    const hwBlit = () => { blits.n++; machine.hwBlit(); };
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    env.hwBlit = hwBlit;
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const VB = machine.hwVideoBase();
    const regs = new DataView(memory.buffer, VB, OFF_PAL);
    const plane = () => new Uint8Array(memory.buffer, VB + regs.getUint32(REG_FB_BASE, true), W * H);
    const palette = () => new Uint32Array(memory.buffer, VB + OFF_PAL, 256);
    // One frame; the hwBlit() calls it made.
    const frame = () => { blits.n = 0; demo.frame(16.6); return blits.n; };
    return { demo, plane, palette, frame, stride: regs.getUint16(REG_FB_STRIDE, true) };
}

const inLabel = (x, y) => x >= LABEL.x0 && x < LABEL.x1 && y >= LABEL.y0 && y < LABEL.y1;
function diff(a, b, skipLabel) {
    let n = 0, first = "";
    for (let i = 0; i < W * H; i++) {
        if (a[i] === b[i]) continue;
        const x = i % W, y = (i / W) | 0;
        if (skipLabel && inLabel(x, y)) continue;
        if (!n++) first = ` first at (${x},${y}) ${a[i]} vs ${b[i]}`;
    }
    return { n, first };
}
// Label ink: [pixels left of CPU_X0, pixels from CPU_X0 on].
function labelInk(p) {
    let left = 0, right = 0;
    for (let y = LABEL.y0; y < LABEL.y1; y++)
        for (let x = LABEL.x0; x < LABEL.x1; x++) if (p[y * W + x] === TEXT_COL) x < CPU_X0 ? left++ : right++;
    return [left, right];
}
async function ppm(path, p, pal) {
    const hdr = new TextEncoder().encode(`P6\n${W} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + W * H * 3);
    buf.set(hdr);
    for (let i = 0; i < W * H; i++) {
        const c = pal[p[i]];
        buf.set([c & 255, (c >>> 8) & 255, (c >>> 16) & 255], hdr.length + i * 3);
    }
    await writeFile(path, buf);
}

const out = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/blitter_headless";
await mkdir(out, { recursive: true });
const hw = await boot("docs/demo-blitter.wasm");
const cpu = await boot("docs/demo-blitter.wasm");
check("plane 0 is a 320-wide window", hw.stride === W, `stride ${hw.stride}`);
if (broke !== "nokey") cpu.demo.key("b".charCodeAt(0));

hw.frame(), cpu.frame();
const [hl, hr] = labelInk(hw.plane()), [cl, cr] = labelInk(cpu.plane());
check("the blitter one says BLITTER (ink left of the CPU word too)", hl > 0 && hr > 0, `${hl}+${hr} px`);
check("B: the CPU one says CPU (ink only where CPU sits)", cl === 0 && cr > 0, `${cl}+${cr} px`);
check("... and the two labels differ", hr !== cr || hl !== cl);

for (let m = 0; m < NAMES.length; m++) {
    hw.demo.setShadeMode(m), cpu.demo.setShadeMode(m);
    let bad = 0, palBad = 0, first = "", hwMin = Infinity, hwMax = 0, cpuMax = 0;
    for (let f = 0; f < FRAMES; f++) {
        const nh = hw.frame(), nc = cpu.frame();
        hwMin = Math.min(hwMin, nh), hwMax = Math.max(hwMax, nh), cpuMax = Math.max(cpuMax, nc);
        if (broke === "pixel" && m === 4 && f === 5) cpu.plane()[100 * W + 160] ^= 1;
        const d = diff(hw.plane(), cpu.plane(), true);
        if (d.n && !bad) first = `frame ${f}: ${d.n} px,${d.first}`;
        bad += d.n > 0;
        palBad += hw.palette().some((c, i) => c !== cpu.palette()[i]);
    }
    await ppm(`${out}/${m + 1}-${NAMES[m].toLowerCase()}-cpu.ppm`, cpu.plane(), cpu.palette());
    check(`${NAMES[m]}: CPU frames equal the blitter's`, bad === 0, bad ? `${bad}/${FRAMES} differ, ${first}` : `${FRAMES} frames`);
    check(`${NAMES[m]}: palettes equal`, palBad === 0);
    check(`${NAMES[m]}: CPU mode issues no hwBlit()`, cpuMax === 0, `max ${cpuMax} a frame`);
    check(`${NAMES[m]}: blitter mode blits every frame`, hwMin > 0, `${hwMin}..${hwMax} a frame`);
    if (m === 4) check("RUBBER: the merged runs stay well under 200 row blits", hwMax < 120, `max ${hwMax}`);
}

cpu.demo.key("B".charCodeAt(0)); // capital B toggles too
const back = cpu.frame();
hw.frame();
check("B again: back on the blitter", back > 0, `${back} blits`);
check("... the whole frame equal, label included", diff(hw.plane(), cpu.plane(), false).n === 0);
check("no menu request before Escape", cpu.demo.pollCartRequest() === 0);
cpu.demo.key(K_ESC);
check("Escape asks for the menu", cpu.demo.pollCartRequest() === -1);

if (broke) {
    const want = broke === "pixel" ? "RUBBER: CPU frames equal the blitter's" : "B: the CPU one says CPU (ink only where CPU sits)";
    const hit = failures.includes(want);
    console.log(hit ? `blitter: PASS (--break ${broke} caught: ${want})` : `blitter: FAILED -- --break ${broke} was not caught`);
    process.exit(hit ? 0 : 1);
}
console.log(failures.length ? `blitter: FAILED -- ${failures.join("; ")}` : "blitter: all pass");
process.exit(failures.length ? 1 : 0);
