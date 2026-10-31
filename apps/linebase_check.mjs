// Copper LBASE + HSCROLL on overscan planes (HW 1.10.0, fpga/review/COPPER_LINEBASE.md), driven
// straight through the sealed machine with no cart: the STE line list (video counter, HSCROLL and
// colour 0 rewritten every line) as copper records, checked pixel by pixel against an independent
// model of the rule:
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

const PAGES = 112, VIDEO = 0x300000, OFF_VRAM = 0x1100, VRAM_END = OFF_VRAM + 0x100000;
const REG_BACKGROUND = 0x04, REG_FB_HBL_POS = 0x28, REG_FB_STRIDE = 0x34, REG_HSCROLL = 0x3C;
const REG_FB_BASE = 0x44, REG_FB_MODE = 0x54, REG_FB_COPPER = 0x78, OFF_PAL = 0x100;
const RW = 800, RH = 280, BG = 0xFF123456;
const FB0 = OFF_VRAM, SRC = OFF_VRAM + 0x20000, SRC_ROWS = 600; // plane 0: overscan, stride 400
const FB1 = OFF_VRAM + 0x70000;                                  // plane 1: normal, stride 320
const LIST = [OFF_VRAM + 0x80000, OFF_VRAM + 0x90000];

const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const dv = () => new DataView(memory.buffer);
const machine = (await WebAssembly.instantiate(
    await readFile(process.env.MACHINE || "docs/machine-video.wasm"),
    { env: { memory, hblDispatch: () => {} } })).instance.exports;
const r8 = (o) => dv().getUint8(VIDEO + o), r16 = (o) => dv().getUint16(VIDEO + o, true);
const set8 = (o, v) => dv().setUint8(VIDEO + o, v);
const set16 = (o, v) => dv().setUint16(VIDEO + o, v, true);
const set32 = (o, v) => dv().setUint32(VIDEO + o, v >>> 0, true);
const hex = (v) => "0x" + (v >>> 0).toString(16);

// --- the records: [line, [[op, value]...]] per plane --------------------------------------
const HEAD = (y, n) => 0xF0000000 + (y << 19) + n;
const OPS = { flick: () => [0x30000000], lbase: (v) => [0x50000000 + v],
    hs: (p) => (v) => [0x20000000 + ((REG_HSCROLL + 2 * p) << 20) + v], pal0: (c) => [0x10001000, c] };
function records0() {
    const recs = [];
    for (let y = 3; y < RH; y++) {
        const r = [["flick"]];
        if (y === 250) r.push(["lbase", OFF_VRAM - 1]);                 // stops the list here
        else if (y % 7 === 3 && y >= 10) r.push(["lbase", SRC + ((y * 37) % 560) * 400 + (y % 9)]);
        if (y % 4 === 0) r.push(["hs", y % 40 === 0 ? 397 : (y * 3) % 16]);
        if (y % 6 === 0) r.push(["pal0", (0xFF000000 | (y * 0x0101)) >>> 0]);
        recs.push([y, r]);
    }
    return recs;
}
function records1() { // a flip on the visible lines; odd lines run on from the even one above
    const recs = [];
    for (let ly = 0; ly < 200; ly += 2) recs.push([40 + ly, [["lbase", FB1 + (199 - ly) * 320], ["hs", 5]]]);
    return recs;
}
function writeList(p, recs) {
    let at = LIST[p];
    const put = (w) => { set32(at, w); at += 4; };
    for (const [y, r] of recs) {
        const words = r.flatMap(([op, v]) => (op === "hs" ? OPS.hs(p) : OPS[op])(v));
        put(HEAD(y, words.length));
        words.forEach(put);
    }
    put(HEAD(511, 0));
    set16(REG_FB_COPPER + 2 * p, (LIST[p] - OFF_VRAM) / 16);
}

