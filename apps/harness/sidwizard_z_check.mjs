// SID-WIZARD Z (apps/zig/scenes/sidwizard_z.zig): SID-Wizard 1.97's editor with its UI in native Zig and Hermit's own 6502 player
// on libs/zig/players/cpu6502.zig, its SID on the BARD queue, started from GEM off its data disk (apps/harness/sidwizard_z_lib.mjs):
//   boot    GEM runs BOOT.WSM = the committed cart; plane 0 is on and the editor's picture is up (many colours, borders open: 400x280)
//   idle    a frame with nothing to do changes no pixel
//   song    FLASHBAK.SWM was opened off the floppy at start: F1 plays it, and its first 1000 SID writes are, register for
//           register and value for value, what the C cart (apps/ports/sidwizard: the whole C64 program on an emulated 6502) wrote
//   queue   the writes are on the page's SID live (BARD queue), none dropped; the player's ticks are paced by the sound side
//   stop    Run/Stop silences (attack/decay and sustain/release zeroed) and no write follows; Run/Stop again plays on
//   edit    Tab (CONTROL: next track), Down, Space (the editor starts in jam mode: edit on), W: a note lands in the pattern (the picture changes there)
//   save    F8 (the menu opens on SAVE TUNE), Return, a name, Return: C:\<name>.SWM is the floppy's song byte for byte when unedited,
//           and with the note typed differs from it, by a few bytes, and loads back (F8, LOAD TUNE shows it listed)
//   quit    Shift+F8 asks, Y asks the machine for request 4, GEM comes back
// --break sabotages one part and passes only if a check notices: silent (F1 never pressed), edit (no note typed), write (C: refuses
//   every write), quit (Y never pressed), bard (no sound side on this host), nodisk (the drive emptied: no start song).
//   node apps/harness/sidwizard_z_check.mjs [--break silent|edit|write|quit|bard|nodisk] [--png <dir>]
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { rig, K, DOWN, RIGHT, SONG } from "./sidwizard_z_lib.mjs";
import { png, colours, sha } from "./ports_machine.mjs";

