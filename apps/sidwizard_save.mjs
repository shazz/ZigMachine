// SID-Wizard (apps/ports/sidwizard) SAVES a song to C: and it is there afterwards, byte for byte. Started from GEM
// over its floppy (apps/ports_gem.mjs), C: = a copy of docs/gemdos-c.img, its writes served as the page serves
// them (docs/kos-cfile.js), as apps/gemdos_grafx2_save.mjs does for GrafX2.
//   SAVE     FLASHBAK.SWM opens off the floppy at start; F8 (the menu, on LOAD TUNE), Up (SAVE TUNE), Return:
//            the save dialog, the floppy's root listing C: as the folder "C" (apps/ports/sidwizard/kestrel_sw_files.c);
//            Tab Tab (the owner-only code, the dialog's file selector), Return: into C:; Tab, M Y S O N G, Return
//   ON DISK  C:\MYSONG.SWM is the floppy's FLASHBAK.SWM byte for byte past its 2-byte load address (where the
//            song sat in the C64's memory, not part of the song), read back with mtools
// --break write: the host refuses every write (EWRPRO, a C: with no writes): no MYSONG.SWM, caught.
//   node apps/sidwizard_save.mjs [--break write] [--png <dir>]
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { machine, step, picture, png } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";

const CART = "docs/demo-sidwizard.wasm", DISK = "docs/demo-sidwizard.zmd", C_IMAGE = "docs/gemdos-c.img";
const SONG = "apps/ports/sidwizard/data/FLASHBAK.SWM";
const F8 = 0xe008, TAB = 0xe019, ENTER = 13, UP = 0, DOWN = 1;
const key = (f, k) => [[f, (d) => d.key(k)], [f + 4, (d) => d.keyUp(k)]];
const arrow = (f, dir) => [[f, (d) => d.input(dir)], [f + 4, (d) => d.inputRelease(dir)]];
const EVENTS = [...key(320, F8), ...arrow(345, UP), ...key(365, ENTER), ...key(400, TAB), ...key(420, TAB), ...key(440, ENTER),
    ...key(470, TAB), ...[..."mysong"].flatMap((c, i) => key(490 + 10 * i, c.charCodeAt(0))), ...key(560, ENTER)];
const FRAMES = 700, SHOTS = [400, 460, 550, 700];

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && broke !== "write") throw new Error(`--break ${broke}: write`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

console.log(`sidwizard_save: SID-Wizard off ${DISK} saves to C: = a copy of ${C_IMAGE}${broke ? ` (--break ${broke})` : ""}`);
const img = new Uint8Array(await readFile(C_IMAGE));
const m = await machine(await readFile(DISK));
m.env.kosDriveRead = makeCDrive(m.memory, img);
const serve = makeCFile(m.memory, img), answers = [];
m.env.kosFileOp = (req) => { const r = broke === "write" ? -13 : serve(req); answers.push(r); return r; };
const gem = await launchFromGem(m, CART);
check("GEM runs BOOT.WSM, the committed cart", gem.name === "BOOT.WSM" && gem.same);
const shots = new Map();
for (let f = 1; f <= FRAMES; f++) {
    for (const [ef, fn] of EVENTS) if (ef === f) fn(m.demo);
    step(m);
    if (SHOTS.includes(f)) shots.set(f, picture(m));
}
check("the song opened off the floppy at start", m.log.includes("sidwizard: song opened"));
check("the save reached C: (env.kosFileOp asked)", answers.length > 0, `${answers.length} request(s): ${JSON.stringify(answers.slice(0, 8))}`);
const dir = await mkdtemp(`${tmpdir()}/sidwizard_save_`);
await writeFile(`${dir}/c.img`, img);
let saved = null;
try { saved = execFileSync("mtype", ["-i", `${dir}/c.img`, "::HD/MYSONG.SWM"], { stdio: ["ignore", "pipe", "pipe"] }); } catch { saved = null; }
const song = await readFile(SONG);
check("C:\\MYSONG.SWM is there", saved !== null, saved ? `${saved.length} bytes` : "mtype found no ::HD/MYSONG.SWM");
check("it is the song, byte for byte (past the load address)", saved && saved.length === song.length && saved.subarray(2).equals(song.subarray(2)),
    saved ? `${saved.length} vs ${song.length} bytes` : "nothing to compare");
await rm(dir, { recursive: true, force: true });
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [f, p] of shots) await png(p, `${pngDir}/sidwizard_save_${f}.png`);
}
if (broke) {
    console.log(failures ? `\nsidwizard_save: PASS (--break ${broke} was caught)` : `\nsidwizard_save: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nsidwizard_save: ${failures} FAILED` : "\nsidwizard_save: PASS");
process.exit(failures ? 1 : 0);
