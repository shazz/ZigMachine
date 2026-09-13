// Headless Union Demo menu driver: boots the sealed machine + demo-union_demo.wasm
// the way docs/sealed-loader.js does, walks Charly through a scripted timeline and
// dumps the visible 320x200 screen as PPMs, plus the frame cost. Then it CHECKS:
//
//   wrap   teleport to the last door (key 0), walk right with F1 and fire held:
//          the view keeps scrolling past the street's end and the hidden door at
//          x 2208 (union_textracker) is entered on the far side of the seam.
//   stop   a key held like a browser auto-repeats it (press, 500 ms, then every
//          33 ms), released anywhere from 550 to 1500 ms, on a 60 Hz and on a
//          144 Hz display: the street always stops moving within STOP_MS (the
//          60 ms input window + the original's 9-step friction tail + a frame).
//   keyup  with the host's key-up (demo.inputRelease), a 100 ms tap stops as fast.
//   door   the hub -> door swap in the page's order (disk, ROM unpack, instantiate,
//          romReset, hwInit, boot, skipBoot) shows the TEX loader panel.
//
// The timeline is the one the ORIGINAL remake was traced with in Chrome (one
// requestAnimationFrame per step), so shot N here is comparable to reference
// frame N: the reference had run 3 frames before its frame 0, so we pre-roll 3,
// after the menu's graphics depack behind menuloader.js's TEX panel.
// A held range sends an event every frame and stops HOLD_TAIL frames early: the
// scene keeps a repeating direction held for 60 ms after its last event.
//
//   node apps/union_demo_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const PREROLL = 3;
const HOLD_TAIL = 3; // frames held after the last event: 3 x 16.6 ms < 60 ms
const DT = 16.6;
const TEX_INK = [0xc0, 0xa0, 0x00]; // the TEX loader panel's ink
const DIR = { up: 0, down: 1, left: 2, right: 3, fire: 5 };
const K_F1 = 0xe001;
const STREET = [116, 159]; // screen rows of pavement: only Charly and the view change them
const STOP_MS = 250; // 60 ms window + 9 x 16.7 ms of friction (0.5 a step from 5 px) + a frame
const TIMELINE = {
    frames: 900,
    hold: [["right", 60, 130], ["up", 150, 200], ["fire", 230, 231], ["right", 260, 700], ["down", 720, 760], ["left", 780, 860]],
    shots: { 1: "start", 100: "walking", 210: "at-door", 231: "door-entered", 400: "scrolled", 600: "scroller", 760: "down", 850: "walking-left" },
};
const outDir = process.argv[2] || "/tmp/union_demo";
const CART = process.argv[3] || "docs/demo-union_demo.wasm";

async function boot(loaded = true) {
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
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    const m = { memory, machine, rom, env, demo: null, cost: { frame: [], render: [] } };
    // demo.hblDispatch must reach the CURRENT cart after a swap
    Object.defineProperty(m, "demo", { get: () => demo, set: (d) => { demo = d; } });
    await load(m, await readFile(CART), false);
    if (loaded) await ready(m);
    return m;
}

// The hub's graphics depack behind menuloader.js's TEX panel on EVERY start, a
// return from a screen included; its first street step runs on the frame the
// depack ends, which is also when it asks for its music. Returns the frame count.
async function ready(m, onFrame = () => {}) {
    for (let f = 1; f <= 400; f++) {
        step(m);
        await onFrame(f);
        if (m.demo.pollSongRequest()) return f;
    }
    throw new Error("the hub never finished loading");
}

// instantiateCart + the swap's hwInit/boot/skipBoot, with any import this cart
// needs that the harness does not provide stubbed (the loader's tolerantEnv).
async function load(m, bytes, packed) {
    if (packed) {
        const src = m.machine.hwRomRamBase() + m.machine.hwRomRamUsed();
        new Uint8Array(m.memory.buffer, src, bytes.length).set(bytes);
        const n = m.rom.romDepack(src, bytes.length, m.machine.hwRamBase(), m.machine.hwRamSize());
        bytes = new Uint8Array(m.memory.buffer.slice(m.machine.hwRamBase(), m.machine.hwRamBase() + n));
    }
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
        if (imp.module === "env" && !(imp.name in m.env)) m.env[imp.name] = () => 0;
    m.demo = (await WebAssembly.instantiate(bytes, { env: m.env })).instance.exports;
    m.machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    m.rom.romReset();
    m.machine.hwInit();
    m.demo.boot();
    m.demo.skipBoot();
}

