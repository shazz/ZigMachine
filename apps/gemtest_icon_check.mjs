// A program's icons and desktop (G16; Matt on the board, 9 Nov: "on the green desktop behind GEMTEST, show
// icons to test behaviours"): GEMTEST's WF_NEWDESK tree (gemtest/desk.zig) of four G_ICONs naming the ROM's
// own icons, drawn by the ROM wherever the desk shows; in low and the desk, every window closed (^K):
//   drawn    each icon inked in its box (the ROM's icon by number)
//   select   a click selects an icon, a second one moves the selection, a click on the empty desk deselects
//            all: the first screen again
//   drag     an icon dragged up lands there (its old box is desk again) and the screen = a whole repaint
//   ghost    while an icon is held off its place, a dotted box (Mode > Drag ghost) sits where it would land,
//            and none once released; Drag ghost off: none while held
//   snap     Mode > Snap to grid: an icon dropped between grid cells lands on the nearest one
//   open     a double-click on an icon opens the Icons area (a window comes up, G_ICONs in it)
//   node apps/gemtest_icon_check.mjs [--break icons]   icons: the ROM's icons lost (deskSetEngine bit 30)
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && brk !== "icons") throw new Error(`--break ${brk}: icons`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));
const SIZE = [[320, 200], [640, 200], [640, 480]];

// desk.zig: icon k at (8 + 80 k, h - 46), 72 x 42.
const box = (mode, k) => [8 + 80 * k, SIZE[mode][1] - 46, 72, 42];
const centre = (mode, k) => { const [x, y, w] = box(mode, k); return [x + (w >> 1), y + 14]; };
function inked(d, [x0, y0, w, h]) {
    const { W, idx } = d.indices();
    let n = 0;
    for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) if (idx[y * W + x] === 0) n++;
    return n;
}

const toggle = (d, k) => d.ctrl(k ? "s" : "g"); // Mode > Drag ghost ^G, Snap to grid ^S

async function run(mode) {
    const tag = MODES[mode];
    const d = await afterDesktop(img, mode);
    d.m.rom.deskSetEngine(brk === "icons" ? 1 << 30 : 0);
    d.frames(3);
    d.ctrl("k"); d.frames(2); // Close windows: the bare desk
    const rest = () => { d.point(SIZE[mode][0] - 20, 40); d.frames(2); return d.plane(); };
    const counts = [0, 1, 2, 3].map((k) => inked(d, box(mode, k)));
    check(`${tag}: the four desk icons are drawn (the ROM's, by number)`, counts.every((n) => n >= 40), counts.join(" "));
    const bare = rest();
    d.click(...centre(mode, 0)); const one = rest();
    d.click(...centre(mode, 1)); const two = rest();
    d.click(SIZE[mode][0] - 40, 60); const none = rest();
    check(`${tag}: a click selects an icon, the next moves the selection, the empty desk deselects all`, one !== bare && two !== one && two !== bare && none === bare);
    const [cx, cy] = centre(mode, 2);
    d.drag(cx, cy, cx, cy - 60);
    rest();
    const old = inked(d, box(mode, 2)), moved = inked(d, [box(mode, 2)[0], box(mode, 2)[1] - 60, 72, 42]);
    check(`${tag}: an icon dragged up lands there, its old place desk again`, old === 0 && moved >= 40, `${old} / ${moved}`);
    const inc = rest(), full = d.repainted();
    check(`${tag}: after the drag the screen = a whole repaint`, inc === full);
    // The ghost: icon 1 held 50 px right of its place, the box there dotted; released, no dots left over.
    const [gx, gy] = centre(mode, 1), [bx1, by1] = box(mode, 1);
    const ghostTop = () => { const { W, idx } = d.indices(); let n = 0; for (let x = bx1 + 50; x < bx1 + 50 + 72; x++) if (idx[by1 * W + x] === 0) n++; return n; };
    d.point(gx, gy, 0); d.point(gx, gy, 1); d.point(gx + 25, gy, 1); d.point(gx + 50, gy, 1); d.frames(1);
    const held = ghostTop();
    d.point(gx, gy, 1); d.point(gx, gy, 0); d.frames(2); // back where it was: no move
    check(`${tag}: a held icon shows its dotted ghost where it would land, gone on release`, held >= 30 && ghostTop() === 0, `${held} / ${ghostTop()}`);
    toggle(d, 0);
    d.point(gx, gy, 0); d.point(gx, gy, 1); d.point(gx + 25, gy, 1); d.point(gx + 50, gy, 1); d.frames(1);
    const off = ghostTop();
    d.point(gx, gy, 1); d.point(gx, gy, 0); d.frames(2);
    check(`${tag}: Drag ghost off (^G): no ghost while held`, off === 0, `${off}`);
    toggle(d, 0);
    // Snap: icon 0 dropped 30 px right and 10 up lands back on its cell (80 px columns, the bottom row).
    const [sx, sy] = centre(mode, 0), [b0x, b0y] = box(mode, 0), right = () => inked(d, [b0x + 72, b0y - 10, 8, 52]); // the gap before icon 1
    toggle(d, 1); d.drag(sx, sy, sx + 30, sy - 10); rest();
    check(`${tag}: Snap to grid: dropped between cells, the icon lands on the nearest one`, inked(d, box(mode, 0)) >= 40 && right() === 0, `${right()}`);
    toggle(d, 1);
    d.drag(sx, sy, sx + 30, sy - 10); rest();
    check(`${tag}: free move: the icon lands where it was dropped`, right() >= 4, `${right()}`);
    d.point(...centre(mode, 0), 0); d.point(...centre(mode, 0), 2); d.frames(3); // the page's double-click pulse
    check(`${tag}: a double-click on an icon opens the Icons area`, d.top() === 1, `top ${d.top()}`);
}

for (const mode of [0, 2]) await run(mode);
if (brk) {
    console.log(failures ? `\ngemtest_icon_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_icon_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_icon_check: ${failures} FAILED` : "\ngemtest_icon_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
