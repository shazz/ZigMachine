// KOS GEMDOS phase 2's proof in a real program (docs/KOS_GEMDOS.md §7): GrafX2 SAVES a picture to C:, and it
// is there afterwards. GrafX2 is started from GEM over its floppy (apps/ports_gem.mjs), C: = a copy of
// docs/gemdos-c.img, its writes served by KFS as the page serves them (docs/kos-cfile.js, kos-cfs.wasm).
//   SAVE     F3, the floppy's ZIGPLASM.PI1 loaded; F2 (Save picture as), Select drive, /C, PICTURES, the
//            file name typed: NEW, Enter (GrafX2 adds .pi1): ONE env.kosFileOp request, answered 0
//   ON DISK  the image after it: C:\PICTURES\NEW.PI1 is the floppy's picture byte for byte (mtools, when
//            installed: fsck.fat -n clean too)
//   RELOAD   a new session over that image: F3, /C, PICTURES lists NEW.PI1 (the view pinned), double-
//            clicked: the picture's rows equal, hash for hash, those of the floppy's own copy loaded (the
//            status line below names the file, so it differs)
// --break SABOTAGES and passes only if caught:
//   write  the host refuses every write (EWRPRO, as a C: with no writes): no NEW.PI1
//   torn   the host's disk stops taking sectors half way through the save (a crash): no whole NEW.PI1
//   bytes  a byte of the picture is changed on its way to the host: the reload differs
//   node apps/gemdos_grafx2_save.mjs [--break write|torn|bytes] [--png <dir>] [--out <img>]
import { readFile, writeFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { machine, step, picture, rows, sha, png } from "./ports_machine.mjs";
import { launchFromGem } from "./ports_gem.mjs";
import { makeCDrive, makeCFile } from "./scene_hash_disk.mjs";

const CART = "docs/demo-grafx2.wasm", DISK = "docs/demo-grafx2.zmd", C_IMAGE = "docs/gemdos-c.img";
const PICTURE = "apps/ports/grafx2/ownpics/ZIGPLASMA.PI1"; // the floppy's ZIGPLASM.PI1
const F2 = 0xe002, F3 = 0xe003, ENTER = 13;
const PINS = {
    named: "475b4fa6d5bd4041e75e018d708a37efe2573a3e1aad2bf1863b2fbcf1141dfe", // frame 528: the save selector in C:\PICTURES, "NEW" typed
    relisted: "d82fe1947e4ff941d68fbca4a9fc9ccc6d0515f033fd9d8204d7f86df39d97e5", // frame 258 of the reload: C:\PICTURES with NEW.PI1
};
const at = (f, x, y, b) => [f, (d) => d.pointer(x * 2, y, b)];
const click = (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 6, x, y, 0)];
const twice = (f, x, y) => [at(f - 1, x, y, 0), at(f, x, y, 1), at(f + 1, x, y, 0), at(f + 3, x, y, 1), at(f + 4, x, y, 0)];
const key = (f, k) => [[f, (d) => d.key(k)], [f + 2, (d) => d.keyUp(k)]];
const START = [...click(100, 160, 163), ...key(130, F3)]; // OK on the read-only warning, then Load picture
const LOAD_FLOPPY = [...START, ...twice(160, 30, 114)]; // the floppy's ZIGPLASM.PI1, its third row
// F2, Select drive, /C, PICTURES, the file name field, N E W, Enter (the rows as apps/gemdos_grafx2_check.mjs)
const SAVE = [...LOAD_FLOPPY, ...key(350, F2), ...click(390, 37, 28), ...twice(420, 30, 107), ...twice(460, 30, 105),
    ...click(500, 150, 50), ...key(510, 78), ...key(514, 69), ...key(518, 87), ...key(530, ENTER)];
const RELOAD = [...START, ...click(160, 37, 28), ...twice(190, 30, 107), ...twice(230, 30, 105), ...twice(290, 30, 114)];
const PICTURE_ROWS = [40, 180]; // physical rows: the picture, the pointer on it, not the menu
const SHOTS_SAVE = { named: 528, saved: 600 }, SHOTS_RELOAD = { relisted: 258, loaded: 338 }, SHOTS_FLOPPY = { loaded: 338 };

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : ""; };
const broke = opt("--break"), pngDir = opt("--png"), out = opt("--out");
if (broke && !["write", "torn", "bytes"].includes(broke)) throw new Error(`--break ${broke}: write, torn or bytes`);

let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// The host's writes, as the page makes them, with the --break sabotage in between.
function writes(m, img) {
    const serve = makeCFile(m.memory, img);
    const answers = [];
    return Object.assign((req) => {
        if (broke === "write") { answers.push(-13); return -13; }
        const w = new Uint32Array(m.memory.buffer, req, 12);
        if (broke === "bytes" && w[5] > 4000) new Uint8Array(m.memory.buffer, w[6], w[5])[4000] ^= 0xff;
        const r = serve(req);
        answers.push(r);
        return r;
    }, { answers });
}

