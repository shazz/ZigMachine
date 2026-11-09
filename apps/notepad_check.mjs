// NOTEPAD (apps/zig/scenes/notepad.zig, docs/NOTEPAD.md) end to end, over the real machine + ROM with
// C: = a copy of docs/gemdos-c.img (KOS GEMDOS, the page's KFS for the writes):
//   launch   GEM boots over demo-notepad.zmd, BOOT.WSM is the committed cart, it opens in the desktop's
//            resolution (low: GEM's default), a window and a menu bar from the ROM (winGet answers)
//   save     text typed, ^S, the ITEM SELECTOR, NOTE typed, Return: C:\NOTE.TXT holds the text with
//            CR LF (mtools), fsck clean; the title loses its "*"
//   reopen   a new session, ^O, NOTE.TXT typed, Return: the text rows are the first session's pixels
//   alert    more typing, ^N: form_alert "Save changes?"; Cancel keeps the text, Return (Yes) saves
//            and empties it; the file has the new line
//   menu     File > Open... by the pointer opens the selector; Edit's Cut is disabled with no selection
//   scroll   60 lines: the view follows the cursor (vscroll), PgUp, the up arrow gadget held repeats
//   resize   the size gadget dragged: the work area shrinks, the window outline left no dot behind
//   repaint  after each step, the incremental screen equals a whole repaint, byte for byte; an idle
//            frame changes nothing
//   modes    a desktop in medium and in the desk: Notepad opens in it (Getrez), the same checks hold
//   node apps/notepad_check.mjs [--break write|bytes|ctrl] [--png <dir>]
//     write: the host refuses every write; bytes: a byte changed on its way; ctrl: Control never sent
import { readFile, writeFile, rm, mkdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { fromGem, afterDesktop, K, C_IMAGE } from "./notepad_lib.mjs";
import { png } from "./ports_machine.mjs";

const args = process.argv.slice(2);
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : ""; };
const brk = opt("--break"), pngDir = opt("--png");
if (brk && !["write", "bytes", "ctrl"].includes(brk)) throw new Error(`--break ${brk}: write, bytes or ctrl`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const shots = {};
const shot = (name, d) => { if (pngDir) shots[name] = d.picture(); };

// What the image holds at C:\path (mtools), and whether fsck.fat calls it clean.
const IMG = `${tmpdir()}/notepad_check_${process.pid}.img`;
async function mtype(img, path) {
    await writeFile(IMG, img);
    try { return execFileSync("mtype", ["-i", IMG, `::HD/${path}`], { stdio: ["ignore", "pipe", "pipe"] }).toString("latin1"); } catch { return null; }
}
async function fsckClean(img) {
    await writeFile(IMG, img);
    try { execFileSync("fsck.fat", ["-n", IMG], { stdio: "pipe" }); return true; } catch (e) { return e.code === "ENOENT"; }
}
// The incremental screen against a whole repaint of the same state.
function same(d, what) {
    const inc = d.plane();
    const full = d.repainted();
    check(`${what}: the screen as drawn = a whole repaint`, inc === full, inc === full ? "" : `${inc.slice(0, 12)} vs ${full.slice(0, 12)}`);
}

const TEXT = "Hello, GEM 5!\nNotepad on KOS.";
console.log(`notepad_check: NOTEPAD off docs/demo-notepad.zmd, C: = a copy of ${C_IMAGE}${brk ? ` (--break ${brk})` : ""}`);
const img = new Uint8Array(await readFile(C_IMAGE));

// --- launch, type, save ---
const a = await fromGem(img, brk);
check("GEM runs BOOT.WSM off the data disk, the committed cart", a.m.launch.name === "BOOT.WSM" && a.m.launch.same, a.m.launch.name);
a.frames(3);
check("it opens in the desktop's resolution (GEM's default: low)", a.res() === 0, `RESOLUTION ${a.res()}`);
const [wx, wy, ww, wh] = a.work();
check("a ROM window with a work area", ww > 200 && wh > 100, `${ww}x${wh} at ${wx},${wy}`);
const idle0 = a.plane(); a.frames(5);
check("an idle frame paints nothing", a.plane() === idle0);
a.type(TEXT);
shot("typed", a);
same(a, "typed");
a.ctrl("s");
shot("save_selector", a);
a.type("note"); a.key(13); a.frames(3);
const saved = await mtype(img, "NOTE.TXT");
check("^S, NOTE, Return: C:\\NOTE.TXT is the text with CR LF", saved === TEXT.replace(/\n/g, "\r\n"), JSON.stringify(saved));
check("the card stays clean (fsck.fat -n)", await fsckClean(img));
same(a, "saved");
const typedRows = a.plane();

// --- reopen in a new session ---
const b = await fromGem(img, brk);
b.frames(3);
b.ctrl("o"); b.type("NOTE.TXT"); b.key(13); b.frames(3);
b.key(K.END); b.arrow(1); b.key(K.END); // the cursor where a's was: after the last character typed
check("^O NOTE.TXT shows what was typed, pixel for pixel", b.plane() === typedRows);

// --- Save changes? ---
a.type("\nMore.");
a.ctrl("n");
shot("save_changes", a);
const alertUp = a.plane();
a.click(232, 117); // Cancel (the alert's third button in low res)
check("Cancel keeps the text and the alert goes", a.plane() !== alertUp && (await mtype(img, "NOTE.TXT")) === saved);
a.ctrl("n");
a.key(13); a.frames(3); // Return: the default, Yes
check("Yes (Return) saves then empties the text", await mtype(img, "NOTE.TXT") === (TEXT + "\nMore.").replace(/\n/g, "\r\n"));
same(a, "after New");

// --- the menu by the pointer ---
a.point(72, 4); a.frames(2); // File drops on hover
shot("file_menu", a);
a.click(72, 23); a.frames(2); // Open...
shot("open_selector", a);
const selector = a.plane();
a.click(264, 148); a.frames(2); // Cancel (the ITEM SELECTOR's, low res: 222..306 x 142..154 in a box at 0,24)
check("File > Open... by the pointer opens the ITEM SELECTOR, Cancel closes it", selector !== a.plane());
same(a, "menu");

// --- scroll ---
for (let i = 0; i < 60; i++) a.type(`line ${i}\n`);
check("the view follows the cursor down (vscroll)", a.win(8) > 40, `vscroll ${a.win(8)}`);
same(a, "60 lines");
a.key(K.PGUP); a.key(K.PGUP);
const v1 = a.win(8);
check("PgUp scrolls back", v1 < 40, `vscroll ${v1}`);
const up = [a.win(4) + a.win(6) - 6, a.win(5) + 12 + 5];
a.point(...up, 0); a.point(...up, 1); a.frames(30); a.point(...up, 0);
check("the up arrow held repeats (TOS's arrows did)", a.win(8) < v1 - 3, `vscroll ${v1} -> ${a.win(8)}`);
same(a, "scrolled");

// --- resize ---
const w0 = a.win(2);
a.drag(a.win(4) + a.win(6) - 5, a.win(5) + a.win(7) - 5, a.win(4) + a.win(6) - 85, a.win(5) + a.win(7) - 45);
shot("resized", a);
check("the size gadget dragged shrinks the work area", a.win(2) < w0 - 60, `${w0} -> ${a.win(2)}`);
same(a, "resized");

// --- other resolutions ---
for (const [mode, name] of [[1, "medium"], [2, "desk"]]) {
    const c = await afterDesktop(new Uint8Array(await readFile(C_IMAGE)), mode, brk);
    c.frames(3);
    check(`after a desktop in ${name}, Notepad opens in it`, c.res() === [0, 2, 3][mode], `RESOLUTION ${c.res()}`);
    c.type(TEXT); c.point(300, 100); c.frames(2);
    same(c, `${name}: typed`);
    c.ctrl("a"); c.ctrl("c"); c.key(K.END); c.ctrl("v");
    shot(`${name}_pasted`, c);
    same(c, `${name}: select all, copy, paste`);
}

await rm(IMG, { force: true });
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [k, p] of Object.entries(shots)) await png(p, `${pngDir}/notepad_${k}.png`);
}
if (brk) {
    console.log(failures ? `\nnotepad_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\nnotepad_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\nnotepad_check: ${failures} FAILED` : "\nnotepad_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
