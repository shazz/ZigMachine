// The ITEM SELECTOR as TOS 4's on the GEM 5 engine (rom/gem/desktop/fsel_tree.zig + fsel_draw.zig, G21; Matt's
// GEMTEST on the board, 9 Nov: "still the TOS 1.0 one: TOS 4's has DRIVE buttons, the path as its title"), over
// GEMTEST with C: a copy of docs/gemdos-c.img, in low, medium and the desk, flat and 3D (deskSetEngine(2)):
//   drives   opened on C:\*.*, the A: button re-roots it at A:\*.* and re-lists: the screen is the selector
//            opened on A:\*.* (gemtestShow 30) pixel for pixel; C: back again = the one opened on C:\*.*
//   absent   B: (no such drive: DISABLED) does nothing
//   looks    the selector flat and 3D are two looks; an idle frame draws the same screen
//   cancel   Cancel (TOS 4's place) closes it
//   still    an idle frame does not draw the box again (the board showed every repaint half drawn: a flash,
//            Matt 10 Nov), and a program painting over the box gets it drawn again
//   node apps/gemtest_fsel_check.mjs [--break drive]
//     drive: the drive buttons do nothing (deskSetEngine's mutant bit 25)
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";
import { fselGeom } from "./fsel_geom.mjs";
import { layout } from "./fsel_layout.mjs";

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
// fsel_geom.zig's layout (apps/fsel_geom.mjs): the box centred, the drive buttons, Cancel.
const geom = (mode) => fselGeom(...SIZE[mode]);
function box(mode) { const b = geom(mode).box; return [b.x, b.y]; }
function drive(mode, k) { const g = geom(mode); return g.mid(g.drive(k)); }
// The selector's box and its outline, the pointer (the desk's arrow) aside: the window behind shows what the
// program wrote when it opened (Mask A: or C:), so only the box is compared.
const rest = (d) => {
    d.point(2, 190); d.frames(2);
    const { W, H, idx } = d.indices(), b = geom(d.mode()).box, out = [];
    // the box and its 3-px outline (one more pixel is the window behind, which the program rewrites)
    for (let y = Math.max(0, b.y - 3); y < Math.min(H, b.y + b.h + 3); y++) out.push(idx.subarray(y * W + b.x - 3, y * W + b.x + b.w + 3).join());
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
    const g = geom(mode);
    d.click(...g.mid(g.cancel)); // Cancel
    check(`${tag}: Cancel closes it`, [1, 2].every((h) => d.m.rom.fileSelActive(h) !== 1));
    return onC;
}

// A pixel of video memory, in the program's coordinates.
function poke(d, x, y, f) {
    const v = new DataView(d.m.memory.buffer, d.m.machine.hwVideoBase()), r = d.res();
    const st = r === 3 ? 640 : v.getUint16(0x34, true), a = d.m.machine.hwVideoBase() + v.getUint32(0x44, true) + y * st + x;
    const u = new Uint8Array(d.m.memory.buffer);
    u[a] = f(u[a]);
}
async function still(mode) {
    const [d] = await opened(mode, false, 31), [bx, by] = box(mode), { W } = d.indices();
    const at = (by + 100) * W + bx + 100, was = d.indices().idx[at];
    poke(d, bx + 100, by + 100, (p) => p ^ 5);
    d.frames(2);
    check(`${MODES[mode]}: an idle frame leaves the box alone (no repaint)`, d.indices().idx[at] === (was ^ 5));
    const b = geom(mode).box;
    for (let y = by - 4; y < by + b.h + 6; y++) for (let x = bx - 4; x < bx + b.w + 6; x++) poke(d, x, y, () => (x ^ y) & 1);
    d.frames(2);
    check(`${MODES[mode]}: painted over, the box is drawn again`, d.indices().idx[at] === was);
}

for (const mode of [0, 1, 2]) await still(mode);
for (const mode of [0, 1, 2]) await layout(mode, await opened(mode, false, 31), "C:\\*.*", check);
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
