// A PROGRAM's form_alert on the GEM 5 engine (rom/gem/gui/alert_obj.zig, docs/GEMTEST.md; Matt's GEMTEST
// findings on the board, 9 Nov: G19 the icons, G18 the malformed string), over GEMTEST, in low, medium and
// the desk, in both looks (flat TOS 1, and TOS 4's 3D rules asked for with deskSetEngine(2), the built-in
// art: the gate has no local asset set):
//   icons    form_alert icons 0, 1, 2, 3 with one button: four different screens (each its own art)
//   looks    the same alert flat and 3D: two different screens
//   layout   TOS 4's: the second of two buttons where the layout puts it (a cell apart, the row centred under
//            the icon and lines): a click there answers 2; Return answers 1 (the default); each closes it
//   idle     an alert left up: the next frames draw the same screen
//   malformed  the Alerts menu's Malformed alert picked over the Windows area opens nothing, and the Alerts
//            window comes up with the answer
//   node apps/gemtest_alert_check.mjs [--break icon]
//     icon: the ROM loses the icon art (deskSetEngine's mutant bit 24): the icon boxes are blank
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && brk !== "icon") throw new Error(`--break ${brk}: icon`);
const BREAK_NOICON = 1 << 24;
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));
const SIZE = [[320, 200], [640, 200], [640, 480]];

async function rig(mode, three_d) {
    const d = await afterDesktop(img, mode);
    d.m.rom.deskSetEngine((three_d ? 2 : 0) | (brk === "icon" ? BREAK_NOICON : 0));
    d.frames(3);
    return d;
}

// gemtestShow 17: icon 2, buttons Yes|No, three lines (flow.zig SPECS); its second button by TOS 4's layout.
function secondButton(mode) {
    const [sw, sh] = SIZE[mode], cw = 8, ch = 8;
    const widest = "with 2 button(s), the first".length, tx = 2 * cw + 32;
    const by = Math.max(3 + 3 * ch, ch + 32) + 4, bw = (3 + 2) * cw, bh = ch + 6, row = 2 * bw + cw;
    const w = Math.min(Math.max(tx + widest * cw + 2 * cw, row + 4 * cw), sw - 18), h = by + bh + ch; // the box inside its 5-px rim
    const x = ((sw - w) >> 1) + ((w - row) >> 1) + bw + cw, y = ((sh - h) >> 1) + by;
    return [x + (bw >> 1), y + (bh >> 1)];
}

// The icon's 32 x 32 box of gemtestShow 13 / 16 / 19 (icon 1..3, one button, a 27-cell widest line):
// a cell in from the box's top-left. Its pixels, and how many are black (the ROM's palette 0).
function iconBox(d, mode) {
    const [sw, sh] = SIZE[mode], w = 48 + 27 * 8 + 16, h = 44 + 14 + 8;
    const x0 = ((sw - w) >> 1) + 8, y0 = ((sh - h) >> 1) + 8, { W, idx } = d.indices();
    const px = [];
    for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) px.push(idx[(y0 + y) * W + x0 + x]);
    return { key: px.join(), black: px.filter((v) => v === 0).length };
}

async function sweep(mode, three_d) {
    const tag = `${MODES[mode]} ${three_d ? "3D" : "flat"}`;
    const d = await rig(mode, three_d), seen = [], art = [];
    for (const id of [10, 13, 16, 19]) {
        d.show(id); seen.push(d.plane());
        if (id !== 10) art.push(iconBox(d, mode));
        d.key(13); d.frames(2);
    }
    check(`${tag}: icons 0 1 2 3 draw four different alerts`, new Set(seen).size === 4, `${new Set(seen).size}`);
    const inked = art.every((a) => a.black >= 60);
    check(`${tag}: icons 1 2 3 each draw their own art in the icon's box`, inked && new Set(art.map((a) => a.key)).size === 3, art.map((a) => a.black).join(" "));
    d.show(17);
    const up = d.plane(); d.frames(4);
    check(`${tag}: an alert left up draws the same screen`, d.plane() === up);
    const rest = () => { d.point(4, 190); d.frames(2); return d.plane(); }; // the pointer (the desk's arrow) out of the way
    d.click(...secondButton(mode));
    const by_click = rest();
    d.show(17);
    const open = rest();
    check(`${tag}: a click on the second button (TOS 4's layout) closes it`, by_click !== open);
    d.key(13);
    const by_return = rest();
    check(`${tag}: Return (the default, 1) closes it with another answer`, by_return !== by_click && by_return !== open);
    return seen[1];
}

for (const mode of [0, 1, 2]) {
    const flat = await sweep(mode, false), deep = await sweep(mode, true);
    check(`${MODES[mode]}: the note alert flat and 3D are two looks`, flat !== deep);
    const m = await rig(mode, false);
    m.ctrl("w");
    const w = m.plane();
    m.point(170, 4); m.frames(2); m.click(180, 11 + 12 * 8 + 4); m.frames(2); // Alerts > Malformed alert
    check(`${MODES[mode]}: Alerts > Malformed alert over the Windows area opens nothing, the Alerts window says so`, m.plane() !== w && m.top() === 1, `top ${m.top()}`);
}

if (brk) {
    console.log(failures ? `\ngemtest_alert_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_alert_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_alert_check: ${failures} FAILED` : "\ngemtest_alert_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
