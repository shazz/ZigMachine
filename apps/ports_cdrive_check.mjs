// KOS C: in the C ports (docs/KOS_GEMDOS.md §5): pt2-clone, klystrack and ChipNomad launched from GEM over their
// floppies, with C: = a copy of docs/gemdos-c.img that carries one song in HD/MODS, and the program's own
// file browser reaches it by its path ("/C/..." in pt2's PATH field). The ORACLE: the song loaded off C: gives
// the same frame, hash for hash, as the same bytes loaded off the floppy; a browser that never reached C: does not.
//   node apps/ports_cdrive_check.mjs <pt2> [--break c|bytes|list] [--png <dir>]
// --break SABOTAGES and passes only if caught:
//   c      C: answers nothing (kosDriveRead 0): "/C/..." is refused and the browser stays on the floppy
//   bytes  the song's title on C: changed: the loaded frame must differ from the floppy's
//   list   the browser is never asked for C:'s folder: its listing stays the floppy's root
import { readFile, mkdtemp, copyFile, mkdir, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { machine, step, picture, sha, png } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";

const SONG = "docs/music/hybridglenz.mod"; // the floppy's HYBRID.MOD is these bytes; C: carries it as HD/MODS/GLENZ.MOD
const GEMDOS_IMG = "docs/gemdos-c.img";

// pt2 coordinates: its 320x255 screen sits 28 rows above the window (apps/ports_headless.mjs).
const at = (f, x, y, b) => [f, (d) => d.pointer(x * 2, y - 28, b)];
const click = (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 6, x, y, 0)];
const key = (f, k) => [[f, (d) => d.key(k)], [f + 2, (d) => d.keyUp(k)]];
const typeText = (f, s) => [...s].flatMap((ch, i) => key(f + 3 * i, ch.codePointAt(0)));
const backspaces = (f, n) => Array.from({ length: n }, (_, i) => key(f + 2 * i, 8)).flat();

const SPECS = {
    pt2: {
        cart: "docs/demo-pt2.wasm", disk: "docs/demo-pt2.zmd",
        // DISK OP (212,38) opens on the floppy's root (the PATH field shows it); a click in PATH (0..237, 22..32)
        // enters its text edit; backspaces clear it, "/C/MODS" and Return chdir there (pt2_textedit.c:
        // diskOpSetPath); a click on a row (y 34 + 6 n) loads that file
        browse: (f) => [...click(f, 212, 38), ...click(f + 30, 100, 27), ...backspaces(f + 40, 20),
            ...typeText(f + 84, process.env.CPATH ?? "/C/MODS"), ...key(f + 110, 13)],
        floppyLoad: (f) => [...click(f, 212, 38), ...click(f + 30, 100, 36)], // HYBRID.MOD, the floppy root's first row
        cLoad: (f) => [...click(f, 100, 42)], // GLENZ.MOD: row 1 of MODS, row 0 is ".." (pt2_diskop.c's list: (y - 34) / 6)
        play: (f) => [...click(f, 150, 5)],
    },
};

const args = process.argv.slice(2);
const tag = args[0];
const spec = SPECS[tag];
if (!spec) throw new Error(`usage: node apps/ports_cdrive_check.mjs <${Object.keys(SPECS).join("|")}> [--break c|bytes|list] [--png <dir>]`);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png");
if (broke && !["c", "bytes", "list"].includes(broke)) throw new Error(`--break ${broke}: c, bytes or list`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// A copy of the card with the song in HD/MODS (mtools: the card is FAT, shaped like the board's HD folder).
async function cardWithSong(dir, sabotage) {
    const img = `${dir}/card.img`, song = `${dir}/glenz.mod`;
    await copyFile(GEMDOS_IMG, img);
    const bytes = Buffer.from(await readFile(SONG));
    if (sabotage) bytes[0] = 0x78; // the title's "s" of "setup2" becomes "x": the song name row on the screen
    await writeFile(song, bytes);
    execFileSync("mmd", ["-i", img, "::HD/MODS"]);
    execFileSync("mcopy", ["-i", img, "-o", song, "::HD/MODS/GLENZ.MOD"]);
    return new Uint8Array(await readFile(img));
}

// One session: GEM over the floppy, the program launched, the events, a picture at each frame asked.
async function session(events, shots, image) {
    const m = await machine(await readFile(spec.disk));
    if (image) m.env.kosDriveRead = makeCDrive(m.memory, image);
    const gem = await launchFromGem(m, spec.cart);
    const last = Math.max(...Object.values(shots)), pics = {};
    for (let f = 1; f <= last; f++) {
        for (const [ef, fn] of events) if (ef === f) fn(m.demo);
        step(m);
        for (const [name, sf] of Object.entries(shots)) if (sf === f) pics[name] = picture(m);
    }
    return { gem, pics, audio: m.audio };
}

const dir = await mkdtemp(`${tmpdir()}/ports_cdrive_${tag}_`);
const image = broke === "c" ? null : await cardWithSong(dir, broke === "bytes");
console.log(`ports_cdrive ${tag}: ${spec.disk} off GEM, C: = ${GEMDOS_IMG} + HD/MODS/GLENZ.MOD${broke ? ` (--break ${broke})` : ""}`);
const browseEvents = broke === "list" ? [] : spec.browse(100);
// the pointer is drawn by pt2 itself: both runs park it at (250, 200) before the loaded picture is taken
const park = [at(300, 250, 200, 0)], parkFloppy = [at(160, 250, 200, 0)];
const viaC = await session([...browseEvents, ...spec.cLoad(280), ...park, ...spec.play(330)],
    { root: 125, listed: 260, loaded: 320, played: 360 }, image);
const viaFloppy = await session([...spec.floppyLoad(100), ...parkFloppy], { loaded: 180 }, new Uint8Array(await readFile(GEMDOS_IMG)));
const h = Object.fromEntries(Object.entries(viaC.pics).map(([k, p]) => [k, sha(p.px)]));
const hf = sha(viaFloppy.pics.loaded.px);
check("the browser reaches /C: its listing is not the floppy's root", h.listed !== h.root, `root ${h.root.slice(0, 12)} vs listed ${h.listed.slice(0, 12)}`);
check("the song loaded from /C equals the floppy's copy, frame for frame", h.loaded === hf, `${h.loaded.slice(0, 16)}... vs ${hf.slice(0, 16)}...`);
check("the song from /C plays", viaC.audio.peak > 8, `peak |s8| ${viaC.audio.peak}`);
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [k, p] of Object.entries(viaC.pics)) await png(p, `${pngDir}/cdrive_${tag}_${k}.png`);
}
if (broke) {
    console.log(failures ? `\nports_cdrive ${tag}: PASS (--break ${broke} was caught)` : `\nports_cdrive ${tag}: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nports_cdrive ${tag}: ${failures} FAILED` : `\nports_cdrive ${tag}: PASS`);
