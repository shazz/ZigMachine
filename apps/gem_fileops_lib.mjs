// The rig of apps/gem_fileops_check.mjs: a C: card and a drive-A floppy built with mtools, the GEM
// shell booted over them (gem_headless.mjs: machine + ROM + shell, C:'s writes through KFS as the page
// serves them), the desktop's file-operation mailbox read back (rom/sdk/deskop.zig), and the image
// read back through mtools and fsck.fat.
import { execFileSync } from "node:child_process";
import { writeFileSync, readFileSync, mkdirSync } from "node:fs";
import { bootGem } from "./gem_headless.mjs";
import { makeCFile } from "./scene_hash_disk.mjs";
import { pickRes, settle, res, deskPicture, RES_DESK, W as DW, H as DH } from "./gem_desk_lib.mjs";
import { png } from "./ports_machine.mjs";

// Deterministic contents: the same bytes on every run, different per file.
export const bytesOf = (n, seed) => Buffer.from(Array.from({ length: n }, (_, i) => (i * 31 + seed * 7 + (i >> 8)) & 255));
export const FILES = {
    "ECHO.REQ": Buffer.from("ping\r\n"), "BIG.DAT": bytesOf(70000, 1), "NET/INNET.TXT": Buffer.from("in net\r\n"),
    "PAIR/A.TXT": Buffer.from("the first of two\r\n"), "PAIR/B.DAT": bytesOf(70000, 2),
    "PICTURES/WAVES.PI1": bytesOf(32034, 3), "PICTURES/PLASMA/PLASMA.PI1": bytesOf(32034, 4),
};
const FOLDERS = ["MUSIC", "NET", "PAIR", "PICTURES", "PICTURES/PLASMA"]; // C:\'s root: BIG ECHO, then these four

const mt = (img, cmd, ...a) => execFileSync(cmd, ["-i", img, ...a], { stdio: ["ignore", "pipe", "pipe"] });

/** A FAT12 card of `kb` KB whose HD\ is C:\ (fpga/glass/src/layout.zig), `filler` bytes eaten by FILL.BIN. */
export function card(dir, name, kb = 1440, filler = 0) {
    mkdirSync(dir, { recursive: true });
    const img = `${dir}/${name}.img`;
    execFileSync("mformat", ["-C", "-i", img, "-f", String(kb), "-v", "SDCARD", "::"]);
    mt(img, "mmd", "::HD", ...FOLDERS.map((f) => `::HD/${f}`));
    for (const [path, data] of Object.entries(FILES)) put(dir, img, `HD/${path}`, data);
    if (filler) put(dir, img, "FILL.BIN", Buffer.alloc(filler, 0xa5));
    return img;
}

/** Drive A: a 720 KB FAT12 floppy holding FLOPPY.TXT. */
export function floppy(dir) {
    const img = `${dir}/a.st`;
    execFileSync("mformat", ["-C", "-i", img, "-f", "720", "::"]);
    put(dir, img, "FLOPPY.TXT", FLOPPY_TXT);
    return img;
}
export const FLOPPY_TXT = Buffer.from("from the floppy\r\n");

function put(dir, img, path, data) {
    const tmp = `${dir}/put.bin`;
    writeFileSync(tmp, data);
    mt(img, "mcopy", "-o", tmp, `::${path}`);
}

/** The file at `path` on the image (bytes), or null. */
export function read(img, path) {
    try { return mt(img, "mtype", `::${path}`); } catch { return null; }
}
/** The names in folder `path` ("" for none such). */
export function names(img, path) {
    try { return mt(img, "mdir", "-b", `::${path}`).toString().split("\n").filter(Boolean).map((l) => l.split("/").at(-1)).sort(); } catch { return null; }
}
/** fsck.fat -n's complaint, "" for a clean disk. */
export function fsck(img) {
    try { execFileSync("fsck.fat", ["-n", img], { stdio: "pipe" }); return ""; } catch (e) { return String(e.stdout || e.message).split("\n").slice(1, 3).join(" "); }
}
/** Every ~KOS?.TMP left anywhere under HD (a save that was not dropped). */
export function temps(img) {
    return mt(img, "mdir", "-/", "-b", "::HD").toString().split("\n").filter((l) => /~KOS/.test(l));
}

