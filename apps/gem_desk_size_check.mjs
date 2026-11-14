// The desktop's own windows sized as TOS sizes them (G22, G23; Matt on the board, 9 Nov), in LOW, MEDIUM and
// the desk (the old path; the engine shares the Wm): A:\ opened, its size box dragged
//   clamp    past the screen's bottom-right corner: the window ends AT the edge, its frame is the screen's last
//            column and row (G22: in low it grew past the screen)
//   minimum  far up-left: it stops where every gadget fits (its own floor: an icon cell, above TOS's gadget
//            minimum; a vertical track of at least one gadget), and its first row of icons shows WHOLE, names
//            too, pixel for pixel as in the tall window (Matt, 13 Nov: one icon cell dropped the names in low
//            and medium and cut them in half in the desk: a window's icon row starts 4 px down)
//   names    the files have 8.3 names of 12 characters (ZIGPLASM.GIF): two side by side in the first row are
//            two names, a gap between them (Matt on the board, 14 Nov, SHOT0017: "ZIGPLASM.GIFZIGPLASM.NEO", a
//            12-character name is 72 px, the window's column was the desktop's 72 px cell)
//   cut      the window sized so its second row's icons fit but not their names: nothing of that row is drawn
//            (Matt, SHOT0017: the icons were drawn, their names cut off at the bottom edge)
//   node apps/gem_desk_size_check.mjs [--break clamp|minrow|names|cut]   (deskSetEngine's bit 27,
//   gui/winsize.zig; bits 21, 22, 23, desktop/deskbreak.zig: the minimum one icon cell again, the 72 px
//   column, the cut row drawn. A desktop window's own floor is above the old 44 px, so winsize's min mutant
//   shows on program windows only)
import { bootGem } from "./gem_headless.mjs";
import { res, settle, pickRes, fbBase, bufferAt } from "./gem_desk_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
const BRK = { clamp: 1 << 27, minrow: 1 << 21, names: 1 << 22, cut: 1 << 23 }; // gui/winsize.zig BREAK_NOCLAMP, desktop/deskbreak.zig MIN_ROW, NAME_COL, ROW_CUT
if (brk && !(brk in BRK)) throw new Error(`--break ${brk}: clamp, minrow, names or cut`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const MODES = { low: [320, 200], medium: [640, 200], desk: [640, 480] };
const FLOPPY = [35, 40], R = { x: 24, y: 24, w: 200, h: 120 };
const NAMES = ["ZIGPLASM.GIF", "ZIGPLASM.NEO", "ZIGPLASM.PI1", "ZIGWAVES.GIF", "ZIGWAVES.NEO", "ZIGWAVES.PI1"]; // demo-grafx2's
const DISK = NAMES.map((name) => ({ name, type: 1, size: 1000, date: 20260912 }));

const host = (gem, x, y) => [res(gem) === 0 ? 2 * x : x, y];
// Is the desktop's pixel (x, y) black? The desk's buffer is indices, a plane mode is rendered (black = 0).
function blackAt(gem, sw, sh) {
    if (sh === 480) { const b = bufferAt(gem, fbBase(gem)); return (x, y) => b[y * 640 + x] === 0; }
    gem.machine.hwRenderPlane(0);
    const p = new Uint8Array(gem.memory.buffer, gem.machine.hwPhysicalPtr(), gem.w * gem.h * 4), k = 640 / sw;
    return (x, y) => { const s = ((y + gem.by) * gem.w + k * x + gem.bx) * 4; return p[s] + p[s + 1] + p[s + 2] === 0; };
}

// The window's height down its left frame, and its work area's: from TOP to the horizontal scroll bar's top
// line (the first row black across the work area's first 40 columns).
function heights(black, x, y, sh) {
    let h = 0;
    while (y + h < sh && black(x, y + h)) h++;
    let c = TOP;
    const line = (yy) => { for (let xx = x + 1; xx < x + 41; xx++) if (!black(xx, yy)) return false; return true; };
    while (c < h && !line(y + c)) c++;
    return { h, c: c - TOP };
}

// Matt's SHOT0017 (board, 14 Nov, A:\ of demo-grafx2 in low): 12-character names ran together, and a second
// row's icons were drawn with their names cut off at the window's bottom edge.
async function names(mode) {
    const [sw, sh] = MODES[mode];
    const gem = await bootGem();
    gem.mount(DISK);
    const click = (x, y) => gem.click(...host(gem, x, y));
    if (mode !== "low") pickRes(gem, click, "medium", 320, 200);
    if (mode === "desk") pickRes(gem, click, "desk", 640, 200);
    gem.rom.deskSetEngine(brk ? BRK[brk] : 0);
    gem.open(...host(gem, ...FLOPPY));
    settle(gem, 12);
    const x = sw === 320 ? 2 : R.x, y = R.y, from = sw === 320 ? 316 : 320;
    const drag = (a, b) => { gem.drag(...host(gem, ...a), ...host(gem, ...b), 8); settle(gem, 6); };
    drag([x + from - 6, y + R.h - 5], [x + R.w - 6, y + R.h - 5]);
    const tall = firstRow(blackAt(gem, sw, sh), x, y);
    const runs = nameRuns(blackAt(gem, sw, sh), x, y, tall.rows, R.w - 14);
    check(`${mode}: the first row's two 12-character names are two names, apart (not "ZIGPLASM.GIFZIGPLASM.NEO")`,
        runs.length === 2, JSON.stringify(runs));
    // The second row's icons fit but not their names: 10 px short of two whole rows (a row = its names' last
    // row + 1, the second 4 px shorter: the grid's top margin is the first row's only).
    const want = 2 * (tall.rows + 1) - 4 - 10, at = heights(blackAt(gem, sw, sh), x, y, sh);
    drag([x + R.w - 6, y + at.h - 5], [x + R.w - 6, y + at.h - 5 + want - at.c]);
    const now = heights(blackAt(gem, sw, sh), x, y, sh), below = inkBelow(blackAt(gem, sw, sh), x, y, tall.rows, R.w - 14);
    check(`${mode}: sized so the second row's icons fit but not their names (work area ${want} px)`, now.c === want, JSON.stringify({ at, now }));
    check(`${mode}: ...that row is not drawn (no icons with their names cut off)`, below.ink === 0, JSON.stringify(below));
}

async function run(mode) {
    const [sw, sh] = MODES[mode];
    const gem = await bootGem();
    gem.mount(DISK);
    const click = (x, y) => gem.click(...host(gem, x, y));
    if (mode !== "low") pickRes(gem, click, "medium", 320, 200);
    if (mode === "desk") pickRes(gem, click, "desk", 640, 200);
    gem.rom.deskSetEngine(brk ? BRK[brk] : 0);
    gem.open(...host(gem, ...FLOPPY));
    settle(gem, 12);
    const x = sw === 320 ? 2 : R.x, y = R.y, from = sw === 320 ? 316 : 320; // low: A:\ opened clamped
    const drag = (a, b) => { gem.drag(...host(gem, ...a), ...host(gem, ...b), 8); settle(gem, 6); };
    drag([x + from - 6, y + R.h - 5], [x + R.w - 6, y + R.h - 5]); // to R's size first (gem_desk_bugs_check's)
    const tall = firstRow(blackAt(gem, sw, sh), x, y); // the first icon row with its names, at R's size
    drag([x + R.w - 6, y + R.h - 5], [sw + 40, sh + 40]); // past the corner
    let black = blackAt(gem, sw, sh), col = true, row = true;
    for (let yy = y + 30; yy < sh - 30; yy++) col &&= black(sw - 1, yy);
    for (let xx = x + 30; xx < sw - 30; xx++) row &&= black(xx, sh - 1);
    check(`${mode}: sized past the corner, its frame is the screen's last column and row (G22)`, col && row);
    drag([sw - 6, sh - 5], [x + 2, y + 2]); // far up-left
    black = blackAt(gem, sw, sh);
    let h = 0; // the left frame, down from the title bar: the window's height
    while (y + h < sh && black(x, y + h)) h++;
    const track = h - 21 - 3 * 11 + 2; // title + info line; up, down and the sizer share frame lines
    check(`${mode}: sized far up-left, it stops where every gadget fits: a track >= one gadget (G23)`, track >= 11, `${h} px high`);
    // Matt, 13 Nov: at the minimum the names under the icons were dropped (low, medium) or cut in half (the desk).
    const small = firstRow(black, x, y, tall.rows);
    check(`${mode}: at its minimum, the first icon row shows whole, its names too (= the tall window's ${tall.rows} rows)`,
        tall.rows > 0 && small.bits === tall.bits, `${h} px high`);
}

// The first icon cell of the window at (x, y), from the top of its work area (under the title and info
// lines) to the last row of the first icon's name (`rows`; else found: the end of the second run of ink,
// the icon's art being the first, its name the second).
const CELL_W = 72, TOP = 21;
function firstRow(black, x, y, rows = 0) {
    let bits = "", runs = 0, inRun = false, n = 0;
    for (; rows ? n < rows : n < 120; n++) {
        let line = "";
        for (let xx = x + 1; xx < x + 1 + CELL_W; xx++) line += black(xx, y + TOP + n) ? "1" : "0";
        const ink = line.includes("1");
        if (!rows && inRun && !ink && runs === 2) return { bits, rows: n };
        bits += line;
        if (ink && !inRun) runs++;
        inRun = ink;
    }
    return { bits, rows: rows ? n : 0 };
}

// The names of the first row, as runs of ink across the width `w` over the name's glyph rows (the last 6 of
// `rows`): a gap of NAME_GAP blank columns or more parts two names (a name's own glyphs are closer).
const NAME_GAP = 4;
function nameRuns(black, x, y, rows, w) {
    const runs = [];
    let gap = NAME_GAP, start = -1;
    for (let xx = x + 1; xx < x + 1 + w; xx++) {
        let ink = false;
        for (let r = rows - 6; r < rows; r++) ink ||= black(xx, y + TOP + r);
        if (ink) { if (gap >= NAME_GAP) runs.push([xx - x, xx - x]); runs.at(-1)[1] = xx - x; gap = 0; } else gap++;
        if (start < 0 && ink) start = xx;
    }
    return runs;
}
// Ink in the work area under the first row (from its names' last row + 2) down to the horizontal scroll
// bar's top line (the first row black across the work area's first 40 columns).
function inkBelow(black, x, y, rows, w) {
    let ink = 0, yy = y + TOP + rows + 2;
    const frame = (yy) => { for (let xx = x + 1; xx < x + 41; xx++) if (!black(xx, yy)) return false; return true; };
    for (; yy < y + 200 && !frame(yy); yy++) for (let xx = x + 1; xx < x + 1 + w; xx++) ink += black(xx, yy);
    return { ink, rows: yy - (y + TOP + rows + 2) };
}

for (const mode of Object.keys(MODES)) { if (brk !== "names" && brk !== "cut") await run(mode); await names(mode); }
if (brk) {
    console.log(failures ? `\ngem_desk_size_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngem_desk_size_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngem_desk_size_check: ${failures} FAILED` : "\ngem_desk_size_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