function step(m, dt = DT) {
    m.machine.hwClear();
    let t = performance.now();
    m.demo.frame(dt);
    m.cost.frame.push(performance.now() - t);
    t = performance.now();
    for (let p = 0; p < m.machine.hwPlanesNumber(); p++) if (m.demo.isPlaneEnabled(p)) m.machine.hwRenderPlane(p);
    m.cost.render.push(performance.now() - t);
}

// The visible window of the physical frame, (80, 40) with x doubled, as RGB.
function visible(m, rows = [0, 200]) {
    const w = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), w * m.machine.hwPhysHeight() * 4);
    const out = new Uint8Array(320 * (rows[1] - rows[0]) * 3);
    for (let y = rows[0]; y < rows[1]; y++)
        for (let x = 0; x < 320; x++) {
            const s = ((40 + y) * w + 80 + 2 * x) * 4, d = ((y - rows[0]) * 320 + x) * 3;
            out[d] = pfb[s]; out[d + 1] = pfb[s + 1]; out[d + 2] = pfb[s + 2];
        }
    return out;
}
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const tag = (m) => new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.demo.getCartTagPtr(), m.demo.getCartTagLen()));

async function timeline() {
    await mkdir(outDir, { recursive: true });
    const m = await boot(false);
    // The traced timeline starts with the street. The frame the depack ends is the
    // street's first update, so it counts as one pre-roll frame.
    let midInk = 0;
    const loadFrames = await ready(m, async (f) => {
        if (f !== 50) return;
        const px = visible(m);
        for (let i = 0; i < px.length; i += 3) if (px[i] === TEX_INK[0] && px[i + 1] === TEX_INK[1] && px[i + 2] === TEX_INK[2]) midInk++;
        await writeFile(`${outDir}/loader-0050.ppm`, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), px]));
    });
    if (midInk < 500) throw new Error(`mid-load the TEX loader panel shows ${midInk} ink px`);
    console.log(`menu loader: ${loadFrames} frames behind menuloader.js's TEX panel (${midInk} ink px at frame 50)`);
    for (let i = 1; i < PREROLL; i++) step(m);
    for (let f = 0; f < TIMELINE.frames; f++) {
        for (const [key, from, to] of TIMELINE.hold) {
            const last = key === "fire" ? from : to - HOLD_TAIL;
            if (f >= from && f <= last) m.demo.input(DIR[key]);
        }
        step(m);
        const name = TIMELINE.shots[f];
        if (!name) continue;
        const path = `${outDir}/${String(f).padStart(4, "0")}-${name}.ppm`;
        await writeFile(path, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), visible(m)]));
        console.log(`  shot: ${path}`);
    }
    return m.cost;
}

// wrap: from the last door, right + F1 + fire, until a door asks for a cart.
async function checkWrap() {
    const m = await boot();
    step(m);
    m.demo.key("0".charCodeAt(0)); step(m); // teleport to x 5436
    m.demo.key(K_F1); step(m);
    let prev = visible(m, STREET), still = 0, f = 0;
    for (; f < 600; f++) {
        m.demo.input(DIR.right); m.demo.input(DIR.fire);
        step(m);
        const street = visible(m, STREET);
        still = same(street, prev) ? still + 1 : 0;
        prev = street;
        if (still > 30) return `FAIL wrap: walking right, the street has not scrolled for 30 frames (frame ${f}): the view is held at the map's end`;
        if (m.demo.pollCartRequest() === 1) break;
    }
    const t = f < 600 ? tag(m) : "(none)";
    return t === "union_textracker" ? `ok   wrap: past the end, the hidden door was entered after ${f} frames`
        : `FAIL wrap: expected the union_textracker door beyond the seam, got ${t}`;
}