const GOLDEN = "apps/zig/scenes/sidwizard_z/old_cart_sid.bin";
const BREAKS = ["silent", "edit", "write", "quit", "bard", "nodisk"];
const args = process.argv.slice(2);
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : ""; };
const brk = opt("--break"), pngDir = opt("--png");
if (brk && !BREAKS.includes(brk)) throw new Error(`--break ${BREAKS.join(" | ")}`);
let failures = 0;
const check = (name, ok, detail = "") => { if (!ok) failures++; console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`); };
const shots = {};

async function mtype(img, path) {
    const dir = await mkdtemp(`${tmpdir()}/sidwizard_z_`);
    await writeFile(`${dir}/c.img`, img);
    try { return execFileSync("mtype", ["-i", `${dir}/c.img`, `::HD/${path}`], { stdio: ["ignore", "pipe", "pipe"] }); } catch { return null; } finally { await rm(dir, { recursive: true, force: true }); }
}

console.log(`sidwizard_z_check: SID-WIZARD Z off site/carts/demo-sidwizard_z.zmd, C: = a copy of site/disks/gemdos-c.img${brk ? ` (--break ${brk})` : ""}`);
const song = await readFile(SONG), golden = await readFile(GOLDEN);
const d = await rig({ brk });
check("GEM runs BOOT.WSM off the data disk, the committed cart", d.m.launch.name === "BOOT.WSM" && d.m.launch.same, d.m.launch.name);
d.frame(30);
const pic0 = d.picture();
shots.boot = pic0;
check("plane 0 is on and the picture is the editor's (>= 8 colours, 280 lines of the 400-wide frame, doubled on the host)", colours(pic0) >= 8 && pic0.W === 800 && pic0.H === 280, `${colours(pic0)} colours, ${pic0.W}x${pic0.H}`);
d.frame(10);
check("the picture is still but for the cursor's flasher (the borders and the 26th row do not move)", sha(d.rows(0, 35)) === sha(pic0.px.subarray(0, 36 * pic0.W * 4)) && sha(d.rows(237, 279)) === sha(pic0.px.subarray(237 * pic0.W * 4)));

// --- song: F1 ---
if (brk !== "silent") d.key(K.F1);
d.frame(240);
const sid = () => d.sid().filter(([, a]) => a >= 0xd400 && a <= 0xd418);
const w = sid();
check("F1 plays: SID writes are on the BARD queue", w.length > 1000, `${w.length} writes`);
let same = w.length >= 1000;
for (let i = 0; i < Math.min(1000, w.length) && same; i++) same = w[i][1] - 0xd400 === golden[2 * i] && w[i][2] === golden[2 * i + 1];
check("its first 1000 writes are the C cart's, register for register", same);
shots.play = d.picture();

// --- stop / continue ---
const r0 = sid().length;
d.frame(40);
const rate = sid().length - r0; // writes in 40 frames of normal play
const n1 = sid().length;
d.key(K.ESC);
d.frame(6);
const n2 = sid().length;
const quiet = sid().slice(n1).filter(([, a, v]) => [5, 6, 12, 13, 19, 20].includes(a - 0xd400) && v === 0).length;
d.frame(120); // paused: the sound side's clock runs on
check("Run/Stop silences every channel's ADSR, then no write follows", quiet >= 6 && sid().length === n2, `${quiet} zeroed, ${sid().length - n2} after`);
d.key(K.ESC);
const c0 = sid().length;
d.frame(40);
const cont = sid().length - c0;
check("Run/Stop again plays on at the song's speed (no replay of the pause)", cont > rate * 0.5 && cont < rate * 1.6, `${cont} writes in 40 frames after the pause, ${rate} in 40 of normal play`);
const ts = d.sid().filter(([, a]) => a >= 0xd400 && a <= 0xd418).map(([tt]) => tt);
check("every stamp is at or after the one before (a pause never sends the past)", ts.every((v, i) => i === 0 || v >= ts[i - 1]));
d.key(K.ESC);
d.frame(10);

// --- save: F8 (the menu opens on SAVE TUNE), Return, a name, Return ---
const save = async (name) => {
    d.key(K.F8);
    d.key(13);
    d.frame(2);
    shots["save_" + name] = d.picture();
    d.type(name);
    d.key(13);
    d.frame(6);
    shots["saved_" + name] = d.picture();
    return mtype(d.img, `${name.toUpperCase()}.SWM`);
};
const plain = await save("plain");
check("saved as it was opened, C:\\PLAIN.SWM is the floppy's FLASHBAK.SWM byte for byte", plain !== null && plain.equals(song), plain ? `${plain.length} vs ${song.length} bytes` : "no file");

// --- edit: a note in track 2 ---
const before = sha(d.rows(36, 236));
if (brk !== "edit") { d.key(K.TAB); d.arrow(DOWN); d.key(0x20); d.key("w".charCodeAt(0)); }
d.frame(4);
shots.edited = d.picture();
const after = sha(d.rows(36, 236));
check("Tab, Down, Space (jam -> edit), W: the pattern changes (a note typed in track 2)", before !== after);

const edited = await save("mysong");
check("the save reached C: (the host was asked to write)", d.m.cWrites > 0, `${d.m.cWrites} request(s)`);
check("C:\\MYSONG.SWM is there", edited !== null, edited ? `${edited.length} bytes` : "mtype found no ::HD/MYSONG.SWM");
if (edited) {
    // the packed stream changes where the note went (the file may grow by a byte or two): the same start, the same end
    const n = Math.min(edited.length, song.length);
    let head = 0, tail = 0;
    while (head < n && edited[head] === song[head]) head++;
    while (tail < n - head && edited[edited.length - 1 - tail] === song[song.length - 1 - tail]) tail++;
    const mid = Math.max(edited.length, song.length) - head - tail;
    check("it is the song with the typed note (one place differs from the floppy's, a few bytes)", head > 64 && tail > 64 && mid > 0 && mid < 8, `${head} bytes alike at the start, ${tail} at the end, ${mid} between (${edited.length} vs ${song.length})`);
}

// --- load: F8, Down (LOAD TUNE), Return: the dialog lists C: then the floppy; the third entry is FLASHBAK ---
d.key(K.F8); d.arrow(DOWN); d.key(13); d.frame(4);
shots.load = d.picture();
const lp = shots.load.px, at = (260 * 4 + 100 * 800 * 4);
check("the file dialog is text on black (the repo's system font), not the editor's bar charset", lp[at] === 0 && lp[at + 1] === 0 && lp[at + 2] === 0 && colours(shots.load) >= 3);
d.arrow(RIGHT); d.arrow(RIGHT); d.key(13); d.frame(6);
const again = await save("again");
check("LOAD TUNE, FLASHBAK (listed off the floppy beside C:'s files): saved again it is the floppy's song (the edit is gone)", again !== null && again.equals(song), again ? `${again.length} bytes` : "no file");

const st = d.stats();
check("heard on SID live, nothing refused, dropped or re-anchored, over the whole session", st.mode === 1 && st.refused === 0 && st.dropped === 0 && st.resyncs === 0, JSON.stringify(st));

// --- quit ---
d.with(K.SHIFT, () => d.key(K.F8));
d.frame(2);
shots.exit = d.picture();
check("Shift+F8 asks (the picture changes)", sha(d.rows(36, 236)) !== after);
if (brk !== "quit") d.key("y".charCodeAt(0));
d.frame(30);
check("Y asks the machine for request 4 and GEM comes back", d.m.backs === 1);

if (pngDir) { await mkdir(pngDir, { recursive: true }); for (const [n, p] of Object.entries(shots)) await png(p, `${pngDir}/sidwizard_z_${n}.png`); }
if (brk) {
    console.log(failures ? `\nsidwizard_z_check: PASS (--break ${brk} was caught)` : `\nsidwizard_z_check: FAILED - --break ${brk} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nsidwizard_z_check: ${failures} FAILED` : "\nsidwizard_z_check: PASS");
process.exit(failures ? 1 : 0);
