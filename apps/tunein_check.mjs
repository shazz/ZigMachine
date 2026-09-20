// Channel-change snow for the polyglot carts: a C or Rust channel must tune in
// through the SAME TV snow as a Zig cart, then start exactly as skipBoot would.
//
// The host, on +/-: hwInit, boot, tuneIn(25) (docs/sealed-loader.js). A Zig cart
// (apps/zig/demo_main.zig) draws snow on frames 1..25 and starts the cart on
// frame 26 as the first frame after skipBoot(). So, per cart, over the real host
// loop (hwClear, frame, hwRenderPlane per enabled plane; see apps/scene_hash.mjs):
//
//   snow    frames 1..25: plane 0's mode, stride, base, raw 400x280 pixels, the
//           whole of palette 0 and the rendered RGBA of every enabled plane are
//           byte-identical to the Zig reference cart's.
//   start   tuned frame 25+k == skipBoot frame k (rendered planes + palette 0),
//           k = 2..AFTER, byte for byte. At k = 1 (frame 26, the cart's first,
//           not snow) palette 0 is identical and the ONLY differing pixels show
//           the snow's background: the host runs hwClear BEFORE frame(), so that
//           clear still paints the snow's BACKGROUND register, and the cart puts
//           its own back inside frame(). demo_main has the same one-frame lag (it
//           resets at frame 26 too), so the Zig reference is held to this check.
//   escape  skipBoot after 10 snow frames: frame 10+k == skipBoot frame k.
//   ignored tuneIn after the cart has run changes nothing.
//
//   node apps/tunein_check.mjs                         # every c-*/rust-* channel
//   node apps/tunein_check.mjs <cart.wasm> ...          # just these
//   node apps/tunein_check.mjs --fail-proof <cart> ...  # passes only if each FAILS
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TUNE = 25; // TUNE_FRAMES in docs/sealed-loader.js
const AFTER = 60;
const ESC_AT = 10;
const DT = 16.6;
const ZIG_REF = "docs/demo-tutorial.wasm"; // any Zig scene: demo_main.zig owns the snow
const REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44, REG_FB_MODE = 0x54, OFF_PAL = 0x100, PH = 280;

async function boot(path) {
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
    const bytes = await readFile(path);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(bytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    return { memory, machine, demo, base: machine.hwVideoBase() };
}

const SNOW_BG = [20, 20, 20, 255]; // resetForScene's background, which tuneIn sets

// One host frame. Returns the rendered hash, a copy of palette 0 and, with
// `keep`, each plane's rendered RGBA (null for a disabled plane).
function step({ memory, machine, demo, base }, keep = false) {
    machine.hwClear();
    demo.frame(DT);
    const h = createHash("sha256");
    const size = machine.hwPhysWidth() * machine.hwPhysHeight() * 4;
    const planes = [];
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) { h.update(`off${p}`); planes.push(null); continue; }
        machine.hwRenderPlane(p);
        const rgba = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), size);
        h.update(rgba);
        planes.push(keep ? rgba.slice() : null);
    }
    return { hash: h.digest("hex"), pal: new Uint8Array(memory.buffer, base + OFF_PAL, 1024).slice(), planes };
}

// k = 1 after the snow: how many pixels differ, or an error when one of them is
// anything but the snow's background showing through the host's first clear.
function lagPixels(got, want) {
    let n = 0;
    for (let p = 0; p < got.planes.length; p++) {
        const a = got.planes[p], b = want.planes[p];
        if (!a !== !b) return `plane ${p} enabled differs`;
        for (let i = 0; a && i < a.length; i += 4) {
            if (a[i] === b[i] && a[i + 1] === b[i + 1] && a[i + 2] === b[i + 2] && a[i + 3] === b[i + 3]) continue;
            if (SNOW_BG.some((v, j) => a[i + j] !== v)) return `pixel ${(i / 4) % 800},${Math.floor(i / 3200)} of plane ${p} is neither the cart's nor the snow's background`;
            n++;
        }
    }
    return n;
}

function plane0({ memory, base }) {
    const v = new DataView(memory.buffer, base);
    const stride = v.getUint16(REG_FB_STRIDE, true), fb = v.getUint32(REG_FB_BASE, true);
    return { mode: v.getUint8(REG_FB_MODE), stride, fb,
             pixels: new Uint8Array(memory.buffer, base + fb, stride * PH).slice() };
}

const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

async function snowOf(path) {
    const run = await boot(path);
    run.demo.tuneIn(TUNE);
    const frames = [];
    for (let f = 1; f <= TUNE; f++) frames.push({ ...step(run), ...plane0(run) });
    return { run, frames };
}

async function skipRun(path, n) {
    const run = await boot(path);
    run.demo.skipBoot();
    const frames = [];
    for (let k = 1; k <= n; k++) frames.push(step(run, k === 1));
    return frames;
}

