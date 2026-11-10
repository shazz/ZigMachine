// A program's window redraws (Matt's GEMTEST on the board, 9 Nov): G17 a move or a top flashed the screen
// (every window repainted back to front, unclipped), G22 in low res the sizer let a window grow past the
// screen, G23 a window sized to its minimum left vertical line artefacts. Over GEMTEST's Windows area (four
// windows, the back one larger than the screen), in low, medium and the desk:
//   redraw   GADGETS topped, then moved, then closed: a pixel of the desk and one of another window far from
//            it are poisoned first and must survive (only the ROM's WM_REDRAW rectangles were redrawn, clipped);
//            the screen then equals a whole repaint (nothing stale)
//   clamp    its sizer dragged past the screen's bottom-right corner: it ends at the screen's edge
//   minimum  its sizer dragged far up-left: it stops at the size that holds every gadget (the track at least
//            one gadget cell), and the screen equals a whole repaint
//   node apps/gemtest_redraw_check.mjs [--break whole|clamp|min]
//     whole: every redraw list is the whole window (bit 26); clamp: no edge clamp (bit 27); min: the old
//     44-px minimum (bit 28)
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
const BREAKS = { whole: 1 << 26, clamp: 1 << 27, min: 1 << 28 };
if (brk && !(brk in BREAKS)) throw new Error(`--break ${brk}: whole, clamp or min`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));
const SIZE = [[320, 200], [640, 200], [640, 480]];
const G = 2; // GADGETS (gemtest_check's): window 1 is the larger-than-the-screen one, at the back
const GH = 11, TOP = 11 + 10; // the gadget height, the title bar + info line (gem_glyphs.zig, types.zig)

async function rig(mode) {
    const d = await afterDesktop(img, mode);
    d.m.rom.deskSetEngine(brk ? BREAKS[brk] : 0);
    d.frames(3);
    return d;
}
function poke(d, x, y, v) {
    const vd = new DataView(d.m.memory.buffer, d.m.machine.hwVideoBase());
    const base = vd.getUint32(0x44, true), stride = d.res() === 3 ? 640 : vd.getUint16(0x34, true);
    const at = d.m.machine.hwVideoBase() + base + y * stride + x;
    const px = new Uint8Array(d.m.memory.buffer, at, 1);
    if (v !== undefined) px[0] = v;
    return px[0];
}
const POISON = 77;
// The desk's left strip (x < 8: no window), and the back window far right and low (off GADGETS's way).
const spots = (mode) => [[3, 100], [SIZE[mode][0] - 12, SIZE[mode][1] - 14]];
// The screen as drawn against a whole repaint: "" when equal, else the bounding box of the difference.
function stale(d) {
    const inc = d.indices().idx.slice(), W = d.indices().W;
    d.repainted();
    const full = d.indices().idx;
    let x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1;
    for (let i = 0; i < inc.length; i++) if (inc[i] !== full[i]) {
        const x = i % W, y = (i / W) | 0;
        x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
    }
    return x1 < 0 ? "" : `${x0},${y0}..${x1},${y1}`;
}
function poisoned(d, mode, what, act) {
    const was = spots(mode).map(([x, y]) => poke(d, x, y));
    for (const [x, y] of spots(mode)) poke(d, x, y, POISON);
    act();
    const kept = spots(mode).every(([x, y]) => poke(d, x, y) === POISON);
    check(`${MODES[mode]}: ${what}: only the WM_REDRAW rectangles were redrawn (the desk and the back window kept)`, kept);
    spots(mode).forEach(([x, y], k) => poke(d, x, y, was[k]));
    const s = stale(d);
    check(`${MODES[mode]}: ${what}: the screen then = a whole repaint`, s === "", s);
}

async function redraws(mode) {
    const d = await rig(mode);
    const title = () => [d.win(G, 4) + 30, d.win(G, 5) + 5];
    poisoned(d, mode, "GADGETS topped", () => d.click(...title()));
    const [x, y] = title();
    poisoned(d, mode, "GADGETS moved", () => d.drag(x, y, x + 24, y + 16));
    poisoned(d, mode, "GADGETS closed", () => d.click(d.win(G, 4) + 5, d.win(G, 5) + 5));
}

async function sizes(mode) {
    const [sw, sh] = SIZE[mode];
    const d = await rig(mode);
    d.click(d.win(G, 4) + 30, d.win(G, 5) + 5); // on top
    const corner = () => [d.win(G, 4) + d.win(G, 6) - 4, d.win(G, 5) + d.win(G, 7) - 4];
    d.drag(...corner(), sw + 60, sh + 60);
    const right = d.win(G, 4) + d.win(G, 6), bottom = d.win(G, 5) + d.win(G, 7);
    check(`${MODES[mode]}: sized past the corner, it stops at the screen's edge (G22)`, right <= sw && bottom <= sh && right > sw - 8, `${right},${bottom}`);
    d.drag(...corner(), d.win(G, 4) + 2, d.win(G, 5) + 2);
    const w = d.win(G, 6), h = d.win(G, 7);
    const track = h - TOP - 3 * GH + 2;
    check(`${MODES[mode]}: sized far up-left, it stops where every gadget fits, a track >= one gadget (G23)`, track >= GH && w >= 4 * 12 - 3 && w % 8 === 0, `${w}x${h}`);
    const s0 = stale(d);
    check(`${MODES[mode]}: at its minimum the screen = a whole repaint (no leftover lines)`, s0 === "", s0);
    d.drag(...corner(), d.win(G, 4) + 200, d.win(G, 5) + 120);
    d.drag(...corner(), d.win(G, 4) + 2, d.win(G, 5) + 2);
    const s1 = stale(d);
    check(`${MODES[mode]}: larger and back to the minimum: still = a whole repaint`, s1 === "", s1);
}

for (const mode of [0, 1, 2]) {
    await redraws(mode);
    await sizes(mode);
}

if (brk) {
    console.log(failures ? `\ngemtest_redraw_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_redraw_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_redraw_check: ${failures} FAILED` : "\ngemtest_redraw_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
