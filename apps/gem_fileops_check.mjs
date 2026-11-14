// GEM5_PLAN P1.1, real file operations on C: (rom/gem/desktop/fileop*.zig posts them, the shell's
// apps/zig/scenes/gem_fileop*.zig does them through KOS GEMDOS). The machine + ROM + GEM shell over a
// C: card built with mtools (HD\ = C:\: ECHO.REQ, BIG.DAT 70 KB, MUSIC\, NET\, PAIR\ two files,
// PICTURES\ with PLASMA\ inside) and a FAT floppy in drive A, driven by the pointer and keys as the page
// drives them (text view: one row an item), every write served by KFS as the page serves it. Then the
// image is read back with mtools: the exact bytes, no ~KOS?.TMP left, fsck.fat -n clean.
//   low    a file dragged onto NET (TOS's box: 0 folders 1 item, OK, its count runs down to 0), the
//          PICTURES folder with its contents onto NET (2 folders 2 items), BIG.DAT Control-dragged onto
//          MUSIC (moved: one rename), ECHO.REQ onto NET again (NAME CONFLICT, Skip: nothing written),
//          Show Info renames it PONG.REQ, New Folder NEWDIR, PAIR dropped on the TRASH (gone, contents too)
//   drive  FLOPPY.TXT Control-dragged from A:\ into C:\'s window: copied, A:'s delete refused (write-
//          protected), the source kept and an alert; a drop onto the floppy's icon: the write-protect alert
//   desk1  GEM 5's engine in the desk: ECHO.REQ dropped onto the C: icon (its own folder): NAME CONFLICT,
//          renamed ECHO2.REQ, copied as that
//   medium the old path in medium: PICTURES onto MUSIC
//   full   a card with 50 KB free: PAIR onto NET stops at B.DAT (the alert, -10), A.TXT copied, no B.DAT,
//          no temporary file, fsck clean
//   keep   a host that refuses renames: the Control-drag of ECHO.REQ onto NET leaves it where it was
//   node apps/gem_fileops_check.mjs [--break copy|delete|rename|click] [--png <dir>]   (mutants: the host answers 0 to that
//   kind of request and writes nothing; each must be caught)
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { card, floppy, desktop, runOut, read, names, fsck, temps, shot, PHASE, FILES, FLOPPY_TXT } from "./gem_fileops_lib.mjs";

