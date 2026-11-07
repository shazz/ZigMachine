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
//  3. Folders (Matt on the board, 6 Nov 2026: C:\, PICTURES, then PLASMA opened a NEW window
//     each time): as on TOS 1.00, a folder opens INSIDE its drive's window (rom/gem/desktop/
//     desknav.zig), so that window's close box goes back up one level and closes it only at the
//     root. Held by frames: GAMES then its close box (where A:\'s was) = A:\ opened alone; again
//     = the empty desktop; GAMES, LEVELS, close box = GAMES alone; GAMES, File > Close Window = the
//     empty desktop. A window per folder (main 0e47697e's ROM, run with MACHINE_DIR) fails that
//     last one: in low res its cascade wraps, so GAMES's window sat exactly over A:\'s, and
//     closing it left A:\ behind.
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
// The session's total over every frame, taken from a desktop that repaints every frame: the skip
// must not move a pixel. First from main ef337055 (before deskdirty.zig); re-taken 6 Nov 2026 when
// GAMES started opening inside A:\'s window (desknav.zig) instead of a window of its own, from this
// ROM with deskdirty.mustDraw forced true; the skipping ROM gives the same total.
const PIN = "06930a66389eaf65ffa0c0f50079229eac7288db7104039c51cec24d4ae4aa1c";

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

// 3. Folders in place. Each case ends with the pointer parked on the bare desktop, so equal frames
// mean equal desktops. CLOSE is the root window's close box (logical 2,24: A:\ opens there).
const PARK = (f) => ptr(f, 600, 190, 0), CLOSE = (f) => click(f, 12, 29);
const GAMES = dbl(40, 505, 65), LEVELS = dbl(80, 220, 70); // A:\GAMES, then its LEVELS
const FOLDER_CASES = [ // [what, the session, the session it must equal, a window must show]
    ["GAMES's close box goes back up to A:\\ in the same window (= A:\\ opened alone)",
        [...OPEN_A, ...GAMES, ...CLOSE(120), ...PARK(140)], [...OPEN_A, ...PARK(140)], true],
    ["a second click closes the window at the root (= the desktop before anything opened)",
        [...OPEN_A, ...GAMES, ...CLOSE(120), ...CLOSE(140), ...PARK(160)], [...PARK(160)], false],
    ["LEVELS opened inside GAMES, then its close box: back to GAMES, one level up",
        [...OPEN_A, ...GAMES, ...LEVELS, ...CLOSE(120), ...PARK(140)], [...OPEN_A, ...GAMES, ...PARK(140)], true],
    // The one that tells the ROMs apart: on a low-res screen the old cascade wraps, so GAMES's own window
    // opened exactly over A:\'s and the cases above looked the same; Close Window then left A:\ behind it.
    ["GAMES, then File > Close Window: one window, so the desktop is empty",
        [...OPEN_A, ...GAMES, ...ptr(120, 120, 4, 0), ...click(130, 220, 55), ...PARK(160)], [...PARK(160)], false],
    ["GAMES, then File > Close: up one level, as the close box (= A:\\ opened alone)",
        [...OPEN_A, ...GAMES, ...ptr(120, 120, 4, 0), ...click(130, 220, 47), ...PARK(160)], [...OPEN_A, ...PARK(160)], true],
];
const lastHash = (args) => hashes(190, 190, args).samples.at(-1).hash;

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
    const empty = lastHash([...kos, ...PARK(160)]);
    for (const [what, run, same, shown] of FOLDER_CASES) { // `shown`: equal to an empty desktop proves nothing
        const got = lastHash([...kos, ...run]);
        check(what, got === lastHash([...kos, ...same]) && (!shown || got !== empty));
    }
    const o = parseArgs(["--warmup", "40", "--frames", "20", "--disk", a, "--c-image", C_IMG,
        "--call", "1:insertDisk:2", ...OPEN_C]);
    const r = await costOf(CART, o);
    check(`C:'s window open costs ${r.mc.avg} Mc a frame (< ${MAX_MC})`, r.mc.avg < MAX_MC);
    check(`no C: read in the frame path (${r.kosReads} a frame)`, r.kosReads === 0);
}

main().catch((e) => { console.error(e.stack ?? e.message); process.exit(2); });
