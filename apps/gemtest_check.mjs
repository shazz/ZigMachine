// GEMTEST (apps/zig/scenes/gemtest.zig, docs/GEMTEST.md) end to end, over the real machine + ROM, C: a
// copy of docs/gemdos-c.img:
//   launch   GEM boots over demo-gemtest.zmd, BOOT.WSM is the committed cart; it opens in GEM's low res
//            with the Windows area: four ROM windows, the fourth on top and larger than the screen
//   areas    each area's ^key (W E D A F T I R) shows its window: drawn (>= 3 colours), a hash of its own,
//            the same hash in a second run (deterministic), an idle frame paints nothing, and the screen
//            as drawn equals a whole repaint; in low, medium and the desk
//   windows  a click on a lower window tops it (WF_TOP), its title dragged moves it, the sizer resizes
//            it, the down arrow scrolls it, the closer closes it (the next one is on top)
//   menus    ^L (the Menus title's shortcut) and the Checked item picked off the bar change the window;
//            picked twice it is back; the disabled ^U does nothing
//   dialogs  OK, a radio button, a check box (twice: back), the field's digits, Return, the slider
//   alerts   form_alert opens over the Alerts area, Return closes it and the answer shows; the
//            malformed string opens nothing
//   files    the ITEM SELECTOR on A:\*.* and C:\*.* (different lists), Cancel closes it
//   quit     ^Q: back to the desktop (request 4)
//   node apps/gemtest_check.mjs [--break ctrl|click]
//     ctrl: Control never sent (^W types a w); click: the pointer not mapped to low res (x not doubled)
import { readFile } from "node:fs/promises";
import { fromGem, afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && !["ctrl", "click"].includes(brk)) throw new Error(`--break ${brk}: ctrl or click`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));
const AREAS = [["windows", "w"], ["menus", "e"], ["dialogs", "d"], ["alerts", "a"], ["files", "f"], ["text", "t"], ["icons", "i"], ["modes", "r"]];

async function rig(mode) {
    const d = await afterDesktop(img, mode, brk);
    if (brk === "click") { const p = d.point; d.point = (x, y, b = 0) => { d.m.demo.pointer(x, y, b); d.frames(1); }; d.unused = p; }
    d.frames(3);
    return d;
}
function same(d, what) {
    const inc = d.plane(), full = d.repainted();
    check(`${what}: the screen as drawn = a whole repaint`, inc === full);
}
const colours = (d) => new Set(d.indices().idx).size;

console.log(`gemtest_check: GEMTEST off docs/demo-gemtest.zmd${brk ? ` (--break ${brk})` : ""}`);

// --- launch ---
const g = await fromGem(img);
check("GEM runs BOOT.WSM off the data disk, the committed cart", g.m.launch.name === "BOOT.WSM" && g.m.launch.same, g.m.launch.name);
g.frames(3);
check("it opens in the desktop's resolution (GEM's default: low)", g.mode() === 0, `mode ${g.mode()}`);
check("the Windows area: four windows, OVERLAP B (the fourth) on top", [1, 2, 3, 4].every((i) => g.win(i, 2) > 0) && g.top() === 4, `top ${g.top()}`);
check("the first, at the back, is larger than the screen", g.win(1, 6) > 320 && g.win(1, 7) > 200, `${g.win(1, 6)}x${g.win(1, 7)}`);

// --- every area, in each mode, twice ---
async function sweep(mode) {
    const d = await rig(mode), hashes = [];
    for (const [name, k] of AREAS) {
        const before = d.plane();
        d.ctrl(k); d.frames(2);
        const h = d.plane();
        hashes.push(h);
        if (hashes.length > 1 && h === before) check(`${MODES[mode]}: ^${k.toUpperCase()} shows ${name}`, false);
        if (colours(d) < 3) check(`${MODES[mode]}: ${name} is drawn`, false, `${colours(d)} colours`);
        d.frames(5);
        if (d.plane() !== h) check(`${MODES[mode]}: ${name}: an idle frame paints nothing`, false);
        same(d, `${MODES[mode]}: ${name}`);
    }
    return hashes;
}
for (const mode of [0, 1, 2]) {
    const a = await sweep(mode), b = await sweep(mode);
    check(`${MODES[mode]}: eight areas, eight different screens`, new Set(a).size === 8, `${new Set(a).size}`);
    check(`${MODES[mode]}: a second run draws the same eight (deterministic)`, a.join() === b.join());
}

