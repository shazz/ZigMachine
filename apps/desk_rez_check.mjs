// The desktop's mode across a program load (rom/rom_deskmode.zig, docs/GEM_DESK_MODE.md §9).
// Matt on the board, 9 Nov: "i ran notepad from deskmode but it seems it switched to medium res".
// The page's ROM outlives the cart swap, so Getrez had its answer; the board loads a program as a
// new image with a fresh ROM, which said "no desktop ran" (0xFF: Notepad's medium). The board's
// firmware now hands the new ROM the mode the glass carried (cycles/bdeskrez.h, deskSetScreenMode);
// here a fresh machine + ROM stands for that image:
//   - Notepad opens in each mode it is told (low, medium, the desk); told nothing, medium (0xFF);
//   - the desktop's shell, told a mode, comes back in it (the return from a program), and a boot
//     (told nothing) keeps DESKTOP.INF's (low here); the shell forgets the return once bound;
//   - a mode past the desk is ignored (the ROM's boundary contract);
//   - on the page, a launch from GEM remembers the mode the desktop comes back in.
// --break carry: the firmware never hands the mode over (the board before the fix): caught.
//
// Usage: node apps/desk_rez_check.mjs [--break carry]
import { readFile } from "node:fs/promises";
import { afterBoardLoad, fromGem, C_IMAGE } from "./notepad_lib.mjs";

const GEM = "docs/demo-gem.wasm";
const RES = [0, 2, 3]; // RESOLUTION for low, medium, the desk
const NAMES = ["low", "medium", "the desk"];
const NONE = 0xff;
const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
if (brk && brk !== "carry") throw new Error(`unknown --break ${brk}`);
let failures = 0;
const check = (what, ok, detail = "") => {
    if (!ok) failures++;
    console.log(`${ok ? "ok  " : "FAIL"}  ${what}${ok || !detail ? "" : `  (${detail})`}`);
};
const img = async () => new Uint8Array(await readFile(C_IMAGE));

for (let mode = 0; mode < 3; mode++) {
    const d = await afterBoardLoad(await img(), mode, undefined, brk);
    d.frames(3);
    check(`a program loaded after a desktop in ${NAMES[mode]}: Notepad opens in it`, d.res() === RES[mode], `RESOLUTION ${d.res()}`);
    check(`...and Getrez says ${mode}`, d.m.rom.deskScreenMode() === mode, `${d.m.rom.deskScreenMode()}`);
}
const none = await afterBoardLoad(await img(), null);
none.frames(3);
check("no desktop ran (a cart booted directly): Getrez 0xFF, Notepad in medium", none.m.rom.deskScreenMode() === NONE && none.res() === 2,
    `Getrez ${none.m.rom.deskScreenMode()}, RESOLUTION ${none.res()}`);
for (const bad of [3, NONE, 0xffffffff]) none.m.rom.deskSetScreenMode(bad);
check("a mode past the desk is ignored", none.m.rom.deskScreenMode() === NONE && none.m.rom.deskReturnMode() === NONE);

for (let mode = 0; mode < 3; mode++) {
    const s = await afterBoardLoad(await img(), mode, GEM, brk);
    s.frames(3);
    check(`the desktop back from a program launched in ${NAMES[mode]} comes back in it`, s.res() === RES[mode], `RESOLUTION ${s.res()}`);
    check("...and the shell forgot the return once bound", s.m.rom.deskReturnMode() === NONE, `${s.m.rom.deskReturnMode()}`);
}
const boot = await afterBoardLoad(await img(), null, GEM);
boot.frames(3);
check("a boot (nothing carried) is DESKTOP.INF's mode: low", boot.res() === 0, `RESOLUTION ${boot.res()}`);

const page = await fromGem(await img());
check("on the page, a launch from GEM (low) remembers low for the return", page.m.rom.deskReturnMode() === 0, `${page.m.rom.deskReturnMode()}`);

if (brk) {
    console.log(failures ? `\ndesk_rez_check: PASS (--break ${brk} was caught: ${failures} checks failed)` : `\ndesk_rez_check: FAILED - --break ${brk} was not caught`);
    process.exitCode = failures ? 0 : 1;
} else {
    console.log(failures ? `\ndesk_rez_check: ${failures} FAILED` : "\ndesk_rez_check: PASS");
    process.exitCode = failures ? 1 : 0;
}