// A key the browser way: a press at 0, repeats from 500 ms every 33.3 ms while
// held, released at `upMs` (and reported with inputRelease when `keyup`), on a
// `hz` display. Returns how many ms after the release the street last moved.
async function stopAfter(upMs, keyup, hz) {
    const m = await boot();
    for (let i = 0; i < PREROLL; i++) step(m);
    const events = [0];
    for (let k = 0; 500 + (k * 1000) / 30 < upMs; k++) events.push(500 + (k * 1000) / 30);
    const frameMs = 1000 / hz, total = Math.ceil((upMs + 1000) / frameMs);
    let next = 0, released = false, prev = visible(m, STREET), last = -1;
    for (let f = 0; f < total; f++) {
        const now = f * frameMs;
        while (next < events.length && events[next] <= now) { m.demo.input(DIR.right); next++; }
        if (keyup && !released && upMs <= now) { m.demo.inputRelease(DIR.right); released = true; }
        step(m, frameMs);
        const street = visible(m, STREET);
        if (!same(street, prev)) last = now;
        prev = street;
    }
    return Math.round(last - upMs);
}

async function checkStop(hz) {
    let worst = -Infinity, at = 0;
    for (let up = 550; up <= 1500; up += 25) {
        const after = await stopAfter(up, false, hz);
        if (after > worst) { worst = after; at = up; }
    }
    return worst <= STOP_MS ? `ok   stop ${hz} Hz: releases 550..1500 ms, the street stops at worst ${worst} ms later`
        : `FAIL stop ${hz} Hz: released at ${at} ms, the street kept moving ${worst} ms (limit ${STOP_MS})`;
}

async function checkKeyup() {
    const probe = await boot();
    if (!probe.demo.inputRelease) return "FAIL keyup: the cart has no inputRelease export";
    const after = await stopAfter(100, true, 60);
    return after <= STOP_MS ? `ok   keyup: a 100 ms tap released by key-up stops ${after} ms later`
        : `FAIL keyup: a 100 ms tap released by key-up kept moving ${after} ms (limit ${STOP_MS})`;
}

// The hub's door request followed through the shelf's disks, page order.
async function checkDoor() {
    const m = await boot();
    m.demo.key("h".charCodeAt(0)); step(m); // in front of the hidden door
    m.demo.input(DIR.fire); step(m);
    if (m.demo.pollCartRequest() !== 1) return "FAIL door: fire in front of the hidden door asked for nothing";
    const disk = new Uint8Array(await readFile(`docs/demo-${tag(m)}.zmd`));
    const dv = new DataView(disk.buffer, disk.byteOffset);
    const start = dv.getUint32(0x0e, true) * dv.getUint16(0x08, true);
    await load(m, disk.slice(start, start + dv.getUint32(0x12, true)), true);
    let ink = 0;
    for (let f = 0; f < 60; f++) {
        step(m);
        const px = visible(m);
        for (let i = 0; i < px.length; i += 3) if (px[i] === 0xc0 && px[i + 1] === 0xa0 && px[i + 2] === 0) { ink++; break; }
    }
    return ink >= 50 ? `ok   door: the TEX loader panel shows on ${ink} of the first 60 frames after the swap`
        : `FAIL door: the TEX loader panel shows on only ${ink} of the first 60 frames after the swap`;
}

const cost = await timeline();
const results = [await checkWrap(), await checkStop(60), await checkStop(144), await checkKeyup(), await checkDoor()];
for (const r of results) console.log(r);

const stats = (a) => {
    const s = [...a].sort((x, y) => x - y);
    return `mean ${(a.reduce((x, y) => x + y, 0) / a.length).toFixed(3)} ms, p99 ${s[Math.floor(s.length * 0.99)].toFixed(3)} ms, max ${s[s.length - 1].toFixed(3)} ms`;
};
console.log(`frames: ${cost.frame.length}`);
console.log(`  cart update+render: ${stats(cost.frame)}`);
console.log(`  hwRenderPlane     : ${stats(cost.render)}`);
const worst = Math.max(...cost.frame.map((v, i) => v + cost.render[i]));
console.log(worst < 16.7 ? `=> PASS within the 60 fps budget (worst ${worst.toFixed(3)} ms of 16.7)` : `=> OVER budget: worst ${worst.toFixed(3)} ms`);
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(failed ? `=> ${failed} check(s) FAILED` : "=> all checks pass");
process.exit(failed || worst >= 16.7 ? 1 : 0);