const args = process.argv.slice(2);
const opt = (n) => (args.includes(n) ? args[args.indexOf(n) + 1] : "");
const brk = opt("--break"), pngDir = opt("--png");
const MUTANT = { copy: 1, delete: 2, rename: 3 }; // rom/kos/kfs_abi.zig Op: write, delete, rename
const CLICK_BIT = 1 << 18; // rom/gem/desktop/deskbreak.zig CLICK: every held press drags, icons under windows take drops
if (brk && !MUTANT[brk] && brk !== "click") throw new Error(`--break ${brk}: copy, delete, rename or click`);
const CTRL = 0xe014, BS = 8, RET = 13;
const DIR = mkdtempSync(`${tmpdir()}/gem_fileops_`);
let fails = 0;
const check = (what, ok, detail = "") => { if (!ok) fails++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${what}${detail ? ": " + detail : ""}`); };
const same = (a, b) => a !== null && Buffer.compare(a, b) === 0;
// The mutant: requests of that kind answered 0 and dropped (rmdir with delete).
const mutant = (m, req, serve) => {
    const op = new Uint32Array(m.buffer, req, 1)[0];
    return MUTANT[brk] === op || (brk === "delete" && op === 5) ? 0 : serve(req);
};
const hook = MUTANT[brk] ? mutant : null;
const bits = brk === "click" ? CLICK_BIT : 0;

// C:\'s window opens at (2, 24) in low res (clamped), (24, 24) wider; text rows 10 px from y 45.
const row = (i, y0 = 24) => y0 + 26 + 10 * i;
const X = 60, TRASH = [20, 158];
function op(ui, from, to, { ctrl = false, confirm = true } = {}) {
    if (ctrl) ui.key(CTRL);
    ui.drag(from, to);
    if (ctrl) ui.keyUp(CTRL);
    const counted = { phase: ui.box("phase"), folders: ui.box("folders"), files: ui.box("files") };
    if (confirm && counted.phase === PHASE.counted) ui.key(RET); // the box's OK (the default button)
    const seen = [];
    const done = runOut(ui, seen);
    return { counted, seen, done, status: ui.box("status"), kept: ui.box("kept") };
}
const countsDown = (seen, n) => seen.length > 0 && seen[0] === n && seen.at(-1) === 0 && seen.every((v, i) => i === 0 || v <= seen[i - 1]);
function alerted(ui) { // an alert is up: Return takes it down and the screen changes
    const before = ui.gem.hash();
    ui.key(RET); ui.settle(4);
    return ui.gem.hash() !== before;
}
function menu(ui, item) { ui.click(72, 8); ui.click(100, 15 + 8 * item); ui.settle(2); } // File > item

async function low() {
    console.log("low (the old path)");
    const c = card(DIR, "low"), ui = await desktop(c, null, "low", hook);
    ui.open(20, 70); // C:\ (rows: BIG.DAT ECHO.REQ MUSIC NET PAIR PICTURES)
    let r = op(ui, [X, row(1)], [X, row(3)]);
    check("a file onto NET: TOS's box counts 0 folders, 1 item", r.counted.phase === PHASE.counted && r.counted.folders === 0 && r.counted.files === 1, JSON.stringify(r.counted));
    check("...its count runs down to 0 while it works", countsDown(r.seen, 1), r.seen.join(","));
    ui.save();
    check("...C:\\NET\\ECHO.REQ has its bytes, C:\\ECHO.REQ is still there", same(read(c, "HD/NET/ECHO.REQ"), FILES["ECHO.REQ"]) && same(read(c, "HD/ECHO.REQ"), FILES["ECHO.REQ"]));
    r = op(ui, [X, row(5)], [X, row(3)]);
    check("the PICTURES folder onto NET: 2 folders, 2 items, counted down", r.counted.folders === 2 && r.counted.files === 2 && countsDown(r.seen, 2), `${JSON.stringify(r.counted)} ${r.seen.join(",")}`);
    ui.save();
    check("...NET\\PICTURES holds WAVES.PI1 and PLASMA\\PLASMA.PI1, byte for byte",
        same(read(c, "HD/NET/PICTURES/WAVES.PI1"), FILES["PICTURES/WAVES.PI1"]) && same(read(c, "HD/NET/PICTURES/PLASMA/PLASMA.PI1"), FILES["PICTURES/PLASMA/PLASMA.PI1"]));
    r = op(ui, [X, row(0)], [X, row(2)], { ctrl: true });
    ui.save();
    check("BIG.DAT Control-dragged onto MUSIC is MOVED (70,000 bytes there, none at the root)", same(read(c, "HD/MUSIC/BIG.DAT"), FILES["BIG.DAT"]) && read(c, "HD/BIG.DAT") === null && r.status === 0);
    // rows now: ECHO.REQ MUSIC NET PAIR PICTURES
    r = op(ui, [X, row(0)], [X, row(2)]);
    const conflict = ui.box("phase") === PHASE.conflict;
    if (conflict) { ui.click(160, 131); runOut(ui); } // NAME CONFLICT's Skip
    check("ECHO.REQ onto NET again raises NAME CONFLICT; Skip leaves it out and ends the copy", conflict && ui.box("phase") === PHASE.idle && ui.box("status") === 0 && ui.box("files_left") === 0);
    ui.click(X, row(0)); menu(ui, 1); // Show Info... on ECHO.REQ
    for (let i = 0; i < 8; i++) ui.key(BS);
    ui.type("PONG.REQ"); ui.key(RET); runOut(ui);
    menu(ui, 3); ui.type("NEWDIR"); ui.key(RET); runOut(ui); // New Folder...
    ui.save();
    const root = names(c, "HD");
    check("Show Info renamed ECHO.REQ to PONG.REQ; New Folder made NEWDIR", root.includes("PONG.REQ") && !root.includes("ECHO.REQ") && names(c, "HD/NEWDIR") !== null, root.join(" "));
    // rows now: PONG.REQ, then the folders in the card's order: MUSIC NET PAIR PICTURES NEWDIR
    const pair = 3;
    r = op(ui, [X, row(pair)], TRASH);
    ui.save();
    check("PAIR dropped on the TRASH: DELETE FILE(S) counts 1 folder 2 files, and it is gone", r.counted.folders === 1 && r.counted.files === 2 && names(c, "HD/PAIR") === null, JSON.stringify(r.counted));
    tidy(c);
}

function tidy(c) {
    check("no ~KOS?.TMP left on the card", temps(c).length === 0, temps(c).join(" "));
    const f = fsck(c);
    check("fsck.fat -n finds the card clean", f === "", f);
}

async function drive() {
    console.log("drive A");
    const c = card(DIR, "drive"), a = floppy(DIR), ui = await desktop(c, a, "low", hook);
    ui.open(20, 30); // A:\ at (2, 24): it covers C:'s icon
    ui.drag([150, 28], [150, 128]); // its title bar: A:\ down to y 124
    ui.open(20, 70); // C:\ at the cascade's next spot, (2, 36)
    ui.click(150, 180); // A:\'s part below C:\ raises it
    if (pngDir) await shot(ui, `${pngDir}/fileops_drive.png`);
    const r = op(ui, [X, row(0, 124)], [150, 60], { ctrl: true }); // into C:\ where A:\ does not cover it
    const alert = alerted(ui);
    ui.save();
    check("FLOPPY.TXT Control-dragged from A:\\ into C:\\'s window is copied there", same(read(c, "HD/FLOPPY.TXT"), FLOPPY_TXT), JSON.stringify(r.counted));
    check("...A:'s delete is refused (write-protected): the source is kept, and said so", r.kept === 1 && alert, `kept ${r.kept}`);
    ui.click(150, 60); // C:\ on top: its rows at y 62..
    const before = ui.box("seq");
    ui.drag([X, row(1, 36)], [20, 22]); // ECHO.REQ onto drive A's icon
    check("a copy onto drive A: the write-protect alert, nothing posted", ui.box("seq") === before && ui.box("phase") === PHASE.idle && alerted(ui));
    tidy(c);
}

async function deskEngine() {
    console.log("desk1 (GEM 5's engine)");
    const c = card(DIR, "desk"), ui = await desktop(c, null, "desk1", hook, bits);
    ui.open(20, 70);
    ui.drag([200, 30], [400, 230]); // C:\'s title bar: the window to (224, 224), off the C: icon
    const seq = ui.box("seq");
    ui.drag([300, row(1, 224)], [36, 72]); // ECHO.REQ onto the C: icon: its own folder
    check("ECHO.REQ dropped on the C: icon (its own folder) does nothing", ui.box("seq") === seq && ui.box("phase") === PHASE.idle && !alerted(ui));
    op(ui, [300, row(1, 224)], [300, row(3, 224)]); // onto NET, then again: NAME CONFLICT
    const r = op(ui, [300, row(1, 224)], [300, row(3, 224)]);
    if (pngDir) await shot(ui, `${pngDir}/fileops_conflict.png`);
    const conflict = ui.box("phase") === PHASE.conflict;
    for (let i = 0; i < 8; i++) ui.key(BS);
    ui.type("ECHO2.REQ"); ui.key(RET); runOut(ui);
    ui.save();
    check("ECHO.REQ onto NET a second time: NAME CONFLICT, copied as NET\\ECHO2.REQ", conflict && same(read(c, "HD/NET/ECHO2.REQ"), FILES["ECHO.REQ"]), JSON.stringify(r.counted));
    tidy(c);
}

// Matt on the board, 10 Nov: a click on BOOT.WSM in A:\ raised "The disk cannot be read": a held
// press counted as a drag and its release "dropped" on C:'s icon under A:\'s window.
async function clicks() {
    console.log("clicks (low, A:\\ a .zmd over C:'s icon)");
    const c = card(DIR, "clicks"), ui = await desktop(c, null, "low", hook, bits), gem = ui.gem;
    gem.mount(["AAA.DAT", "BBB.DAT", "BOOT.WSM"].map((name, i) => ({ name, type: name.endsWith(".WSM") ? 0 : 1, size: 100 + i, date: 20261110 })));
    gem.programs["BOOT.WSM"] = gem.gemBytes; // what request 3 runs: any cart will do
    ui.open(20, 30); // A:\ at (2, 24): BOOT.WSM's row (y 70) lies over C:'s icon
    const seq = ui.box("seq"), hold = (x, y) => { ui.point(x, y, 1); ui.point(x, y, 1); };
    ui.point(20, 70, 0); hold(20, 70); ui.point(21, 71, 1); ui.point(21, 71, 0); ui.settle(2); // a click, a pixel of jitter
    check("a click on BOOT.WSM (held, 1 px of jitter) only selects: nothing posted, no alert", ui.box("seq") === seq && ui.box("phase") === PHASE.idle && !alerted(ui));
    hold(20, 70); ui.point(20, 70, 0); hold(20, 70); ui.point(20, 70, 0); // a double-click, presses held
    ui.point(20, 70, 2); ui.point(20, 70, 0); ui.settle(2); // and the loader's double-click pulse
    check("a double-click on BOOT.WSM runs it (request 3), nothing posted", gem.swaps === 1 && ui.box("seq") === seq, `swaps ${gem.swaps}`);
}

async function medium() {
    console.log("medium (the old path)");
    const c = card(DIR, "medium"), ui = await desktop(c, null, "medium", hook);
    ui.open(20, 70);
    const r = op(ui, [X, row(5)], [X, row(2)]);
    ui.save();
    check("PICTURES onto MUSIC: both pictures there, byte for byte", same(read(c, "HD/MUSIC/PICTURES/PLASMA/PLASMA.PI1"), FILES["PICTURES/PLASMA/PLASMA.PI1"]) && r.status === 0);
    tidy(c);
}

async function full() {
    console.log("full card");
    const free = 360 * 1024 - 2 * 1024 - 7 * 1024 - 2 * 70000 - 2 * 32768 - 10 * 1024; // a 360 KB card, roughly
    const c = card(DIR, "full", 360, Math.max(0, free - 50 * 1024)), ui = await desktop(c, null, "low", hook);
    ui.open(20, 70);
    const r = op(ui, [X, row(4)], [X, row(3)]);
    const alert = alerted(ui);
    ui.save();
    check("PAIR onto NET on a full card stops with the alert (EWRITF)", r.status === -10 && alert, `status ${r.status}`);
    check("...A.TXT was copied, B.DAT left NO partial file", same(read(c, "HD/NET/PAIR/A.TXT"), FILES["PAIR/A.TXT"]) && read(c, "HD/NET/PAIR/B.DAT") === null);
    tidy(c);
}

async function keep() {
    console.log("a move whose rename fails");
    const c = card(DIR, "keep");
    const refuse = (m, req, serve) => (new Uint32Array(m.buffer, req, 1)[0] === 3 ? -36 : (hook ? hook(m, req, serve) : serve(req)));
    const ui = await desktop(c, null, "low", refuse);
    ui.open(20, 70);
    const r = op(ui, [X, row(1)], [X, row(3)], { ctrl: true });
    const alert = alerted(ui);
    ui.save();
    check("the host refuses the move: ECHO.REQ stays where it was, not in NET, an alert", r.status === -36 && alert && same(read(c, "HD/ECHO.REQ"), FILES["ECHO.REQ"]) && read(c, "HD/NET/ECHO.REQ") === null, `status ${r.status}`);
}

console.log(`gem_fileops_check: C:'s file operations through the desktop${brk ? ` (--break ${brk})` : ""}`);
for (const s of brk === "click" ? [clicks, deskEngine] : [low, drive, deskEngine, medium, full, keep, clicks]) await s();
rmSync(DIR, { recursive: true, force: true });
if (brk) {
    console.log(fails ? `\ngem_fileops_check: PASS (--break ${brk} was caught)` : `\ngem_fileops_check: FAILED - --break ${brk} was not caught`);
    process.exit(fails ? 0 : 1);
}
console.log(fails ? `\ngem_fileops_check: ${fails} FAILED` : "\ngem_fileops_check: PASS");
process.exit(fails ? 1 : 0);
