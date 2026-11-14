// Drive A in the desktop's file operations and its selection (Matt on the board, 13 Nov, GEM 5.0):
//   zmd    A: is a .zmd data disk (docs/demo-sysinfo.zmd: BOOT.WSM and six sound files), the listing the
//          host hands, its bytes through env.diskReadBlock. BOOT.WSM dragged from A:\ into a folder of
//          C:\ (NET) must be copied byte for byte (it raised "The disk cannot be read": KOS GEMDOS does
//          not mount A: over a .zmd, so the shell's count answered EDRIVE), then KEYGEN.XM (18 KB) too.
//          A Control-drag (a move) copies and keeps the write-protected source, and says so.
//   big    A: a FAT floppy holding a 70 KB file: copied whole (GEMDOS's direct 64-sector runs over A:)
//   sel    A:\ and C:\ both open: a file selected in one window paints NOTHING selected in the other
//          (the desktop's one selection was kept by index only: A:'s first file lit C:'s first too)
//   node apps/gem_fileops_a_check.mjs [--break zmd|sel]   (zmd: the .zmd listed with no disk behind it,
//   the bytes must come from the drive; sel: the selection's drive check off; each must be caught)
import { mkdtempSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";
import { card, desktop, runOut, read, fsck, temps, bytesOf, PHASE } from "./gem_fileops_lib.mjs";
import { parseDisk } from "../docs/zmdisk.js";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && brk !== "zmd" && brk !== "sel") throw new Error(`--break ${brk}: zmd or sel`);
const bits = brk === "sel" ? 1 << 20 : 0; // rom/gem/desktop/deskbreak.zig SEL_DRIVE
const DIR = mkdtempSync(`${tmpdir()}/gem_fileops_a_`);
const CTRL = 0xe014, RET = 13;
let fails = 0;
const check = (what, ok, detail = "") => { if (!ok) fails++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${what}${detail ? ": " + detail : ""}`); };
const same = (a, b) => a !== null && b !== null && Buffer.compare(Buffer.from(a), Buffer.from(b)) === 0;
const row = (i, y0) => y0 + 26 + 10 * i;
const X = 60, CY = 24; // C:\'s window opens at (2, 24) (the cascade's first spot): its rows from y 50

const ZMD = new Uint8Array(readFileSync("docs/demo-sysinfo.zmd"));
const DISK = parseDisk(ZMD, "demo-sysinfo.zmd").mounted.files;
const fileOf = (name) => ZMD.subarray(DISK[name].start, DISK[name].start + DISK[name].len);
const listing = () => Object.entries(DISK).map(([name, f]) => ({ name, type: f.type & 0xff, size: f.len, date: 20261113 }));

// Both windows open, A:\ (text rows from y 150) below C:\ (rows from y 50), A:\ on top. --break zmd:
// the listing is handed but no disk is behind it (the drive answers nothing): the copy must fail.
async function twoWindows(c, aImg, zmd) {
    const ui = await desktop(c, zmd && brk !== "zmd" ? "docs/demo-sysinfo.zmd" : aImg, "low", null, bits);
    if (zmd) ui.gem.mount(listing());
    ui.open(20, 30); // A:\ at (2, 24)
    ui.drag([150, 28], [150, 128]); // its title bar: down to y 124
    ui.open(20, 70); // C:\ at (2, CY)
    ui.click(150, 180); // A:\'s part below C:\ raises it
    return ui;
}
function op(ui, from, to, ctrl = false) {
    if (ctrl) ui.key(CTRL);
    ui.drag(from, to);
    if (ctrl) { ui.keyUp(CTRL); }
    const counted = { phase: ui.box("phase"), files: ui.box("files"), status: ui.box("status") };
    if (counted.phase === PHASE.counted) ui.key(RET);
    runOut(ui);
    const r = { counted, status: ui.box("status"), kept: ui.box("kept") };
    if (ui.box("phase") === PHASE.idle) { ui.key(RET); ui.settle(4); } // any alert down
    return r;
}

async function zmd() {
    console.log("zmd (A: a .zmd data disk)");
    const c = card(DIR, "zmd"), ui = await twoWindows(c, null, true);
    // C:\'s rows: BIG.DAT ECHO.REQ MUSIC NET PAIR PICTURES (A:\ covers it from y 124 down only).
    let r = op(ui, [X, row(0, 124)], [X, row(3, CY)]); // BOOT.WSM onto NET
    ui.save();
    check("BOOT.WSM dragged from A:\\ (a .zmd) onto C:\\NET: counted 1 item, ended with no error", r.counted.files === 1 && r.status === 0, JSON.stringify(r));
    check("...C:\\NET\\BOOT.WSM holds the disk's bytes", same(read(c, "HD/NET/BOOT.WSM"), fileOf("BOOT.WSM")), `${read(c, "HD/NET/BOOT.WSM")?.length} of ${DISK["BOOT.WSM"].len}`);
    ui.click(150, 180); // A:\ on top again
    // rows sorted by name: BOOT.WSM GAUNTLET.SAP HERMINI.SID JINKS.SND KEYGEN.XM ... (0..4 in view)
    r = op(ui, [X, row(4, 124)], [X, row(3, CY)]);
    ui.save();
    check("KEYGEN.XM (18,619 bytes, not block-aligned on the disk's end) onto NET, byte for byte", r.status === 0 && same(read(c, "HD/NET/KEYGEN.XM"), fileOf("KEYGEN.XM")), JSON.stringify(r));
    ui.click(150, 180);
    r = op(ui, [X, row(3, 124)], [X, row(2, CY)], true); // JINKS.SND Control-dragged onto MUSIC
    ui.save();
    check("JINKS.SND Control-dragged onto MUSIC: copied, the write-protected source kept", r.status === 0 && r.kept === 1 && same(read(c, "HD/MUSIC/JINKS.SND"), fileOf("JINKS.SND")), JSON.stringify(r));
    check("no ~KOS?.TMP left, fsck.fat -n clean", temps(c).length === 0 && fsck(c) === "", fsck(c));
}

async function big() {
    console.log("big (A: a FAT floppy with a 70 KB file)");
    const c = card(DIR, "big"), a = `${DIR}/big.st`, data = bytesOf(70000, 9);
    execFileSync("mformat", ["-C", "-i", a, "-f", "720", "::"]);
    require_put(a, "LARGE.DAT", data);
    const ui = await twoWindows(c, a, false);
    const r = op(ui, [X, row(0, 124)], [X, row(3, CY)]);
    ui.save();
    check("LARGE.DAT (70,000 bytes) from the FAT floppy onto C:\\NET, byte for byte", r.status === 0 && same(read(c, "HD/NET/LARGE.DAT"), data), JSON.stringify(r));
}
function require_put(img, name, data) {
    const tmp = `${DIR}/put.bin`;
    execFileSync("sh", ["-c", 'cat > "$0"', tmp], { input: data });
    execFileSync("mcopy", ["-i", img, "-o", tmp, `::${name}`]);
}

// The pixels of C:\'s window rows 0..2 (the whole width: A:\'s rows are below them).
function cRows(ui) {
    const g = ui.gem, m = g.machine;
    m.hwRenderPlane(0);
    const W = m.hwPhysWidth(), px = new Uint8Array(g.memory.buffer, m.hwPhysicalPtr(), W * m.hwPhysHeight() * 4);
    const y0 = g.by + row(0, CY), y1 = g.by + row(3, CY);
    return Buffer.from(px.slice(y0 * W * 4, y1 * W * 4));
}

async function sel() {
    console.log("sel (A:\\ and C:\\ open, one selection)");
    const c = card(DIR, "sel"), ui = await twoWindows(c, null, true);
    const before = cRows(ui);
    ui.click(X, row(0, 124)); // BOOT.WSM, A:'s first file
    check("selecting A:\\'s first file leaves C:\\'s rows unselected (pixel for pixel)", same(cRows(ui), before));
    ui.click(X, row(1, CY)); // ECHO.REQ in C:\ (raises it)
    const aSel = cRows(ui);
    check("...and selecting C:\\'s ECHO.REQ lights it (the check sees a selection at all)", !same(aSel, before));
}

console.log(`gem_fileops_a_check: drive A in the desktop's file operations${brk ? ` (--break ${brk})` : ""}`);
for (const s of brk === "sel" ? [sel] : brk === "zmd" ? [zmd] : [zmd, big, sel]) await s();
rmSync(DIR, { recursive: true, force: true });
if (brk) {
    console.log(fails ? `\ngem_fileops_a_check: PASS (--break ${brk} was caught)` : `\ngem_fileops_a_check: FAILED - --break ${brk} was not caught`);
    process.exit(fails ? 0 : 1);
}
console.log(fails ? `\ngem_fileops_a_check: ${fails} FAILED` : "\ngem_fileops_a_check: PASS");
process.exit(fails ? 1 : 0);
