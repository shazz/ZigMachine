// Headless ANIMA driver (cart 107): boots the sealed machine + demo-anima.wasm the way
// docs/sealed-loader.js does (hwClear, frame, hwRenderPlane per enabled plane, every
// frame: the HBL runs inside hwRenderPlane, so the raster and the borders are live) and
// checks what the screen is about:
//   1. music: breath_2000.sndh requested at start
//   2. borders: closed in DARK (the border columns show the machine background), sides
//      opening from the middle line out during OPEN, every line open once the screen runs
//   3. REAL raster: entry 0 changes per line; wherever the plane holds index 0, the
//      composed pixel IS that line's raster colour, in BOTH side borders too (x 0 and 799)
//   4. frames pinned by SHA-256 of the composed 800x280 picture at points in every phase
//   5. CHISEL ops per frame under a ceiling (each hwBlit costs ~1,000 cycles on the board)
//   6. est. board cost (apps/frame_cost.mjs) under CEILING_MC in every phase
//   node apps/anima_headless.mjs [outdir] [--pin] [--no-cost] [--break hash|border|raster|music|cost]
// --pin prints the hashes to paste into PINS. --break plants one fault and PASSES only if caught.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = "docs/demo-anima.wasm";
const PAGES = 112;
const CEILING_MC = 1.75; // the board knee: above it the frame drops below 60 fps (lead, 2026-10-23)
const MAX_BLITS = 200;
const BREAKS = ["hash", "border", "raster", "music", "cost"];
const argv = process.argv.slice(2);
const bi = argv.indexOf("--break");
const broke = bi >= 0 ? argv[bi + 1] : null;
if (bi >= 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const PIN = argv.includes("--pin");
const NO_COST = argv.includes("--no-cost");
const out = argv.find((a, i) => !a.startsWith("--") && argv[i - 1] !== "--break") ?? "/tmp/anima";

// frame -> sha256 of the composed picture (DARK, OPEN, BREATHE, SCROLL, four GLENZ objects)
const PINS = {
    60: "2ffcc7dae0b41e2cfd6d545cfaadb1ac73019dbbece3491845294ce2bfc7896c",
    170: "9d50fdc7a502806abdc5711004b6090b849874696be74f2c23c734c06ae1266b",
    330: "ee448db17f829187c73577f669147127cd3894c038a0cd32a2eb4e776efa19c3",
    700: "1c2f26edf1e254cfff6d61bc5c457297cbb6fc013dead7faba682e5dd0544be5",
    1400: "e6ccdee070a3e5569cfae2ed5907acdb3afa81c7f59215593060636f086c8bd4",
    2100: "3a450d3df2c1bfcaa57a546d220286d007734a195949455003f4ba7bee70de63",
};
const SHOTS = [60, 170, 330, 700, 1400, 2100];

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
    const counter = { blits: 0 };
    const cartBytes = await readFile(CART);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    env.hwBlit = () => { counter.blits++; machine.hwBlit(); };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, counter };
}

const errors = [];
let injected = false;
const ok = (cond, msg) => { if (!cond) errors.push(msg); };
await mkdir(out, { recursive: true });
const { memory, machine, demo, counter } = await boot();
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const pfb = () => new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), W * H);
const bg = () => new Uint32Array(memory.buffer, machine.hwVideoBase() + 4, 1)[0];

// ---- 1. music: the request is made in init, before the first frame
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = broke === "music" ? "not_the_tune.sndh" : "breath_2000.sndh";
    if (broke === "music" && name === "breath_2000.sndh") injected = true;
    ok(pending === 1 && name === want, `music: asked for '${name}' (pending ${pending}), want ${want}`);
}

let maxBlits = 0;
let frame = 0;
function step() {
    frame++;
    machine.hwClear();
    counter.blits = 0;
    demo.frame(16.6);
    maxBlits = Math.max(maxBlits, frame > 1 ? counter.blits : 0);
    machine.hwRenderPlane(0);
}

