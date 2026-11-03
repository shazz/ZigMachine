// The true-colour plane (HW 1.15.0, FB_MODE_TRUECOLOR 5 / FB_MODE_TRUECOLOR_FULL 6), driven straight
// through the sealed machine with no cart and checked pixel by pixel against an independent model
// of the rule (fpga/review/TRUECOLOR_PLANE.md):
//   - a pixel is a little-endian u16 R5 G6 B5, expanded by bit replication (0xFFFF white), alpha 255;
//   - mode 6 covers the whole 800x280 raster from (0, 0), doubled, physical lines; mode 5 the
//     320x200 window at (80, 40), logical lines; nothing else of the PFB changes;
//   - FB_STRIDE, HSCROLL (re-read every line, after the handler) and a copper LBASE are bytes, and
//     bit 0 of a line's address is ignored (an odd one shows the even pixel below).
// The full plane's buffer holds pixel i = i & 0xFFFF, so every 565 value is shown and checked.
//
//   node apps/truecolor_check.mjs           (exit 1 on any failure)
//   node apps/truecolor_check.mjs --break   the model breaks one rule at a time (expansion by
//                                           shift, bit 0 honoured, stride in pixels, HSCROLL latched,
//                                           the window's geometry for mode 6, LBASE ignored):
//                                           passes only if the checks catch every one.
import { readFile } from "node:fs/promises";
import { OFF_VRAM, RH, REG_HSCROLL, REG_FB_COPPER } from "./linebase_model.mjs";

const PAGES = 128, VIDEO = 0x400000, RW = 800, BG = 0xFF123456;
const REG_BACKGROUND = 0x04, REG_FB_HBL_ID = 0x20, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44, REG_FB_MODE = 0x54;
const LIST = OFF_VRAM + 0xF0000;
// [plane, mode, stride, FB_BASE]: the full plane at an odd base, the window with an odd stride
const PLANES = [[0, 6, 800, OFF_VRAM + 1], [1, 5, 641, OFF_VRAM + 0x50000 + 3]];
const LBASES = new Map([[10, OFF_VRAM + 0x8001], [150, OFF_VRAM + 0x20000]]); // plane 0's list (raster lines)
const hsOf = (p, line) => (p === 1 ? (line * 7) % 301 : line % 5 === 0 ? 0 : (line * 3) % 97);

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const dv = () => new DataView(memory.buffer);
const set16 = (o, v) => dv().setUint16(VIDEO + o, v, true), set32 = (o, v) => dv().setUint32(VIDEO + o, v >>> 0, true);
const r16 = (o) => dv().getUint16(VIDEO + o, true);
const machine = (await WebAssembly.instantiate(await readFile(process.env.MACHINE || "docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, line) => set16(REG_HSCROLL + 2 * p, hsOf(p, line)) },
})).instance.exports;

function setup() {
    machine.hwInit();
    set32(REG_BACKGROUND, BG);
    for (const [p, mode, stride, fb] of PLANES) {
        dv().setUint8(VIDEO + REG_FB_MODE + p, mode), set16(REG_FB_STRIDE + 2 * p, stride), set32(REG_FB_BASE + 4 * p, fb);
        set16(REG_FB_HBL_ID + 2 * p, p + 1);
    }
    for (let i = 0; i < 0x50000 / 2; i++) set16(OFF_VRAM + 2 * i, i & 0xFFFF); // includes every 565 value
    for (let i = 0; i < 0x40000 / 2; i++) set16(OFF_VRAM + 0x50000 + 2 * i, (i * 40503 + 7) & 0xFFFF);
    let at = LIST;
    for (const [y, v] of LBASES) set32(at, 0xF0000001 + (y << 19)), set32(at + 4, 0x50000000 + v), at += 8;
    set32(at, 0xF0000000 + (511 << 19));
    set16(REG_FB_COPPER, (LIST - OFF_VRAM) / 16);
}

