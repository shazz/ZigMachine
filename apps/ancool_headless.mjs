// Headless AN COOL check (apps/zig/scenes/ancool.zig): the starfield, the TCB
// wireframe letters and the raster scroller moved from three planes into ONE
// (2026-10-23: each enabled plane costs ~0.59 Mc of FRESCO a frame on the board),
// so the planes changed and the picture must not. EVERY frame of the run is
// composited as the browser stacks its plane canvases (each enabled plane's
// physical render, HBLs included, topmost non-clear pixel wins: scene_hash's
// stackOver) and, per 300-frame period, the SHA-256 of those composites equals
// apps/ancool_expected.json, written from the three-plane cart as it was before
// (git 82db48da:docs/demo-ancool.wasm). 3600 frames: the starfield's 104-frame
// start and 52-frame cycle many times over, the letters, the whole scroll text.
// Also, every frame: exactly ONE plane enabled, at most one CHISEL blit (the
// clear), and the scroller's raster is a colour register per line: on every
// line, every ink pixel has the same colour, and at some frame the band shows
// 20+ colours at once (the text has gaps, so not every frame does).
//
//   node apps/ancool_headless.mjs [--break skip|planes|raster] [--cart X.wasm] [--write]
//     --break skip    one extra frame at 2000: the later periods must differ
//     --break planes  the pre-change three-plane cart (same pixels): the plane count must fail
//     --break raster  two inks painted on one line of the composite: the raster check must fail
//     --write         (re)write apps/ancool_expected.json from --cart (never in the gate)
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { boot } from "./ancool_boot.mjs";

const EXPECTED = "apps/ancool_expected.json";
const FRAMES = 3600, PERIOD = 300;
const OLD_REV = "82db48da"; // the last three-plane cart

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i < 0 ? dflt : argv[i + 1]; };
const brk = opt("--break", null);
if (brk && !["skip", "planes", "raster"].includes(brk)) throw new Error(`--break takes skip|planes|raster, not ${brk}`);
let cartBytes = readFileSync(opt("--cart", "docs/demo-ancool.wasm"));
if (brk === "planes") cartBytes = execFileSync("git", ["show", `${OLD_REV}:docs/demo-ancool.wasm`], { maxBuffer: 16 << 20 });

const m = await boot(cartBytes);
const { W, H } = m;
const comp = new Uint32Array(W * H);
const fails = [];
const fail = (msg) => { if (fails.length < 20) fails.push(msg); };
const periods = [];
let period = createHash("sha256"), maxBlits = 0, maxPlanes = 0, rasterColours = 0;

for (let f = 1; f <= FRAMES; f++) {
    m.resetBlits();
    m.frame();
    if (brk === "skip" && f === 2000) m.frame();
    maxBlits = Math.max(maxBlits, m.blits());
    const enabled = m.composite(comp);
    maxPlanes = Math.max(maxPlanes, enabled);
    if (enabled !== 1) fail(`frame ${f}: ${enabled} planes enabled (want 1)`);
    if (brk === "raster" && f === 900) secondInk(comp);
    if (f >= 300 && f % 30 === 0) rasterColours = Math.max(rasterColours, checkRaster(comp, f));
    period.update(createHash("sha256").update(new Uint8Array(comp.buffer)).digest());
    if (f % PERIOD === 0) { periods.push({ from: f - PERIOD + 1, to: f, sha: period.digest("hex") }); period = createHash("sha256"); }
}

// --break raster: on the first line that carries ink, one more ink pixel in
// another colour (what a pixel-painted bar instead of a register would leave).
function secondInk(c) {
    const at = c.findIndex(isInk);
    c[at + 1] = c[at] ^ 0x00101010;
}

// The scroller's ink: any composite pixel that is not clear, the black border,
// star white, or letter red (the raster colours are none of those).
function isInk(p) {
    const rgb = p & 0xffffff;
    return (p >>> 24) !== 0 && rgb !== 0 && rgb !== 0xffffff && rgb !== 0x0000ff;
}

function checkRaster(c, f) {
    const seen = new Set();
    for (let y = 0; y < H; y++) {
        let ink = null;
        for (let x = 0; x < W; x++) {
            const p = c[y * W + x];
            if (!isInk(p)) continue;
            if (ink === null) ink = p;
            else if (p !== ink) { fail(`frame ${f} row ${y}: two scroller inks on one line (${ink.toString(16)}, ${p.toString(16)})`); break; }
        }
        if (ink !== null) seen.add(ink);
    }
    return seen.size;
}

if (argv.includes("--write")) {
    writeFileSync(EXPECTED, JSON.stringify({ frames: FRAMES, from: `${OLD_REV}:docs/demo-ancool.wasm`, periods }, null, 1) + "\n");
    console.log(`ancool: wrote ${EXPECTED}`);
    process.exit(0);
}
const want = JSON.parse(readFileSync(EXPECTED, "utf8")).periods;
const bad = periods.filter((p, i) => p.sha !== want[i].sha);
for (const p of bad) fail(`frames ${p.from}..${p.to}: composite differs from the three-plane cart`);
if (rasterColours < 20) fail(`the scroller band never shows more than ${rasterColours} raster colours at once (want 20+)`);
if (maxBlits > 1) fail(`up to ${maxBlits} CHISEL blits a frame (want 1: the clear)`);

const verdict = fails.length ? "FAIL" : "PASS";
console.log(`ancool: ${verdict} ${periods.length - bad.length}/${periods.length} periods (${FRAMES} frames) composite = three-plane cart; planes enabled <= ${maxPlanes}; blits/frame <= ${maxBlits}; raster colours ${rasterColours}`);
for (const msg of fails) console.log(`  ${msg}`);
const expectFail = brk !== null;
if (expectFail) {
    console.log(fails.length ? `ancool: --break ${brk} caught` : `ancool: --break ${brk} NOT caught`);
    process.exit(fails.length ? 0 : 1);
}
process.exit(fails.length ? 1 : 0);