// ---- 2 + 3. borders and the raster, on the composed picture of this frame
function checkLines(where, wantOpen) {
    const px = pfb(), back = bg();
    const fb = new Uint8Array(memory.buffer, demo.animaFb(), 400 * 280);
    let rasterRows = 0, borderBad = 0, rasterBad = 0;
    const colours = new Set();
    for (let r = 0; r < H; r++) {
        const open = demo.animaLineOpen(r) === 1;
        const want = wantOpen(r);
        if (open !== want) borderBad++;
        let rc = demo.animaRasterAt(r) >>> 0;
        if (broke === "raster" && r === 150) rc ^= 0x00ffffff;
        colours.add(rc);
        if (r < 40 || r >= 240) continue; // bands: checked through the side columns below only
        for (const [x, lx] of [[0, 0], [W - 1, 399]]) {
            const p = px[r * W + x];
            if (!open) { if (p !== back) borderBad++; continue; }
            if (fb[r * 400 + lx] !== 0) continue; // something drawn there: not the raster
            rasterRows++;
            if (p !== rc) { rasterBad++; if (process.env.ANIMA_DEBUG && rasterBad < 6) console.log(where, r, x, p.toString(16), rc.toString(16)); }
        }
    }
    if (broke === "border" && where === "dark") borderBad += demo.animaLineOpen(140) === 0 ? 1 : 0;
    ok(borderBad === 0, `${where}: ${borderBad} border mismatches (closed must show the background, open the plane)`);
    ok(rasterBad === 0, `${where}: ${rasterBad} border pixels are not their line's raster colour`);
    if (where === "main") {
        ok(rasterRows > 300, `${where}: only ${rasterRows} raster samples in the side borders`);
        ok(colours.size >= 30, `${where}: only ${colours.size} raster colours over 280 lines`);
    }
    if (broke === "raster" && rasterBad > 0) injected = true;
    if (broke === "border" && borderBad > 0) injected = true;
}

const hashes = {};
async function shot(f) {
    const px = new Uint8Array(pfb().buffer, machine.hwPhysicalPtr(), W * H * 4);
    const h = createHash("sha256");
    if (broke === "hash" && f === SHOTS[2]) { const c = px.slice(); c[1000] ^= 1; h.update(c); } else h.update(px);
    hashes[f] = h.digest("hex");
    const rgb = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) for (let c = 0; c < 3; c++) rgb[i * 3 + c] = px[i * 4 + c];
    await writeFile(`${out}/anima-${String(f).padStart(4, "0")}.ppm`, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]));
}

const last = SHOTS[SHOTS.length - 1];
while (frame < last) {
    step();
    if (frame === 30) checkLines("dark", () => false);
    if (frame === 120) {
        // timeline.zig: sides open from line 140 out over 60 ticks from tick 90, bands later
        const t = demo.animaTick();
        const sides = Math.floor(Math.floor((t - 90) * 256 / 60) * 100 / 256);
        ok(t > 90 && t < 150, `open: tick ${t} is not in the sides' minute`);
        checkLines("open", (r) => r >= 40 && r < 240 && Math.abs(r - 140) <= sides);
    }
    if (frame === 600) checkLines("main", () => true);
    if (SHOTS.includes(frame)) await shot(frame);
}
ok(maxBlits <= MAX_BLITS, `CHISEL: ${maxBlits} ops in one frame (ceiling ${MAX_BLITS})`);
console.log(`  CHISEL ops: at most ${maxBlits} a frame`);
if (PIN) console.log(JSON.stringify(hashes, null, 4));
for (const f of SHOTS) {
    if (PINS[f] === undefined) { ok(PIN, `frame ${f}: no pinned hash`); continue; }
    if (hashes[f] !== PINS[f]) { ok(false, `frame ${f}: picture hash ${hashes[f].slice(0, 16)} != pinned ${PINS[f].slice(0, 16)}`); if (broke === "hash") injected = true; }
}

// ---- 6. the board cost per phase (jump the timeline, measure 30 frames)
if (!NO_COST) {
    const ceiling = broke === "cost" ? 0.5 : CEILING_MC;
    for (const [name, t] of [["dark", 20], ["open", 150], ["breathe", 260], ["scroll", 400], ["cube", 700], ["octa", 1400], ["ico", 2100], ["star", 2800]]) {
        const o = parseArgs([CART, "--frames", "30", "--warmup", "5", "--call", `1:animaJump:${t}`]);
        const r = await costOf(CART, o);
        console.log(`  cost ${name.padEnd(8)} tick ${t}: est. ${r.mc.avg} Mc/frame avg, ${r.mc.max} max (split ${JSON.stringify(r.split)})`);
        if (r.mc.max > ceiling) { ok(false, `cost ${name}: ${r.mc.max} Mc > ${ceiling}`); if (broke === "cost") injected = true; }
    }
}

if (broke) {
    console.log(injected ? `anima: PASS (--break ${broke} caught: ${errors[0]})` : `anima: FAILED -- --break ${broke} was not caught`);
    process.exit(injected ? 0 : 1);
}
for (const e of errors) console.log(`  FAIL ${e}`);
console.log(errors.length ? `anima: FAILED (${errors.length})` : "anima: PASS (music, borders closed/opening/open, real raster in both side borders, pinned frames, CHISEL ops, est. cost per phase)");
process.exit(errors.length ? 1 : 0);
