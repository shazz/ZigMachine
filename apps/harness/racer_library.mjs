// Headless RACER's track library (R82 Kestrel Racing M5 step 2, apps/zig/scenes/racer/library.zig, docs/ports/kestrel_racing/M5.md):
//   1. no disk: the built-in oval only (t stays on it, nothing loads, no trap);
//   2. the shelf disk: OVAL CITY SALT NEON GLACIER listed, in the disk's order (tools/mkdisks.sh);
//   3. a corrupted SALT.KTR (one byte of its packed bytes flipped): refused by name, skipped from then on, the others still load;
//   4. a user's track on C: (a FAT image built here: \HD\RACER\MYTRACK.KTR, Salt Flats' RAW binary, through KOS GEMDOS and
//      env.kosDriveRead as the page serves it): listed after the disk's, loaded and flown; a file that is not a track
//      (\HD\RACER\NOTES.KTR) is refused at the scan.
//   node apps/harness/racer_library.mjs
import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { diskHook, fatEntry, ZMD } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";

const errors = [];
const fail = (m) => errors.push(m);

async function run(hook, keys, frames = 3) {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), hook);
    for (const k of keys) { key(S, k); for (let i = 0; i < frames; i++) S.frame(); }
    const csv = log.filter((l) => l.startsWith("racer,csv,")).pop();
    return { log, track: csv ? csv.split(",")[3] : null, loads: log.filter((l) => l.startsWith("racer,load,")).map((l) => l.split(",")[2]) };
}
const listed = (r) => r.log.filter((l) => l.startsWith("racer,track,") && !l.includes("refused")).map((l) => l.split(",")[2]).join(" ");

// A C: image (tools/kos_fat_fixture.py, the MP3 player's C: builder) holding \HD\RACER\MYTRACK.KTR and a non-track.
const CIMG = `
import sys; sys.path[:0] = ["tools", "fpga/tools"]
import sd_layout; from kos_fat_fixture import Image
img = Image("SD CARD", 2048); hd = sd_layout.HD
img.mkdir(hd); img.mkdir(hd + "/RACER")
img.write(hd + "/RACER/MYTRACK.KTR", open("apps/zig/assets/screens/racer/salt.ktrk", "rb").read())
img.write(hd + "/RACER/NOTES.KTR", b"not a track\\r\\n")
sys.stdout.buffer.write(img.bytes())`;

const bare = await run(undefined, ["t", "t", "t", "l"], 40);
if (!bare.log.some((l) => l.startsWith("racer: 1 tracks")) || bare.loads.length || bare.track !== "OVAL") fail(`no disk: want the oval only, got ${bare.track} loads ${bare.loads}`);
const full = await run(diskHook(), []);
if (listed(full) !== "OVAL CITY SALT NEON GLACIER") fail(`the library lists ${listed(full)}`);
const img = new Uint8Array(await readFile(ZMD));
const e = fatEntry(img, "SALT.KTR");
img[e.start + (e.len >> 1)] ^= 0xa5; // a byte in the middle of the packed track
const bad = await run(diskHook(img), ["t", "t", "t", "t", "l"], 40);
const refused = bad.log.find((l) => l.startsWith("racer,track,refused,SALT"));
// t: CITY, SALT refused (back on the oval), CITY, then NEON: the bad file is skipped from then on
if (!refused || bad.loads.join(" ") !== "CITY CITY NEON" || bad.track !== "NEON") fail(`a corrupted SALT.KTR: ${refused}; loads ${bad.loads}; on ${bad.track}`);
const cimg = new Uint8Array(execFileSync("python3", ["-I", "-c", CIMG], { maxBuffer: 8 << 20 }));
const hd = await run((env) => { diskHook()(env); env.kosDriveRead = makeCDrive(env.memory, cimg); }, ["t", "t", "t", "t", "t", "l"], 40);
const notes = hd.log.find((l) => l.startsWith("racer,track,refused,NOTES"));
if (listed(hd) !== "OVAL CITY SALT NEON GLACIER MYTRACK" || !notes || hd.loads.at(-1) !== "MYTRACK" || hd.track !== "MYTRACK")
    fail(`C:\\RACER: lists ${listed(hd)}; ${notes}; loads ${hd.loads}; on ${hd.track}`);
if (errors.length) { for (const m of errors) console.error(`racer_library: ${m}`); process.exit(1); }
console.log(`racer_library: PASS (no disk = the oval; OVAL CITY SALT NEON GLACIER listed; a corrupted file refused: ${refused}; C:\\RACER\\MYTRACK.KTR listed and flown, NOTES.KTR refused)`);