// The mailbox (rom/sdk/deskop.zig Box): its u32 fields by name.
const BOX = { phase: 0, op: 1, status: 2, kept: 3, answer: 4, seq: 5, folders: 6, files: 7, bytes: 8, folders_left: 9, files_left: 10 };
export const PHASE = { idle: 0, count: 1, counted: 2, run: 3, conflict: 4, answer: 5, done: 6 };

/** GEM over `cImg` (written in place, `hook` sees each request first), drive A `aImg`, in `mode`. */
export async function desktop(cImg, aImg, mode = "low", hook = null, bits = 0) {
    const img = new Uint8Array(readFileSync(cImg)), a = aImg ? readFileSync(aImg) : null;
    const cFileOp = (m) => { const serve = makeCFile(m, img); return (req) => (hook ? hook(m, req, serve) : serve(req)); };
    const diskReadBlock = (m) => (b, dst) => {
        if (!a || (b + 1) * 512 > a.length) return 0;
        new Uint8Array(m.buffer, dst, 512).set(a.subarray(b * 512, b * 512 + 512));
        return 512;
    };
    const gem = await bootGem({ cImage: img, cFileOp, diskReadBlock, deskAvailable: 1 });
    if (a && !aImg.endsWith(".zmd")) { gem.demo.insertDisk(2); settle(gem, 4); } // a .zmd: the caller hands its listing (gem.mount)
    const low = () => gem.machine.hwPhysWidth() && new DataView(gem.memory.buffer, gem.machine.hwVideoBase()).getUint8(0) === 0;
    const host = (x, y) => [low() ? 2 * x : x, y];
    const ui = {
        gem, img, mode,
        save: () => writeFileSync(cImg, img),
        click: (x, y) => gem.click(...host(x, y)),
        open: (x, y) => { gem.open(...host(x, y)); settle(gem, 12); },
        point: (x, y, b) => gem.point(...host(x, y), b),
        drag: (from, to) => { gem.drag(...host(...from), ...host(...to), 8); settle(gem, 2); },
        key: (k) => gem.key(k),
        keyUp: (k) => { gem.demo.keyUp(k); gem.frame(); },
        type: (s) => { for (const c of s) gem.key(c.charCodeAt(0)); },
        box: (f) => new Int32Array(gem.memory.buffer, gem.rom.deskFileOp(), 11)[BOX[f]],
        settle: (n = 4) => settle(gem, n),
    };
    if (mode !== "low") pickRes(gem, ui.click, "medium", 320, 200);
    if (mode.startsWith("desk")) pickRes(gem, ui.click, "desk", 640, 200);
    if (mode === "desk1" || bits) gem.rom.deskSetEngine((mode === "desk1" ? 1 : 0) | bits); // 1: GEM 5's engine, flat; bits: rom/gem/desktop/deskbreak.zig
    ui.click(117, 8); ui.click(145, 23); settle(gem, 4); // View > Show as Text: rows, easy to aim at
    return ui;
}

/** Frames until the operation is over (the box idle again) or asks (NAME CONFLICT); `seen` collects
 * files_left as it counts down. True when it ended. */
export function runOut(ui, seen = [], max = 400) {
    for (let i = 0; i < max && ui.box("phase") !== PHASE.idle && ui.box("phase") !== PHASE.conflict; i++) {
        if (ui.box("phase") === PHASE.run) seen.push(ui.box("files_left"));
        ui.gem.frame();
    }
    ui.settle(4);
    return ui.box("phase") === PHASE.idle;
}

/** The screen as a PNG (apps/ports_machine.mjs's writer), for --png and for looking. */
export function shot(ui, path) {
    const m = ui.gem.machine;
    if (res(ui.gem) === RES_DESK) return png({ W: DW, H: DH, px: deskPicture(ui.gem) }, path);
    m.hwRenderPlane(0);
    const W = m.hwPhysWidth(), H = m.hwPhysHeight();
    return png({ W, H, px: new Uint8Array(ui.gem.memory.buffer, m.hwPhysicalPtr(), W * H * 4).slice() }, path);
}
