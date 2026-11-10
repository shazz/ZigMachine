// A program's OBJECT TREE on the GEM 5 engine (G20, rom.aes.obj: objc_draw / objc_find / form_button /
// objc_change / objc_edit), over GEMTEST's Dialogs area (gemtest/dlg_tree.zig), in the desk, flat and 3D:
//   radio    Medium pressed: the group changes; pressed again it stays (RBUTTON); Low brings the first look back
//   check    a check box pressed twice: back as it was (SELECTABLE)
//   disabled the DISABLED button pressed: nothing changes
//   field    the G_FBOXTEXT focused, digits type (objc_edit), letters do not (validation 9), Backspace rubs out
//   slider   a press on the track moves the knob there
//   looks    the area flat and 3D are two looks
//   menu     the Test menu's shortcuts are a right-aligned column (a TAB in the label), in low
//   node apps/gemtest_obj_check.mjs [--break radio]   radio: form_button toggles an RBUTTON (bit 29)
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && brk !== "radio") throw new Error(`--break ${brk}: radio`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));

async function rig(mode, three_d) {
    const d = await afterDesktop(img, mode);
    d.m.rom.deskSetEngine((three_d ? 2 : 0) | (brk === "radio" ? 1 << 29 : 0));
    d.frames(3);
    return d;
}

// area_dialogs.zig's layout, content pixels from the work area's corner (unscrolled).
const AT = { medium: [80, 57], low: [24, 57], high: [140, 57], check: [13, 85], disabled: [200, 19], field: [96, 112], track: [8 + 8 * 8 + 3, 139] };

async function dialogs(three_d) {
    const tag = three_d ? "3D" : "flat";
    const d = await rig(2, three_d);
    d.ctrl("d");
    const at = (k) => [d.win(1, 0) + AT[k][0], d.win(1, 1) + AT[k][1]];
    const shot = () => { d.point(4, 470); d.frames(2); return d.plane(); };
    const press = (k) => { d.click(...at(k)); return shot(); };
    const start = shot();
    const med = press("medium");
    check(`${tag}: Medium pressed: the radio group changes`, med !== start);
    check(`${tag}: Medium pressed again: it stays on (RBUTTON)`, press("medium") === med);
    check(`${tag}: Low pressed: the first look is back`, press("low") === start);
    const on = press("check");
    check(`${tag}: a check box pressed twice is back (SELECTABLE)`, on !== start && press("check") === start);
    check(`${tag}: the DISABLED button pressed: nothing changes`, press("disabled") === start);
    const focused = press("field");
    d.type("09"); const typed = shot();
    d.type("ab"); const refused = shot();
    check(`${tag}: digits type into the G_FBOXTEXT, letters are refused`, typed !== focused && refused === typed);
    d.key(8);
    check(`${tag}: Backspace rubs one out`, shot() !== typed);
    const before = shot();
    check(`${tag}: a press on the slider's track moves the knob`, press("track") !== before);
    return start;
}

// The rightmost ink of a drop-down row, left of the drop-down's frame: where its shortcut ends.
function shortcutEnd(d, y) {
    const { W, idx } = d.indices();
    const line = (x) => { for (let yy = 12; yy < 80; yy++) if (idx[yy * W + x] !== 0) return false; return true; };
    let x = 50;
    while (x < W - 1 && !line(x)) x++; // the drop-down's right frame: a black column all the way down
    x--;
    while (x > 0 && idx[y * W + x] !== 0) x--; // the white margin left of it
    return x;
}
async function menu() {
    const d = await rig(0, false);
    d.point(64, 4); d.frames(2); // the Test title drops
    const ends = [0, 4, 7].map((row) => Math.floor(Math.max(...[1, 2, 3, 4, 5, 6].map((k) => shortcutEnd(d, 11 + row * 8 + k))) / 8)); // the cell each ends in
    check("low: the Test menu's shortcuts end in one column (right-aligned)", ends[0] === ends[1] && ends[1] === ends[2] && ends[0] > 12, ends.join(","));
}

const flat = await dialogs(false), deep = await dialogs(true);
check("the Dialogs area flat and 3D are two looks", flat !== deep);
await menu();

if (brk) {
    console.log(failures ? `\ngemtest_obj_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_obj_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_obj_check: ${failures} FAILED` : "\ngemtest_obj_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
