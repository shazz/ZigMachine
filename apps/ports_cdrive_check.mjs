// KOS C: in the C ports (docs/KOS_GEMDOS.md §5): pt2-clone and klystrack launched from GEM over their floppies,
// with C: = a copy of docs/gemdos-c.img that carries one song (HD/MODS/GLENZ.MOD for pt2, HD/SONGS/STARPORT.KT for
// klystrack), and the program's own file browser reaches it: pt2 by its PATH field ("/C/MODS"), klystrack by its
// Open song box (a "C" folder at the floppy's root, then SONGS). The ORACLE: the song loaded off C: gives the same
// frame, hash for hash, as the same bytes loaded off the floppy; a browser that never reached C: does not.
//   node apps/ports_cdrive_check.mjs <pt2|klystrack> [--break c|bytes|list] [--png <dir>]
// --break SABOTAGES and passes only if caught:
//   c      C: answers nothing (kosDriveRead 0): the browser cannot reach it
//   bytes  the song's title on C: changed: the loaded frame must differ from the floppy's
//   list   the browser is never asked for C:'s folder: its listing stays the floppy's root
import { readFile, mkdtemp, copyFile, mkdir, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { machine, step, picture, sha, png } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";

const GEMDOS_IMG = "docs/gemdos-c.img";
const MOD = "docs/music/hybridglenz.mod"; // pt2: the floppy's HYBRID.MOD is these bytes; C: carries them as HD/MODS/GLENZ.MOD
const KT = "apps/ports/klystrack/data/STARPORT2.KT"; // klystrack: the floppy's STARPORT2.KT; C: carries it as HD/SONGS/STARPORT.KT

// pt2 coordinates: its 320x255 screen sits 28 rows above the window (apps/ports_headless.mjs).
const pt2At = (f, x, y, b) => [f, (d) => d.pointer(x * 2, y - 28, b)];
// klystrack coordinates (the program's own): pointer (2x, y - 20) (apps/ports/klystrack/kestrel_main.c's origin).
const kAt = (f, x, y, b) => [f, (d) => d.pointer(x * 2, y - 20, b)];
const click = (at) => (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 6, x, y, 0)];
const dbl = (at) => (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 3, x, y, 0), at(f + 5, x, y, 1), at(f + 8, x, y, 0)];
const key = (f, k) => [[f, (d) => d.key(k)], [f + 2, (d) => d.keyUp(k)]];
const typeText = (f, s) => [...s].flatMap((ch, i) => key(f + 3 * i, ch.codePointAt(0)));
const backspaces = (f, n) => Array.from({ length: n }, (_, i) => key(f + 2 * i, 8)).flat();
const CTRL = 0xe014;

