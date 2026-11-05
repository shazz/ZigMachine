// KOS's desktop on the board (docs/KOS_FAT.md, "The board's first run", 4 Nov 2026): the two bugs
// Matt found, held here so they stay fixed.
//
//  1. Redraw: the desktop repainted the whole screen, every icon and every open window each frame
//     (~1.1 Mc of ZIGGY with one C: window open), so the board fell to ~25 fps once a drive window
//     opened. It now repaints only when something changed (rom/gem/desktop/deskdirty.zig). Held two
//     ways: a scripted session (opens, a folder, a click, a window drag, a menu, idle gaps between)
//     hashed EVERY frame equals the pin taken from the desktop that repainted every frame, so the
//     skipped frames are pixel-exact; and apps/frame_cost.mjs with a C: window open stays under
//     MAX_MC, with no C: read in the frame path.
//  2. Drives: with a FAT floppy in drive A and a card in C: (docs/kos-c.img), opening A shows A's
//     files: the frame equals the one with no C: at all (the window covers C:'s icon), and differs
//     from C:'s window.
//
//   node apps/kos_desk_check.mjs [--pin]     (--pin: print the session's total, for a pin update)
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { inflateSync } from "node:zlib";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { costOf, parseArgs } from "./frame_cost.mjs";

const CART = process.env.KOS_DESK_CART ?? "docs/demo-gem.wasm", C_IMG = "docs/kos-c.img";
const MAX_MC = 1.7; // the board's 60 fps band starts at ~1.75 Mc (CLAUDE.md, Board speed)
// The session's total over every frame, taken from the desktop as it was before deskdirty.zig
// (main ef337055, which repainted every frame): the skip must not move a pixel.
const PIN = "5daf3d0ad917fbe58fee38c0e8604e50c952ed2eb9134c1f59f9ade2b6be035c";

const ptr = (f, x, y, b) => ["--call", `${f}:pointer:${x},${y},${b}`];
const click = (f, x, y) => [...ptr(f, x, y, 0), ...ptr(f + 5, x, y, 1), ...ptr(f + 6, x, y, 0)];
const dbl = (f, x, y) => [...click(f, x, y), ...ptr(f + 15, x, y, 2), ...ptr(f + 16, x, y, 0)];
const OPEN_A = dbl(5, 40, 30), OPEN_C = dbl(5, 40, 70);
const SESSION = [
    ...OPEN_A, ...ptr(40, 300, 100, 0), ...click(50, 300, 100), // A:\, a hover, a click in it
    ...dbl(70, 505, 65), // its GAMES folder
    ...ptr(98, 300, 28, 0), ...ptr(100, 300, 28, 1), ...ptr(102, 340, 48, 1), ...ptr(104, 380, 68, 1), ...ptr(106, 380, 68, 0), // its window dragged
    ...click(120, 600, 190), ...ptr(140, 120, 4, 0), ...click(150, 220, 55), // the desktop; File > Close Window (the zoom-box)
];

function hashes(frames, every, args) {
    const out = execFileSync("node", ["apps/scene_hash.mjs", CART, String(frames), String(every), ...args], { maxBuffer: 1 << 26 });
    return JSON.parse(out);
}

// The open window's listing at frame 40, as the page shows it (scene_png.mjs: RGBA, filter 0 rows):
// the window's content box only, so a drive icon peeking past its left edge does not count.
const BOX = { x0: 100, x1: 700, y0: 80, y1: 180 }; // picture pixels: borders included, low res doubled
function listing(dir, name, args) {
    const path = join(dir, `${name}.png`);
    execFileSync("node", ["apps/scene_hash.mjs", CART, "40", "40", ...args], { env: { ...process.env, SCENE_PNG: `40:${path}` } });
    const png = readFileSync(path);
    const w = png.readUInt32BE(16), idat = [];
    for (let at = 8; at < png.length; at += 12 + png.readUInt32BE(at))
        if (png.toString("latin1", at + 4, at + 8) === "IDAT") idat.push(png.subarray(at + 8, at + 8 + png.readUInt32BE(at)));
    const raw = inflateSync(Buffer.concat(idat)), row = w * 4 + 1;
    return Buffer.concat(Array.from({ length: BOX.y1 - BOX.y0 }, (_, i) =>
        raw.subarray((BOX.y0 + i) * row + 1 + BOX.x0 * 4, (BOX.y0 + i) * row + 1 + BOX.x1 * 4))).toString("base64");
}

function check(what, ok) {
    console.log(`kos_desk_check: ${ok ? "ok  " : "FAIL"} ${what}`);
    if (!ok) process.exitCode = 1;
}

function floppy() {
    const out = join(mkdtempSync(join(tmpdir(), "kos-desk-")), "kos.st");
    execFileSync("python3", ["tools/kos_fat_fixture.py", out]);
    return out;
}

async function main() {
    const a = floppy(), kos = ["--kos", a, "--post-frames", "0"];
    const s = hashes(180, 1, [...kos, "--c-image", C_IMG, ...SESSION]);
    if (process.argv.includes("--pin")) return console.log(s.total);
    check(`a session hashed every frame equals the every-frame repaint's (${s.total.slice(0, 12)})`, s.total === PIN);
    const dir = mkdtempSync(join(tmpdir(), "kos-desk-png-"));
    const both = listing(dir, "both", [...kos, "--c-image", C_IMG, ...OPEN_A]);
    const onlyA = listing(dir, "a", [...kos, ...OPEN_A]);
    const openC = listing(dir, "c", [...kos, "--c-image", C_IMG, ...OPEN_C]);
    check("drive A's window with C: mounted lists what it lists with no C: (the floppy, not the card)", both === onlyA);
    check("C:'s window lists something else", openC !== both);
    const o = parseArgs(["--warmup", "40", "--frames", "20", "--disk", a, "--c-image", C_IMG,
        "--call", "1:insertDisk:2", ...OPEN_C]);
    const r = await costOf(CART, o);
    check(`C:'s window open costs ${r.mc.avg} Mc a frame (< ${MAX_MC})`, r.mc.avg < MAX_MC);
    check(`no C: read in the frame path (${r.kosReads} a frame)`, r.kosReads === 0);
}

main().catch((e) => { console.error(e.stack ?? e.message); process.exit(2); });
