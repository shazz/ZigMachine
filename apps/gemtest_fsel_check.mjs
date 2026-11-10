// The ITEM SELECTOR as TOS 4's on the GEM 5 engine (rom/gem/desktop/fsel_tree.zig + fsel_draw.zig, G21; Matt's
// GEMTEST on the board, 9 Nov: "still the TOS 1.0 one: TOS 4's has DRIVE buttons, the path as its title"), over
// GEMTEST with C: a copy of docs/gemdos-c.img, in low, medium and the desk, flat and 3D (deskSetEngine(2)):
//   drives   opened on C:\*.*, the A: button re-roots it at A:\*.* and re-lists: the screen is the selector
//            opened on A:\*.* (gemtestShow 30) pixel for pixel; C: back again = the one opened on C:\*.*
//   absent   B: (no such drive: DISABLED) does nothing
//   looks    the selector flat and 3D are two looks; an idle frame draws the same screen
//   cancel   Cancel (TOS 4's place) closes it
//   node apps/gemtest_fsel_check.mjs [--break drive]
//     drive: the drive buttons do nothing (deskSetEngine's mutant bit 25)
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && brk !== "drive") throw new Error(`--break ${brk}: drive`);
const BREAK_NODRIVE = 1 << 25;
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));
const SIZE = [[320, 200], [640, 200], [640, 480]];

async function rig(mode, three_d) {
    const d = await afterDesktop(img, mode);
    d.m.rom.deskSetEngine((three_d ? 2 : 0) | (brk === "drive" ? BREAK_NODRIVE : 0));
    d.frames(3);
    return d;
}
// fsel_tree.zig: the 312 x 178 box centred; drive k at (224 + (k % 2) * 40, 52 + (k / 2) * 13), 32 x 10.
function box(mode) { const [sw, sh] = SIZE[mode]; return [(sw - 312) >> 1, (sh - 178) >> 1]; }
function drive(mode, k) { const [bx, by] = box(mode); return [bx + 224 + (k % 2) * 40 + 16, by + 52 + (k >> 1) * 13 + 5]; }
// The selector's box and its outline, the pointer (the desk's arrow) aside: the window behind shows what the
// program wrote when it opened (Mask A: or C:), so only the box is compared.
const rest = (d) => {
    d.point(2, 190); d.frames(2);
    const { W, H, idx } = d.indices(), [bx, by] = box(d.mode()), out = [];
    for (let y = Math.max(0, by - 4); y < Math.min(H, by + 182); y++) out.push(idx.subarray(y * W + bx - 4, y * W + bx + 316).join());
    return out.join("|");
};

async function opened(mode, three_d, id) {
    const d = await rig(mode, three_d);
    d.show(id);
    return [d, rest(d)];
}

async function sweep(mode, three_d) {
    const tag = `${MODES[mode]} ${three_d ? "3D" : "flat"}`;
    const [, onA] = await opened(mode, three_d, 30);
    const [d, onC] = await opened(mode, three_d, 31);
    check(`${tag}: A:\\*.* and C:\\*.* are two selectors`, onA !== onC);
    d.frames(3);
    check(`${tag}: an idle frame draws the same screen`, rest(d) === onC);
    d.click(...drive(mode, 1));
    check(`${tag}: B: (absent, disabled) does nothing`, rest(d) === onC);
    d.click(...drive(mode, 0));
    check(`${tag}: the A: button re-roots at A:\\*.*, re-listed: = the selector opened there`, rest(d) === onA);
    d.click(...drive(mode, 2));
    check(`${tag}: ...and C: brings back C:\\*.*`, rest(d) === onC);
    const [bx, by] = box(mode);
    d.click(bx + 212, by + 165); // Cancel
    check(`${tag}: Cancel closes it`, [1, 2].every((h) => d.m.rom.fileSelActive(h) !== 1));
    return onC;
}

for (const mode of [0, 1, 2]) {
    const flat = await sweep(mode, false), deep = await sweep(mode, true);
    check(`${MODES[mode]}: the selector flat and 3D are two looks`, flat !== deep);
}

if (brk) {
    console.log(failures ? `\ngemtest_fsel_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_fsel_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_fsel_check: ${failures} FAILED` : "\ngemtest_fsel_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