// --- the model -------------------------------------------------------------------------------
// One plane's frame, as the rule says: per line its source address, palette entry 0, and whether
// its border pixels show (overscan: FLICK at the magic column opens a band from that row down,
// and the sides of a visible line).
function model(p, recs, brk, hs0, pal0) {
    const ovs = p === 0, stride = ovs ? 400 : 320, rows = ovs ? RH : 200, oy = ovs ? 0 : 40;
    const byLine = new Map(recs);
    let lb = { off: p === 0 ? FB0 : FB1, row: 0 }, hs = hs0, live = true, c0 = pal0, top = false, bot = false;
    if (brk === "reset") lb = { off: ovs ? SRC + 13 : FB1, row: 0 };
    const out = [];
    for (let row = 0; row < rows; row++) {
        const y = oy + row;
        let flick = false;
        for (const [op, v] of (live && byLine.get(y)) || []) {
            if (op === "flick") flick = true;
            else if (op === "lbase") {
                if (v < OFF_VRAM || v >= VRAM_END) { if (brk !== "stop") { live = false; break; } continue; }
                lb = { off: v, row };
            } else if (op === "hs") hs = v;
            else if (op === "pal0") c0 = v;
        }
        const set = lb.row === row && lb.off !== (p === 0 ? FB0 : FB1);
        const base = brk === "persist" && !set ? (ovs ? FB0 : FB1) + row * stride : lb.off + (row - lb.row) * stride;
        const addr = base + (ovs && brk !== "hscroll" ? hs : 0);
        if (ovs && flick && y < 40) top = true;
        if (ovs && flick && y >= 240) bot = true;
        const sides = ovs && flick && y >= 40 && y < 240;
        const band = y < 40 ? top : bot; // this line's value: the flags move on below
        out.push({ y, addr, c0, x0: ovs ? 0 : 40, w: ovs ? 400 : 320,
            open: (x) => !ovs || (y < 40 || y >= 240 ? band : sides || (x >= 40 && x < 360)) });
    }
    return out;
}
const pal = (p, i) => (0xFF000000 | (i << 16) | ((255 - i) << 8) | (p * 64 + (i * 3) % 64)) >>> 0;

// --- the machine --------------------------------------------------------------------------------
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
    writeList(0, records0()), writeList(1, records1());
}
function render(p) {
    const hs0 = r16(REG_HSCROLL + 2 * p);
    const pal0 = dv().getUint32(VIDEO + OFF_PAL + p * 1024, true);
    machine.hwClear(), machine.hwRenderPlane(p);
    const pfb = machine.hwPhysicalPtr(), px = [];
    for (let y = 0; y < RH; y++) for (let x = 0; x < 400; x++) px.push(dv().getUint32(pfb + (y * RW + 2 * x) * 4, true));
    return { px, hs0, pal0 };
}
// The first wrong pixel of plane p's picture against the model, or null.
function compare(p, shot, brk) {
    const lines = model(p, p === 0 ? records0() : records1(), brk, shot.hs0, shot.pal0);
    for (const l of lines) for (let lx = 0; lx < l.w; lx++) {
        const x = l.x0 + lx, i = r8(l.addr + lx);
        const want = !l.open(x) ? BG : i === 0 && p === 0 ? l.c0 : pal(p, i);
        const got = shot.px[l.y * 400 + x];
        if (got !== want) return `plane ${p} line ${l.y} x ${x}: ${hex(got)}, want ${hex(want)}`;
    }
    return null;
}

let failures = 0;
const check = (name, err) => { console.log(`  ${err ? "FAIL" : "ok  "} ${name}${err ? ` — ${err}` : ""}`); failures += !!err; };
check("the machine reports HW 1.10.0 or later", machine.hwVersion() >= 0x00010A00 ? null : `hwVersion ${hex(machine.hwVersion())}`);
setup();
const shots = [render(0), render(0), render(1)];
const runs = (brk) => [compare(0, shots[0], brk), compare(0, shots[1], brk), compare(1, shots[2], brk)];
if (!process.argv.includes("--break")) {
    const [a, b, c] = runs(null);
    check("overscan plane: LBASE, run-on, HSCROLL per line, colour 0, borders, the stop", a);
    check("the second frame starts from FB_BASE again (same picture)", b);
    check("normal plane: LBASE flip, HSCROLL ignored", c);
    console.log(failures ? `linebase_check: ${failures} FAILED` : "linebase_check: all pass");
    process.exit(failures ? 1 : 0);
}
let missed = 0;
for (const brk of ["persist", "hscroll", "stop", "reset"]) {
    const caught = runs(brk).some((e) => e !== null);
    console.log(`  ${caught ? "ok  " : "FAIL"} a model without '${brk}' is caught`);
    missed += !caught;
}
console.log(missed ? `linebase_check --break: ${missed} mutant(s) NOT caught` : "linebase_check --break: every mutant caught");
process.exit(missed ? 1 : 0);
