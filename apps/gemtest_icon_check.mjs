// A program's icons and desktop (G16; Matt on the board, 9 Nov: "on the green desktop behind GEMTEST, show
// icons to test behaviours"): GEMTEST's WF_NEWDESK tree (gemtest/desk.zig) of four G_ICONs naming the ROM's
// own icons, drawn by the ROM wherever the desk shows; in low and the desk, every window closed (^K):
//   drawn    each icon inked in its box (the ROM's icon by number)
//   select   a click selects an icon, a second one moves the selection, a click on the empty desk deselects
//            all: the first screen again
//   drag     an icon dragged up lands there (its old box is desk again) and the screen = a whole repaint
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
