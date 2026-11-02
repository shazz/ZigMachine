// Copper LBASE + HSCROLL on overscan planes (HW 1.10.0, fpga/review/COPPER_LINEBASE.md), driven
// straight through the sealed machine with no cart: the STE line list (video counter, HSCROLL and
// colour 0 rewritten every line) as copper records, checked pixel by pixel against the independent
// model of the rule in apps/linebase_model.mjs:
//   - an LBASE sets the line's source; the lines after it run on by the stride (the counter);
//   - an overscan plane adds HSCROLL, read per line after the record, no wrap;
//   - a normal plane takes LBASE too and ignores HSCROLL;
//   - an LBASE outside VRAM stops the list (the rest of its record and every later one);
//   - every frame starts from FB_BASE: the second frame is the first one again.
//
//   node apps/linebase_check.mjs           (exit 1 on any failure)
//   node apps/linebase_check.mjs --break   the model forgets one rule at a time (persistence,
//                                          overscan HSCROLL, the stop, the frame reset): passes
//                                          only if the checks catch every one.
import { readFile } from "node:fs/promises";
import { OFF_VRAM, RH, REG_HSCROLL, REG_FB_COPPER, decodeList, model, firstMismatch } from "./linebase_model.mjs";

const PAGES = 144, VIDEO = 0x500000;
const REG_BACKGROUND = 0x04, REG_FB_HBL_POS = 0x28, REG_FB_STRIDE = 0x34;
const REG_FB_BASE = 0x44, REG_FB_MODE = 0x54, OFF_PAL = 0x100;
const RW = 800, BG = 0xFF123456;
const FB0 = OFF_VRAM, SRC = OFF_VRAM + 0x20000, SRC_ROWS = 600; // plane 0: overscan, stride 400
const FB1 = OFF_VRAM + 0x70000;                                  // plane 1: normal, stride 320
const LIST = [OFF_VRAM + 0x80000, OFF_VRAM + 0x90000];

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const dv = () => new DataView(memory.buffer);
const machine = (await WebAssembly.instantiate(
    await readFile(process.env.MACHINE || "docs/machine-video.wasm"),
    { env: { memory, hblDispatch: () => {} } })).instance.exports;
const r8 = (o) => dv().getUint8(VIDEO + o), r16 = (o) => dv().getUint16(VIDEO + o, true);
const r32 = (o) => dv().getUint32(VIDEO + o, true);
const set8 = (o, v) => dv().setUint8(VIDEO + o, v);
const set16 = (o, v) => dv().setUint16(VIDEO + o, v, true);
const set32 = (o, v) => dv().setUint32(VIDEO + o, v >>> 0, true);
const hex = (v) => "0x" + (v >>> 0).toString(16);
const pal = (p, i) => (0xFF000000 | (i << 16) | ((255 - i) << 8) | (p * 64 + (i * 3) % 64)) >>> 0;

// --- the lists: plane 0 overscan, plane 1 normal ----------------------------------------------
function words0(y) {
    if (y < 3) return [];
    const w = [0x30000000];                                                       // FLICK
    if (y === 250) w.push(0x50000000 + OFF_VRAM - 1);                              // stops the list here
    else if (y % 7 === 3 && y >= 10) w.push(0x50000000 + SRC + ((y * 37) % 560) * 400 + (y % 9));
    if (y % 4 === 0) w.push(0x20000000 + (REG_HSCROLL << 20) + (y % 40 === 0 ? 397 : (y * 3) % 16));
    if (y % 6 === 0) w.push(0x10001000, (0xFF000000 | (y * 0x0101)) >>> 0);       // colour 0
    return w;
}
function words1(y) { // a flip on even visible lines; odd lines run on; an HSCROLL a normal plane ignores
    const ly = y - 40;
    return ly >= 0 && ly < 200 && ly % 2 === 0 ? [0x50000000 + FB1 + (199 - ly) * 320, 0x20000000 + ((REG_HSCROLL + 2) << 20) + 5] : [];
}
function writeList(p, wordsOf) {
    let at = LIST[p];
    const put = (w) => { set32(at, w); at += 4; };
    for (let y = 0; y < RH; y++) {
        const w = wordsOf(y);
        if (w.length) put(0xF0000000 + (y << 19) + w.length), w.forEach(put);
    }
    put(0xF0000000 + (511 << 19));
    set16(REG_FB_COPPER + 2 * p, (LIST[p] - OFF_VRAM) / 16);
}