// The rule, written out independently of machine/video_tc.zig; `brk` drops one part of it.
function expand(px, brk) {
    const r = px >> 11, g = (px >> 5) & 63, b = px & 31;
    const [r8, g8, b8] = brk === "shift" ? [r << 3, g << 2, b << 3] : [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)];
    return (0xFF000000 | (b8 << 16) | (g8 << 8) | r8) >>> 0;
}
function model(p, mode, stride, fb, brk) {
    const full = mode === 6 && brk !== "window", rows = full ? RH : 200, oy = full ? 0 : 40, ox = full ? 0 : 80;
    const cols = full ? 400 : 320, out = new Map();
    let base = fb, r0 = 0;
    for (let row = 0; row < rows; row++) {
        const y = oy + row;
        if (p === 0 && LBASES.has(y) && brk !== "lbase") base = LBASES.get(y), r0 = row;
        const hs = brk === "latched" ? hsOf(p, 0) : hsOf(p, row);
        let at = base + (row - r0) * (brk === "stride_px" ? 2 * stride : stride) + hs;
        if (brk !== "bit0") at &= ~1;
        for (let x = 0; x < cols; x++) {
            const lo = dv().getUint8(VIDEO + at + 2 * x), hi = dv().getUint8(VIDEO + at + 2 * x + 1);
            out.set(y * RW + ox + 2 * x, expand(lo | (hi << 8), brk));
        }
    }
    return out;
}

function render(p) {
    machine.hwClear(), machine.hwRenderPlane(p);
    const base = machine.hwPhysicalPtr();
    return Uint32Array.from({ length: RW * RH }, (_, i) => dv().getUint32(base + 4 * i, true));
}
// The first pixel where the machine and the model differ, or null.
function mismatch(shot, want) {
    for (let i = 0; i < RW * RH; i++) {
        const m = want.get(i - (i & 1)), got = shot[i], exp = m ?? BG;
        if (got !== exp) return `(${i % RW}, ${Math.floor(i / RW)}): machine 0x${got.toString(16)}, model 0x${exp.toString(16)}`;
    }
    return null;
}

let failures = 0;
const check = (name, err) => { console.log(`  ${err ? "FAIL" : "ok  "} ${name}${err ? ` — ${err}` : ""}`); failures += !!err; };
check("the machine reports HW 1.15.0 or later", machine.hwVersion() >= 0x00010F00 ? null : `hwVersion 0x${machine.hwVersion().toString(16)}`);
setup();
const shots = PLANES.map(([p]) => render(p));
const seen = new Set();
for (let i = 0; i < 400 * 280; i++) seen.add(r16(OFF_VRAM + 2 * i) & 0xFFFF);
if (!process.argv.includes("--break")) {
    check("every 565 value is in the full plane's source", seen.size === 65536 ? null : `${seen.size} values`);
    check("mode 6: the whole raster, odd FB_BASE, LBASEs (an odd one), HSCROLL per line", mismatch(shots[0], model(...PLANES[0])));
    check("mode 5: the window, odd stride, odd HSCROLL every other line", mismatch(shots[1], model(...PLANES[1])));
    check("the second frame is the first one again (FB_BASE re-latched)", mismatch(render(0), model(...PLANES[0])));
    console.log(failures ? `truecolor_check: ${failures} FAILED` : "truecolor_check: all pass");
    process.exit(failures ? 1 : 0);
}
let missed = 0;
for (const brk of ["shift", "bit0", "stride_px", "latched", "window", "lbase"]) {
    const caught = PLANES.some((cfg, k) => mismatch(shots[k], model(...cfg, brk)) !== null);
    console.log(`  ${caught ? "ok  " : "FAIL"} a model with '${brk}' is caught`);
    missed += !caught;
}
console.log(missed ? `truecolor_check --break: ${missed} mutant(s) NOT caught` : "truecolor_check --break: every mutant caught");
process.exit(missed ? 1 : 0);