// One session: GEM over the floppy, GrafX2 launched off it, the events, a picture at each frame asked.
async function session(events, shots, img) {
    const m = await machine(await readFile(DISK));
    const reads = makeCDrive(m.memory, img);
    m.env.kosDriveRead = (...a) => reads(...a);
    const op = writes(m, broke === "torn" ? tornView(img) : img);
    m.env.kosFileOp = op;
    const gem = await launchFromGem(m, CART);
    const last = Math.max(...Object.values(shots)), pics = {};
    for (let f = 1; f <= last; f++) {
        for (const [ef, fn] of events) if (ef === f) fn(m.demo);
        step(m);
        for (const [name, sf] of Object.entries(shots)) if (sf === f) pics[name] = picture(m);
    }
    return { gem, pics, answers: op.answers };
}

// --break torn: the image takes the save's first 20 sectors, then no more (a write that stops half way).
function tornView(img) {
    let left = 20;
    return new Proxy(img, {
        get(t, k) {
            if (k !== "set") { const v = Reflect.get(t, k); return typeof v === "function" ? v.bind(t) : v; }
            return (src, at) => { if (left-- > 0) t.set(src, at); };
        },
    });
}

function mtools(img, ...cmd) {
    try { return execFileSync(cmd[0], ["-i", img, ...cmd.slice(1)], { stdio: ["ignore", "pipe", "pipe"] }); } catch { return null; }
}

console.log(`gemdos_grafx2_save: GrafX2 off ${DISK} saves to C: = a copy of ${C_IMAGE}${broke ? ` (--break ${broke})` : ""}`);
const img = new Uint8Array(await readFile(C_IMAGE));
const saved = await session(SAVE, SHOTS_SAVE, img);
check("GEM runs BOOT.WSM, the committed cart", saved.gem.name === "BOOT.WSM" && saved.gem.same);
check("the save is ONE request, answered 0", saved.answers.length === 1 && saved.answers[0] === 0, JSON.stringify(saved.answers));
const dir = await mkdtemp(`${tmpdir()}/gemdos_save_`);
const file = `${dir}/c.img`;
await writeFile(file, img);
if (out) await writeFile(out, img);
const onDisk = mtools(file, "mtype", "::HD/PICTURES/NEW.PI1");
if (onDisk !== null || !broke) {
    const want = await readFile(PICTURE);
    check("C:\\PICTURES\\NEW.PI1 is the picture, byte for byte (mtools)", onDisk !== null && Buffer.compare(onDisk, want) === 0,
        onDisk === null ? "absent" : `${onDisk.length} bytes`);
    let fsck = "";
    try { execFileSync("fsck.fat", ["-n", file], { stdio: "pipe" }); } catch (e) { fsck = e.code === "ENOENT" ? "" : String(e.stdout); }
    check("fsck.fat -n finds the card clean", fsck === "", fsck.split("\n")[1] ?? "");
}
const reload = await session(RELOAD, SHOTS_RELOAD, img);
const floppy = await session(LOAD_FLOPPY, SHOTS_FLOPPY, new Uint8Array(await readFile(C_IMAGE)));
const h = { named: sha(saved.pics.named.px), relisted: sha(reload.pics.relisted.px) };
if (process.env.PINS) for (const k of Object.keys(PINS)) console.log(`  pin ${k}: ${h[k]}`);
for (const k of Object.keys(PINS)) if (PINS[k]) check(`view ${k}`, h[k] === PINS[k], h[k] === PINS[k] ? `${h[k].slice(0, 16)}...` : `got ${h[k]}`);
// The picture's rows (above GrafX2's menu, whose status line names the file: NEW.PI1 vs ZIGPLASM.PI1).
const back = sha(rows(reload.pics.loaded, ...PICTURE_ROWS)), want = sha(rows(floppy.pics.loaded, ...PICTURE_ROWS));
check("NEW.PI1 re-opened from C:\\PICTURES shows the floppy's picture", back === want && back !== sha(rows(reload.pics.relisted, ...PICTURE_ROWS)),
    `${back.slice(0, 16)}... vs ${want.slice(0, 16)}...`);
if (pngDir) {
    await mkdir(pngDir, { recursive: true });
    for (const [k, p] of Object.entries({ ...saved.pics, relisted: reload.pics.relisted, reloaded: reload.pics.loaded })) await png(p, `${pngDir}/save_${k}.png`);
}
await rm(dir, { recursive: true });
if (broke) {
    console.log(failures ? `\ngemdos_grafx2_save: PASS (--break ${broke} was caught)` : `\ngemdos_grafx2_save: FAILED - --break ${broke} was not caught`);
    process.exit(failures ? 0 : 1);
}
console.log(failures ? `\ngemdos_grafx2_save: ${failures} FAILED` : "\ngemdos_grafx2_save: PASS");
process.exit(failures ? 1 : 0);
