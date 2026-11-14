// Setscreen for a program (GEM 5 S6, rom/rom_app_screen.zig): GEMTEST's keys 1 2 3 switch its screen through
// the ROM (rom.aes.setscreen), which re-programs the plane and re-binds the program's context:
//   modes    low -> medium -> the desk -> low: the machine's RESOLUTION follows (0, 2, 3, 0) and each screen,
//            drawn through the re-bound context, equals a whole repaint (the area laid out for that mode)
//   refused  an unknown mode, and the desk with no buffer, change nothing (0xFF)
//   node apps/gemtest_screen_check.mjs [--break switch]   switch: Setscreen says yes and does nothing (bit 31)
import { readFile } from "node:fs/promises";
import { afterDesktop, C_IMAGE, MODES } from "./gemtest_lib.mjs";

const args = process.argv.slice(2);
const brk = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
if (brk && brk !== "switch") throw new Error(`--break ${brk}: switch`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const img = new Uint8Array(await readFile(C_IMAGE));

const d = await afterDesktop(img, 0);
d.m.rom.deskSetEngine(brk === "switch" ? 2 ** 31 : 0);
d.frames(3);
const RES = [0, 2, 3];
for (const mode of [1, 2, 0]) {
    d.key(0x31 + mode); d.frames(3); // keys 1 2 3
    check(`key ${mode + 1}: RESOLUTION is ${MODES[mode]}'s`, d.res() === RES[mode], `${d.res()}`);
    const inc = d.plane();
    check(`${MODES[mode]}: the screen through the re-bound context = a whole repaint`, inc === d.repainted());
}
const before = d.res();
check("an unknown mode is refused, nothing changes", d.m.rom.guiSetscreen(1, 7, 0) === 0xff && d.res() === before);
check("the desk with no buffer is refused, nothing changes", d.m.rom.guiSetscreen(1, 2, 0) === 0xff && d.res() === before);

if (brk) {
    console.log(failures ? `\ngemtest_screen_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ngemtest_screen_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ngemtest_screen_check: ${failures} FAILED` : "\ngemtest_screen_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
