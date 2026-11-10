// The desktop's own windows sized as TOS sizes them (G22, G23; Matt on the board, 9 Nov), in LOW, MEDIUM and
// the desk (the old path; the engine shares the Wm): A:\ opened, its size box dragged
//   clamp    past the screen's bottom-right corner: the window ends AT the edge, its frame is the screen's last
//            column and row (G22: in low it grew past the screen)
//   minimum  far up-left: it stops where every gadget fits (its own floor: an icon cell, above TOS's gadget
//            minimum; a vertical track of at least one gadget)
//   node apps/gem_desk_size_check.mjs [--break clamp]   (deskSetEngine's bit 27, gui/winsize.zig; a desktop window's
//   own floor (an icon cell) is above the old 44 px, so the min mutant shows on program windows only)
import { bootGem } from "./gem_headless.mjs";
import { res, settle, pickRes, fbBase, bufferAt } from "./gem_desk_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
const BRK = { clamp: 1 << 27 };
if (brk && !(brk in BRK)) throw new Error(`--break ${brk}: clamp`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const MODES = { low: [320, 200], medium: [640, 200], desk: [640, 480] };
const FLOPPY = [35, 40], R = { x: 24, y: 24, w: 200, h: 120 };
const DISK = Array.from({ length: 6 }, (_, i) => ({ name: `FILE${i}.DAT`, type: 1, size: 1000, date: 20260912 }));

const host = (gem, x, y) => [res(gem) === 0 ? 2 * x : x, y];
// Is the desktop's pixel (x, y) black? The desk's buffer is indices, a plane mode is rendered (black = 0).
function blackAt(gem, sw, sh) {
    if (sh === 480) { const b = bufferAt(gem, fbBase(gem)); return (x, y) => b[y * 640 + x] === 0; }
    gem.machine.hwRenderPlane(0);
    const p = new Uint8Array(gem.memory.buffer, gem.machine.hwPhysicalPtr(), gem.w * gem.h * 4), k = 640 / sw;
    return (x, y) => { const s = ((y + gem.by) * gem.w + k * x + gem.bx) * 4; return p[s] + p[s + 1] + p[s + 2] === 0; };
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
}

for (const mode of Object.keys(MODES)) await run(mode);
if (brk) {
    console.log(failures ? `\ngem_desk_size_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngem_desk_size_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngem_desk_size_check: ${failures} FAILED` : "\ngem_desk_size_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