// --- windows: top, move, size, scroll, close (medium) ---
const w = await rig(1), G = 2; // GADGETS: window 2 (window 1 is the larger-than-screen one, at the back)
w.click(w.win(G, 4) + 200, w.win(G, 5) + 5); // GADGETS's title bar, left of the big window
check("a click on a lower window tops it (WF_TOP)", w.top() === G, `top ${w.top()}`);
const x0 = w.win(G, 4);
w.drag(x0 + 60, w.win(G, 5) + 5, x0 + 100, w.win(G, 5) + 25);
check("its title dragged moves it", w.win(G, 4) === x0 + 40, `${x0} -> ${w.win(G, 4)}`);
same(w, "moved");
const ww = w.win(G, 6);
w.drag(w.win(G, 4) + ww - 5, w.win(G, 5) + w.win(G, 7) - 5, w.win(G, 4) + ww - 65, w.win(G, 5) + w.win(G, 7) - 25);
check("the sizer resizes it (to the cell)", w.win(G, 6) < ww - 40 && w.win(G, 6) > ww - 70, `${ww} -> ${w.win(G, 6)}`);
same(w, "sized");
w.click(w.win(G, 4) + w.win(G, 6) - 6, w.win(G, 5) + w.win(G, 7) - 18); // the down arrow (12-px boxes above the sizer)
check("the down arrow scrolls the grid one row", w.win(G, 8) === 1, `vscroll ${w.win(G, 8)}`);
same(w, "scrolled");
w.click(w.win(G, 4) + 5, w.win(G, 5) + 5); // the closer
check("the closer closes it; another window is on top", w.top() !== G && w.top() > 0, `top ${w.top()}`);
same(w, "closed");

// --- menus ---
const m = await rig(1);
m.ctrl("e");
const m0 = m.plane();
m.ctrl("l");
check("^L, the Menus title's shortcut, is counted in the window", m.plane() !== m0);
const m1 = m.plane();
m.ctrl("u");
check("the disabled ^U does nothing", m.plane() === m1);
const pick = () => { m.point(108, 4); m.frames(2); m.click(120, 11 + 3 * 8 + 4); m.frames(2); }; // Menus > Checked item
pick();
const m2 = m.plane();
check("Menus > Checked item off the bar changes the window", m2 !== m1);
pick();
check("picked twice the check is back (only the counters moved)", m.plane() !== m2);
same(m, "menus");

// --- dialogs (the desk: the controls by the layout in area_dialogs.zig, work-area relative) ---
const dl = await rig(2); // the desk: the whole dialog fits (low and medium cut it at the field)
dl.ctrl("d");
const at = (x, y) => [dl.win(1, 0) + x, dl.win(1, 1) + y];
const press = (x, y, what) => { const b = dl.plane(); dl.click(...at(x, y)); check(`dialogs: ${what}`, dl.plane() !== b); };
press(24, 20, "OK (the default button) pressed");
press(88, 68, "a radio button selected");
dl.point(...at(13, 105)); // the desk draws its arrow into the plane: the pointer where the clicks will be
const cb = dl.plane();
press(13, 105, "a check box toggled");
dl.click(...at(13, 105));
check("dialogs: toggled twice, the box is back", dl.plane() === cb);
press(96, 140, "the field takes the focus");
const f0 = dl.plane(); dl.type("0911");
check("dialogs: digits type into the field, letters do not", dl.plane() !== f0);
same(dl, "dialogs");

// --- alerts and files ---
const al = await rig(0);
al.show(17); // form_alert icon 2, 2 buttons, over the Alerts area
const up = al.plane();
al.key(13);
check("form_alert opens; Return closes it and the answer shows", up !== al.plane() && colours(al) >= 3);
const before = al.plane(); al.show(22);
check("the malformed string opens no alert (only the line changes)", al.plane() !== before && al.top() === 1);
const fa = await rig(0); fa.show(30); const ha = fa.plane();
const fc = await rig(0); fc.show(31); const hc = fc.plane();
check("the ITEM SELECTOR on A:\\*.* and on C:\\*.* lists different names", ha !== hc);
fc.click(216, 176); fc.frames(2); // Cancel, TOS 4's box at (4, 11) in low res (fsel_tree.zig)
const ok = await rig(0); ok.show(31); ok.key(13); ok.frames(2); // Return: OK (the window then says "Button: OK")
check("its Cancel closes it, answering Cancel (not OK: the button left of it)", fc.plane() !== hc && fc.plane() !== ok.plane());

// --- quit ---
const q = await rig(0);
q.ctrl("q");
check("^Q: back to the desktop (request 4)", q.m.demo.pollCartRequest() === 4);

if (brk) {
    console.log(failures ? `\ngemtest_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_check: ${failures} FAILED` : "\ngemtest_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
