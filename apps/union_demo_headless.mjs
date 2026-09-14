// Headless Union Demo menu driver: boots the sealed machine + demo-union_demo.wasm
// the way docs/sealed-loader.js does, walks Charly through a scripted timeline and
// dumps the visible 320x200 screen as PPMs, plus the frame cost.
//
// The timeline is the one the ORIGINAL remake was traced with in Chrome (one
// requestAnimationFrame per step), so shot N here is comparable to reference
// frame N: the reference had run 3 frames before its frame 0, so we pre-roll 3.
// The host only sends key-DOWN (auto-repeat); a held range is sent every frame
// and stops REPEAT_HOLD-1 frames early, because the scene keeps a direction
// held for REPEAT_HOLD frames after the last event (controls.zig).
//
//   node apps/union_demo_headless.mjs [outdir]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const PREROLL = 3;
const REPEAT_HOLD = 4;
const DIR = { up: 0, down: 1, left: 2, right: 3, fire: 5 };
const TIMELINE = {
    frames: 900,
    hold: [["right", 60, 130], ["up", 150, 200], ["fire", 230, 231], ["right", 260, 700], ["down", 720, 760], ["left", 780, 860]],
    shots: { 1: "start", 100: "walking", 210: "at-door", 231: "door-entered", 400: "scrolled", 600: "scroller", 760: "down", 850: "walking-left" },
};

async function boot(cartPath = "docs/demo-union_demo.wasm") {
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
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
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

// The visible window of the physical frame: (80, 40), x doubled.
async function shot(memory, machine, path) {
    const w = machine.hwPhysWidth();
    const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), w * machine.hwPhysHeight() * 4);
    const hdr = new TextEncoder().encode("P6\n320 200\n255\n");
    const out = new Uint8Array(hdr.length + 320 * 200 * 3);
    out.set(hdr);
    for (let y = 0; y < 200; y++) {
        for (let x = 0; x < 320; x++) {
            const s = ((40 + y) * w + 80 + 2 * x) * 4, d = hdr.length + (y * 320 + x) * 3;
            out[d] = pfb[s]; out[d + 1] = pfb[s + 1]; out[d + 2] = pfb[s + 2];
        }
    }
    await writeFile(path, out);
    console.log(`  shot: ${path}`);
}

const outDir = process.argv[2] || "/tmp/union_demo";
await mkdir(outDir, { recursive: true });
const { memory, machine, demo } = await boot();
const cost = { frame: [], render: [] };

function step() {
    machine.hwClear();
    let t = performance.now();
    demo.frame(16.6);
    cost.frame.push(performance.now() - t);
    t = performance.now();
    for (let p = 0; p < machine.hwPlanesNumber(); p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
    cost.render.push(performance.now() - t);
}

// The menu's graphics first depack behind menuloader.js's TEX panel (the remake's
// mainMenuLoader); the traced timeline starts with the street. The frame the
// depack ends is the street's first update, so it counts as one pre-roll frame.
const TEX_INK = [0xc0, 0xa0, 0x00];
function panelInk() {
    const w = machine.hwPhysWidth(), pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), w * machine.hwPhysHeight() * 4);
    let n = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const s = ((40 + y) * w + 80 + 2 * x) * 4;
        if (pfb[s] === TEX_INK[0] && pfb[s + 1] === TEX_INK[1] && pfb[s + 2] === TEX_INK[2]) n++;
    }
    return n;
}
let loadFrames = 0, midInk = 0;
for (;;) {
    step();
    loadFrames++;
    if (demo.pollSongRequest()) break;
    if (loadFrames === 50) { midInk = panelInk(); await shot(memory, machine, `${outDir}/loader-0050.ppm`); }
    if (loadFrames > 400) { console.log("=> FAIL the menu never finished loading"); process.exit(1); }
}
if (midInk < 500) { console.log(`=> FAIL mid-load the TEX loader panel shows ${midInk} ink px`); process.exit(1); }
console.log(`menu loader: ${loadFrames} frames behind menuloader.js's TEX panel (${midInk} ink px at frame 50)`);
for (let i = 1; i < PREROLL; i++) step();
for (let f = 0; f < TIMELINE.frames; f++) {
    for (const [key, from, to] of TIMELINE.hold) {
        const last = key === "fire" ? from : to - REPEAT_HOLD;
        if (f >= from && f <= last) demo.input(DIR[key]);
    }
    step();
    if (TIMELINE.shots[f]) await shot(memory, machine, `${outDir}/${String(f).padStart(4, "0")}-${TIMELINE.shots[f]}.ppm`);
}

const stats = (a) => {
    const s = [...a].sort((x, y) => x - y);
    return `mean ${(a.reduce((x, y) => x + y, 0) / a.length).toFixed(3)} ms, p99 ${s[Math.floor(s.length * 0.99)].toFixed(3)} ms, max ${s[s.length - 1].toFixed(3)} ms`;
};
console.log(`frames: ${cost.frame.length}`);
console.log(`  cart update+render: ${stats(cost.frame)}`);
console.log(`  hwRenderPlane     : ${stats(cost.render)}`);
const worst = Math.max(...cost.frame.map((v, i) => v + cost.render[i]));
console.log(worst < 16.7 ? `=> PASS within the 60 fps budget (worst ${worst.toFixed(3)} ms of 16.7)` : `=> OVER budget: worst ${worst.toFixed(3)} ms`);