const SPECS = {
    pt2: {
        cart: "docs/demo-pt2.wasm", disk: "docs/demo-pt2.zmd",
        // the card: a copy of docs/gemdos-c.img with the song in HD/MODS
        card: async (img, sabotage) => {
            await copyFile(GEMDOS_IMG, img);
            const song = `${img}.mod`;
            const bytes = Buffer.from(await readFile(MOD));
            if (sabotage) bytes[0] = 0x78; // the title's "s" of "setup2" becomes "x": the song name row
            await writeFile(song, bytes);
            execFileSync("mmd", ["-i", img, "::HD/MODS"]);
            execFileSync("mcopy", ["-i", img, "-o", song, "::HD/MODS/GLENZ.MOD"]);
        },
        // DISK OP (212,38) opens on the floppy's root; a click in PATH (0..237, 22..32) enters its text edit;
        // backspaces clear it, "/C/MODS" and Return chdir there (pt2_textedit.c: diskOpSetPath); row 1 of the
        // folder (y 34 + 6 n, row 0 is "..") loads GLENZ.MOD
        viaC: (broke) => [...(broke === "list" ? [] : [
            ...click(pt2At)(100, 212, 38), ...click(pt2At)(130, 100, 27), ...backspaces(140, 20),
            ...typeText(184, "/C/MODS"), ...key(210, 13)]),
            ...click(pt2At)(280, 100, 42), // GLENZ.MOD
            ...click(pt2At)(330, 150, 5)], // PLAY
        viaCShots: { root: 125, listed: 260, loaded: 320, played: 360 },
        oracle: [...click(pt2At)(100, 212, 38), ...click(pt2At)(130, 100, 36)], // HYBRID.MOD, the floppy root's first row
        oracleShot: 180,
        at: pt2At, park: (at) => at(300, 250, 200, 0),
    },
    klystrack: {
        cart: "docs/demo-klystrack.wasm", disk: "docs/demo-klystrack.zmd",
        card: async (img, sabotage) => {
            await copyFile(GEMDOS_IMG, img);
            const song = `${img}.kt`;
            const bytes = Buffer.from(await readFile(KT));
            if (sabotage) bytes[50] = 0x58; // "Starport" (the song's title) becomes "Xtarport"
            await writeFile(song, bytes);
            execFileSync("mmd", ["-i", img, "::HD/SONGS"]);
            execFileSync("mcopy", ["-i", img, "-o", song, "::HD/SONGS/STARPORT.KT"]);
        },
        // Ctrl+O (Open song, docs: shortcutdefs.c); the box lists "C" first at the floppy's root (patches/filebox.c.sed):
        // double-click it (x 45, y 81 in the program's coordinates), then SONGS (60, 101), then STARPORT.KT (60, 90)
        viaC: (broke) => [
            ...(broke === "list" ? [] : [
                [100, (d) => d.key(CTRL)], [101, (d) => d.key(0x6f)], [103, (d) => d.keyUp(0x6f)], [106, (d) => d.keyUp(CTRL)],
                ...dbl(kAt)(139, 45, 81), ...dbl(kAt)(199, 60, 101), ...dbl(kAt)(240, 60, 90)])],
        viaCShots: { root: 125, listed: 230, loaded: 320 },
        // the same box on the floppy: STARPORT2.KT is its fourth row (after CASTLEVANIA, DPINTRO, OCEANLOADER3)
        oracle: [[100, (d) => d.key(CTRL)], [101, (d) => d.key(0x6f)], [103, (d) => d.keyUp(0x6f)], [106, (d) => d.keyUp(CTRL)],
            ...dbl(kAt)(139, 60, 109)],
        oracleShot: 320,
        at: kAt, park: (at) => at(300, 100, 200, 0),
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

// One session: GEM over the floppy, the program launched, the events, a picture at each frame asked.
async function session(disk, events, shots, image) {
    const m = await machine(await readFile(disk));
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
const img = `${dir}/card.img`;
if (broke !== "c") await spec.card(img, broke === "bytes");
const image = broke === "c" ? null : new Uint8Array(await readFile(img));
console.log(`ports_cdrive ${tag}: ${spec.disk} off GEM, C: = ${GEMDOS_IMG} + its song${broke ? ` (--break ${broke})` : ""}`);
const viaC = await session(spec.disk, [...spec.viaC(broke), spec.park(spec.at)], spec.viaCShots, image);
const viaFloppy = await session(spec.disk, [...spec.oracle, spec.park(spec.at)], { loaded: spec.oracleShot }, null);
const h = Object.fromEntries(Object.entries(viaC.pics).map(([k, p]) => [k, sha(p.px)]));
const hf = sha(viaFloppy.pics.loaded.px);
check("the browser reaches /C: its listing is not the floppy's root", h.listed !== h.root, `root ${h.root.slice(0, 12)} vs listed ${h.listed.slice(0, 12)}`);
check("the song loaded from /C equals the floppy's copy, frame for frame", h.loaded === hf, `${h.loaded.slice(0, 16)}... vs ${hf.slice(0, 16)}...`);
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [k, p] of Object.entries(viaC.pics)) await png(p, `${pngDir}/cdrive_${tag}_${k}.png`);
}
if (broke) {
    console.log(failures ? `\nports_cdrive ${tag}: PASS (--break ${broke} was caught)` : `\nports_cdrive ${tag}: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\nports_cdrive ${tag}: ${failures} FAILED` : `\nports_cdrive ${tag}: PASS`);