// The next AFTER frames of `run` against skipBoot frames 1..AFTER. `lag`: the
// first frame may show the snow's background (see the header). Returns the
// number of lag pixels, or an error string.
function matchSkip(run, skip, label, lag) {
    let lagged = 0;
    for (let k = 1; k <= AFTER; k++) {
        const got = step(run, k === 1);
        if (!same(got.pal, skip[k - 1].pal)) return `${label}: palette 0 of cart frame ${k} differs from skipBoot frame ${k}`;
        if (got.hash === skip[k - 1].hash) continue;
        if (k === 1 && lag) {
            lagged = lagPixels(got, skip[0]);
            if (typeof lagged === "string") return `${label}: frame 1: ${lagged}`;
            continue;
        }
        return `${label}: frame ${k} of the cart differs from skipBoot frame ${k}`;
    }
    return lagged;
}

// start, escape and late tuneIn, for any cart (the Zig reference included).
async function startChecks(path, lastSnow) {
    const skip = await skipRun(path, AFTER);
    if (skip[0].hash === lastSnow.hash) return "the cart's first frame is still snow";
    const lag = matchSkip(lastSnow.run, skip, "after the snow", true);
    if (typeof lag === "string") return lag;

    const esc = await boot(path);
    esc.demo.tuneIn(TUNE);
    for (let f = 1; f <= ESC_AT; f++) step(esc);
    esc.demo.skipBoot();
    const escaped = matchSkip(esc, skip, `skipBoot after ${ESC_AT} snow frames`, false);
    if (typeof escaped === "string") return escaped;

    const late = await boot(path);
    late.demo.skipBoot();
    if (step(late).hash !== skip[0].hash) return "skipBoot run is not deterministic";
    late.demo.tuneIn(TUNE);
    for (let k = 2; k <= AFTER; k++)
        if (step(late).hash !== skip[k - 1].hash) return `tuneIn on a running cart changed frame ${k}`;
    return { lag, first: skip[0].hash.slice(0, 12) };
}

async function check(path, ref) {
    const exports = WebAssembly.Module.exports(new WebAssembly.Module(await readFile(path))).map((e) => e.name);
    if (!exports.includes("tuneIn")) return "no tuneIn export";
    const { run, frames } = await snowOf(path);
    let pixels = 0;
    for (let i = 0; i < TUNE; i++) {
        const z = ref[i], c = frames[i];
        for (const k of ["mode", "stride", "fb"])
            if (z[k] !== c[k]) return `snow frame ${i + 1}: plane 0 ${k} ${c[k]} != Zig ${z[k]}`;
        if (!same(z.pixels, c.pixels)) return `snow frame ${i + 1}: plane 0 pixels differ from Zig`;
        if (!same(z.pal, c.pal)) return `snow frame ${i + 1}: palette 0 differs from Zig`;
        if (z.hash !== c.hash) return `snow frame ${i + 1}: rendered planes differ from Zig`;
        pixels += c.pixels.length;
    }
    const start = await startChecks(path, { run, hash: frames[TUNE - 1].hash });
    return typeof start === "string" ? start : { pixels, ...start };
}

const argv = process.argv.slice(2);
const failProof = argv[0] === "--fail-proof";
let carts = argv.filter((a) => a !== "--fail-proof");
if (carts.length === 0) {
    // channels.json is a list of {tag, title, type} records (tools/channels.py).
    const channels = JSON.parse(await readFile("docs/channels.json", "utf8"));
    carts = channels.map((c) => c.tag).filter((t) => /^(c|rust)-/.test(t))
        .map((t) => `docs/demo-${t}.wasm`);
}
const zig = await snowOf(ZIG_REF);
const ref = zig.frames;
const levels = new Set(ref[0].pixels).size;
const control = await startChecks(ZIG_REF, { run: zig.run, hash: ref[TUNE - 1].hash });
if (levels < 4 || same(ref[0].pixels, ref[1].pixels) || typeof control === "string") {
    console.log(`FAIL  the Zig reference ${ZIG_REF} is broken: ${levels} snow levels; ${control}`);
    process.exit(1);
}
console.log(`tuneIn: ${TUNE} snow frames of ${ZIG_REF} (${levels} grey levels; its own start lags ${control.lag} border px), then ${AFTER} cart frames`);
let bad = 0;
for (const cart of carts) {
    const r = await check(cart, ref);
    const ok = typeof r !== "string";
    if (ok) console.log(`  ${failProof ? "FAIL" : "PASS"}  ${cart}: ${r.pixels} snow pixels = Zig; frame ${TUNE}+k = skipBoot frame k (k=1: ${r.lag} px show the snow's background); escape and late tuneIn exact`);
    else console.log(`  ${failProof ? "PASS (fails as it must)" : "FAIL"}  ${cart}: ${r}`);
    if (ok === failProof) bad++;
}
if (carts.length === 0) { console.log("FAIL  no carts to check"); process.exit(1); }
if (bad) process.exit(1);
