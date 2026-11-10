// NOTEPAD's ITEM SELECTOR on a C: laid out as Matt's card (board bug, 9 Nov: "0 folders, 0 files"
// on a C:\ holding MUSIC\ PICTURES\ NET\ and ECHO.REQ, no .TXT): docs/gemdos-c.img with its root
// files removed, MUSIC\ and NET\ made, ECHO.REQ and NET\INNET.TXT copied in (mtools). The list is
// read off the screen: a row holds a name when its first cell has ink above the underscore, a
// folder when the marker cell has TOS's diamond.
//   root     ^O on C:\*.TXT lists the four folders and no file (TOS lists folders whatever the mask)
//   mask     a click on the Directory: line, *.TXT edited to *.*, Return: ECHO.REQ is listed too,
//            and the box stays up (Return re-reads, it is not OK)
//   folder   a click on NET opens it: the list is INNET.TXT; the close box goes back to C:\
//   open     NET\INNET.TXT picked and opened, X typed, ^S: the file in NET\ is rewritten (mtools)
//   node apps/notepad_fsel_check.mjs [--break spec|relist] [--png <dir>]
//     spec: the program cannot read the selector's spec; relist: the ROM's relist answer is lost
import { writeFile, readFile, mkdir, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { fromGem, C_IMAGE } from "./notepad_lib.mjs";
import { png } from "./ports_machine.mjs";

const args = process.argv.slice(2);
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : ""; };
const brk = opt("--break"), pngDir = opt("--png");
if (brk && !["spec", "relist"].includes(brk)) throw new Error(`--break ${brk}: spec or relist`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };

// The card's C:\, built with mtools in a scratch directory.
const DIR = `${tmpdir()}/notepad_fsel_${process.pid}`;
const IMG = `${DIR}/c.img`;
const mt = (cmd, ...a) => execFileSync(cmd, ["-i", IMG, ...a], { stdio: ["ignore", "pipe", "pipe"] }).toString("latin1");
await mkdir(DIR, { recursive: true });
await writeFile(IMG, await readFile(C_IMAGE));
mt("mdel", "::HD/README.TXT", "::HD/EMPTY.DAT");
mt("mmd", "::HD/MUSIC", "::HD/NET");
await writeFile(`${DIR}/ECHO.REQ`, "ping\r\n");
await writeFile(`${DIR}/INNET.TXT`, "in net\r\n");
mt("mcopy", `${DIR}/ECHO.REQ`, "::HD/ECHO.REQ");
mt("mcopy", `${DIR}/INNET.TXT`, "::HD/NET/INNET.TXT");
const img = new Uint8Array(await readFile(IMG));
const mtype = async (path) => { await writeFile(IMG, img); try { return mt("mtype", `::HD/${path}`); } catch { return null; } };

const patch = (m) => {
    if (brk === "spec") m.env.fileSelSpec = () => 0;
    if (brk === "relist") m.env.fileSelProcess = (h, g) => { const r = m.rom.fileSelProcess(h, g); return r === 3 ? 0 : r; };
};
console.log(`notepad_fsel_check: NOTEPAD's ITEM SELECTOR over a card-like C:${brk ? ` (--break ${brk})` : ""}`);
const d = await fromGem(img, "", patch);
d.frames(3);

// The selector in low res (320 x 200): the 320 x 152 box at y 24 (filesel.zig), its list at (24, 45).
const BX = 0, BY = 24, LX = BX + 24, LY = BY + 45, ROW0 = LY + 11 + 8;
function pixel(x, y) {
    const v = new DataView(d.m.memory.buffer, d.m.machine.hwVideoBase());
    const base = v.getUint32(0x44, true), stride = v.getUint16(0x34, true);
    return new Uint8Array(d.m.memory.buffer, d.m.machine.hwVideoBase() + base + y * stride + x, 1)[0];
}
// The nine rows: "dir", "file" or "" (the empty template).
function rows() {
    const out = [];
    for (let i = 0; i < 9; i++) {
        const y = ROW0 + i * 8;
        let ink = false;
        for (let yy = y; yy < y + 6; yy++) for (let x = LX + 32; x < LX + 40; x++) ink ||= pixel(x, yy) === 0;
        out.push(!ink ? "" : pixel(LX + 16 + 3, y + 3) === 0 ? "dir" : "file");
    }
    return out;
}
const count = (r, k) => r.filter((x) => x === k).length;
const shot = (name) => { if (pngDir) png(d.picture(), `${pngDir}/fsel_${name}.png`); };

d.ctrl("o"); d.frames(2); shot("root");
let r = rows();
check("^O on C:\\*.TXT: the four folders, no file", count(r, "dir") === 4 && count(r, "file") === 0, r.join(","));

d.click(BX + 40, BY + 34); // the Directory: line
for (let i = 0; i < 3; i++) d.key(8);
d.type("*"); d.key(13); d.frames(2); shot("mask");
r = rows();
check("the Directory: line edited to C:\\*.*, Return: the folders and ECHO.REQ", count(r, "dir") === 4 && count(r, "file") === 1 && r[4] === "file", r.join(","));
const up = () => [1, 2].some((h) => d.m.rom.fileSelActive(h) === 1); // rom_main.zig MAX_FSEL
check("Return re-read the list: the selector is still up", up());

// NET is the folder GEMDOS lists last (made last): the fourth row.
d.click(LX + 50, ROW0 + 3 * 8 + 3); d.frames(2); shot("net");
r = rows();
check("a click on NET opens it: INNET.TXT, no folder", count(r, "dir") === 0 && count(r, "file") === 1, r.join(","));
d.click(LX + 3, LY + 3); d.frames(2);
r = rows();
check("the close box goes back to C:\\", count(r, "dir") === 4 && count(r, "file") === 1, r.join(","));

d.click(LX + 50, ROW0 + 3 * 8 + 3); d.frames(2);
d.click(LX + 50, ROW0 + 3); d.frames(1); // INNET.TXT into the Selection field
d.key(13); d.frames(3);
d.type("X"); d.ctrl("s"); d.frames(3);
const saved = await mtype("NET/INNET.TXT");
check("NET\\INNET.TXT opened, X typed, ^S: the file in NET\\ is rewritten", saved === "Xin net\r\n", JSON.stringify(saved));
check("...and nothing landed in C:\\", (await mtype("INNET.TXT")) === null);

await rm(DIR, { recursive: true, force: true });
if (brk) {
    console.log(failures ? `\nnotepad_fsel_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\nnotepad_fsel_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\nnotepad_fsel_check: ${failures} FAILED` : "\nnotepad_fsel_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
