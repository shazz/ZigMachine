// BEAM (HW 1.6.0): mid-line colour-0 writes, driven straight through the sealed
// machine with no cart in the way. This script IS the global HBL handler: on a
// band of lines it queues a row of 8 px cells across the WHOLE line, borders
// included, the way a zero-bitplane ST screen rewrites $FF8240 with move.w's.
//
// It proves, on the physical framebuffer:
//   - with no writes the machine is the pre-1.6.0 background fill;
//   - every pixel of a beam line is the cell colour the list asked for;
//   - the last colour persists into the next line (colour 0 keeps its value);
//   - the list is consumed once per line (COUNT back to 0);
//   - nothing was dropped (REG_BEAM_DROPPED == 0).
//
//   node apps/beam_check.mjs            (exit 1 on any failure)
//   node apps/beam_check.mjs --break    cells 4 px apart, faster than a move.w:
//                                       passes only if the checks catch it AND
//                                       the machine counted the drops.
import { readFile } from "node:fs/promises";

const PAGES = 112;                  // memmap.SHARED_PAGES
const VIDEO = 0x300000;             // HW_VIDEO_BASE
const REG_BACKGROUND = 0x04, REG_GLOBAL_HBL_ID = 0x10, HBL_GLOBAL_ID = 5;
const REG_BEAM_COUNT = 0x64, REG_BEAM_DROPPED = 0x68;
const OFF_BEAM_TABLE = 0x1DBD00;    // OFF_PFB + PFB_BYTES
const W = 400, RW = 800, RH = 280;  // physical px, raster px, lines
const BAND = [100, 110];            // lines [a, b) that carry beam writes
const COLOURS = [0x700, 0x077];     // alternate cells: red, cyan
const BLACK = 0xFF000000;

const broke = process.argv.includes("--break");
const CELL = broke ? 4 : 8;

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const dv = () => new DataView(memory.buffer);
let hbl = () => {};
const machine = (await WebAssembly.instantiate(
    await readFile(process.env.MACHINE || "docs/machine-video.wasm"),
    { env: { memory, hblDispatch: (id, p, line) => hbl(line) } })).instance.exports;

const reg16 = (o) => dv().getUint16(VIDEO + o, true);
const reg32 = (o) => dv().getUint32(VIDEO + o, true);
const set16 = (o, v) => dv().setUint16(VIDEO + o, v, true);
const set32 = (o, v) => dv().setUint32(VIDEO + o, v >>> 0, true);

// machine/beam.zig stToRgba: STE 4-bit level x 16, RGBA little-endian.
const gun = (n) => ((((n & 7) << 1) | ((n >> 3) & 1)) * 16);
const rgba = (w) => (0xFF000000 | (gun(w) << 16) | (gun(w >> 4) << 8) | gun(w >> 8)) >>> 0;

// Both raster pixels of physical pixel x on line y must agree; returns the colour.
function px(x, y) {
    const base = machine.hwPhysicalPtr() + (y * RW + 2 * x) * 4;
    const a = dv().getUint32(base, true), b = dv().getUint32(base + 4, true);
    return a === b ? a : -1;
}
const hex = (v) => "0x" + (v >>> 0).toString(16);

let failures = 0;
function check(name, fn) {
    const err = fn();
    console.log(`  ${err ? "FAIL" : "ok  "} ${name}${err ? ` — ${err}` : ""}`);
    if (err) failures++;
}
function lineIs(y, want) {
    for (let x = 0; x < W; x++) if (px(x, y) !== want(x)) return `line ${y} x ${x}: ${hex(px(x, y))}, want ${hex(want(x))}`;
    return null;
}

// BEAM arrived in 1.6.0; later minors are additive (1.7.0: the RAM arena), so
// what BEAM needs is "1.6.0 or later, same major".
check("the machine reports HW 1.6.0 or later", () => {
    const v = machine.hwVersion();
    return v >= 0x00010600 && v < 0x00020000 ? null : `hwVersion ${hex(v)}`;
});
check("the BEAM table sits right above the physical framebuffer", () =>
    machine.hwPhysicalPtr() + RW * RH * 4 === VIDEO + OFF_BEAM_TABLE ? null : "OFF_BEAM_TABLE moved");

// --- inert: no writes, the old fill -------------------------------------
machine.hwInit();
set32(REG_BACKGROUND, 0xFF203040);
machine.hwClear();
check("no BEAM writes: every line is BACKGROUND, borders included", () => {
    for (let y = 0; y < RH; y++) { const e = lineIs(y, () => 0xFF203040); if (e) return e; }
    return reg32(REG_BEAM_DROPPED) === 0 ? null : "drops counted with no writes";
});

// --- a band of cells -------------------------------------------------------
machine.hwInit();
set32(REG_BACKGROUND, BLACK);
set16(REG_GLOBAL_HBL_ID, HBL_GLOBAL_ID);
const cells = Math.floor(W / CELL);
let countLeft = 0;
hbl = (line) => {
    if (line === BAND[1]) countLeft = reg16(REG_BEAM_COUNT); // what the last band line left
    if (line < BAND[0] || line >= BAND[1]) return;
    const n = Math.min(cells, 64);
    for (let i = 0; i < n; i++)
        set32(OFF_BEAM_TABLE + 4 * i, ((i * CELL) << 16) | COLOURS[i & 1]);
    set16(REG_BEAM_COUNT, n);
};
machine.hwClear();
const cellColour = (x) => rgba(COLOURS[Math.floor(x / 8) & 1]);
const last = rgba(COLOURS[(Math.floor(W / 8) - 1) & 1]);

check("the line above the band is untouched background", () => lineIs(BAND[0] - 1, () => BLACK));
check("every band pixel is its 8 px cell's colour, both borders included", () => {
    for (let y = BAND[0]; y < BAND[1]; y++) { const e = lineIs(y, cellColour); if (e) return e; }
    return null;
});
check("the list is consumed once per line (COUNT back to 0)", () =>
    countLeft === 0 && reg16(REG_BEAM_COUNT) === 0 ? null : `COUNT ${countLeft} after the band`);
check("the last colour persists into the next lines (colour 0 keeps its value)", () =>
    lineIs(BAND[1], () => last) ?? lineIs(RH - 1, () => last) ??
    (reg32(REG_BACKGROUND) === last ? null : `BACKGROUND ${hex(reg32(REG_BACKGROUND))}`));
const dropped = reg32(REG_BEAM_DROPPED);
check("no write was dropped", () => dropped === 0 ? null : `${dropped} dropped`);

if (broke) {
    const ok = failures > 0 && dropped > 0;
    console.log(ok ? `beam_check: PASS (--break was caught, ${dropped} writes dropped)`
        : `beam_check: FAILED — 4 px writes were not caught (dropped ${dropped})`);
    process.exit(ok ? 0 : 1);
}
console.log(failures ? `beam_check: ${failures} FAILED` : "beam_check: all pass ✅");
process.exit(failures ? 1 : 0);