function setup() {
    machine.hwInit();
    set32(REG_BACKGROUND, BG);
    for (let p = 0; p < 2; p++) for (let i = 0; i < 256; i++) set32(OFF_PAL + p * 1024 + 4 * i, pal(p, i));
    [[0, 4, 400, FB0], [1, 0, 320, FB1]].forEach(([p, mode, stride, fb]) => {
        set8(REG_FB_MODE + p, mode), set16(REG_FB_STRIDE + 2 * p, stride), set32(REG_FB_BASE + 4 * p, fb);
        set16(REG_FB_HBL_POS + 2 * p, 40), set16(REG_HSCROLL + 2 * p, 0);
    });
    for (let i = 0; i < 400 * 280; i++) set8(FB0 + i, (i * 5 + 3) & 0xFF);
    for (let y = 0; y < SRC_ROWS; y++) for (let x = 0; x < 400; x++) set8(SRC + y * 400 + x, (x * 7 + y * 13 + 1) & 0xFF);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) set8(FB1 + y * 320 + x, (x + 3 * y) & 0xFF);
    writeList(0, words0), writeList(1, words1);
}
// One frame of plane p, with what the model needs from its start (HSCROLL, the palette).
function render(p) {
    const cfg = { ovs: p === 0, scroll: false, stride: p === 0 ? 400 : 320, fb: p === 0 ? FB0 : FB1,
        hs0: r16(REG_HSCROLL + 2 * p), pal: Array.from({ length: 256 }, (_, i) => r32(OFF_PAL + p * 1024 + 4 * i)) };
    machine.hwClear(), machine.hwRenderPlane(p);
    const base = machine.hwPhysicalPtr(), px = new Uint32Array(400 * RH);
    for (let y = 0; y < RH; y++) for (let x = 0; x < 400; x++) px[y * 400 + x] = dv().getUint32(base + (y * RW + 2 * x) * 4, true);
    return { p, cfg, px };
}
const compare = (shot, brk) => firstMismatch(model(shot.cfg, decodeList(r32, LIST[shot.p]), brk), r8,
    (x, y) => shot.px[y * 400 + x], BG);

let failures = 0;
const check = (name, err) => { console.log(`  ${err ? "FAIL" : "ok  "} ${name}${err ? ` — ${err}` : ""}`); failures += !!err; };
check("the machine reports HW 1.10.0 or later", machine.hwVersion() >= 0x00010A00 ? null : `hwVersion ${hex(machine.hwVersion())}`);
setup();
const shots = [render(0), render(0), render(1)];
if (!process.argv.includes("--break")) {
    check("overscan plane: LBASE, run-on, HSCROLL per line, colour 0, borders, the stop", compare(shots[0]));
    check("the second frame starts from FB_BASE again (same rule, palette and HSCROLL carried)", compare(shots[1]));
    check("normal plane: LBASE flip, HSCROLL ignored", compare(shots[2]));
    console.log(failures ? `linebase_check: ${failures} FAILED` : "linebase_check: all pass");
    process.exit(failures ? 1 : 0);
}
let missed = 0;
for (const brk of ["persist", "hscroll", "stop", "reset"]) {
    const caught = shots.some((s) => compare(s, brk) !== null);
    console.log(`  ${caught ? "ok  " : "FAIL"} a model without '${brk}' is caught`);
    missed += !caught;
}
console.log(missed ? `linebase_check --break: ${missed} mutant(s) NOT caught` : "linebase_check --break: every mutant caught");
process.exit(missed ? 1 : 0);
