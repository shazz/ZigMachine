// The KESTREL SDK's template cart, built the way an outside coder builds it (docs/SDK.md).
//
// sdk/template is copied OUTSIDE the repository (a fresh temp dir), its build.zig.zon pointed back
// at this checkout, and built with its own build.zig (sdk/build_cart.zig: the repo as a Zig
// package) and its own Makefile (`make floppy`). Then the cart runs on the real
// docs/machine-video.wasm + docs/rom.wasm, strictly linked (apps/ports_machine.mjs):
//   - it builds at all: a demo_main.zig import build.zig gained and sdk/build_cart.zig lacks fails here;
//   - plane 0 is on, the picture moves frame to frame (the scroller);
//   - the rasters are REAL: the window's left column, palette entry 0 on every line, takes 8+
//     colours down the screen, which only a per-line palette write (the copper's HBL) gives;
//   - the song it requests is a file under docs/music/;
//   - `make floppy` writes a bootable .zmd that carries the cart.
//
//   node apps/sdk_check.mjs [--break still|raster|song]
// --break edits the copied template so one check must fail; it exits 0 when that check catches it.
import { cpSync, mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { boot, step, picture, sha } from "./ports_machine.mjs";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const BREAKS = {
    // update() returns at once (a run-time test, so the code after it still compiles): nothing moves.
    still: ["void {\n        _ = zigos;\n        _ = dt; // frame-locked", "void {\n        if (@intFromPtr(self) != 0) return;\n        _ = zigos;\n        _ = dt; // frame-locked", "moving"],
    raster: ["zg.copper.install(fb, &.{BACK}, &copper_table, .{ .flicker = true });", "_ = &copper_table;", "rasters"],
    song: ['const MUSIC = "sos.sndh";', 'const MUSIC = "no_such_tune.sndh";', "song"],
};
const brk = process.argv[2] === "--break" ? process.argv[3] : null;
if (brk !== null && !BREAKS[brk]) throw new Error(`--break ${brk}: one of ${Object.keys(BREAKS).join(", ")}`);

function makeProject() {
    const dir = mkdtempSync(path.join(tmpdir(), "zm-sdk-"));
    cpSync(path.join(ROOT, "sdk/template"), dir, { recursive: true, filter: (s) => !/zig-out|\.zig-cache/.test(s) });
    const zon = path.join(dir, "build.zig.zon");
    const rel = path.relative(dir, ROOT);
    writeFileSync(zon, readFileSync(zon, "utf8").replace('.path = "../.."', `.path = "${rel}"`));
    if (brk) {
        const src = path.join(dir, "src/hello.zig");
        const [from, to] = BREAKS[brk];
        const text = readFileSync(src, "utf8");
        if (!text.includes(from)) throw new Error(`--break ${brk}: the template no longer has "${from}"`);
        writeFileSync(src, text.replace(from, to));
    }
    return dir;
}

function checks(dir) {
    const failed = new Set();
    const check = (name, ok, what) => {
        console.log(`${ok ? "ok  " : "FAIL"} ${name.padEnd(8)} ${what}`);
        if (!ok) failed.add(name);
    };
    execFileSync("make", ["-s", "floppy", "NAME=hello"], { cwd: dir, stdio: ["ignore", "ignore", "inherit"] });
    const wasm = path.join(dir, "zig-out/demo-hello.wasm"), zmd = path.join(dir, "zig-out/demo-hello.zmd");
    return { wasm, zmd, check, failed };
}

async function run(dir) {
    const { wasm, zmd, check, failed } = checks(dir);
    const disk = readFileSync(zmd);
    check("floppy", disk.length > 1536 && disk.includes(Buffer.from("ZX0!")), `${path.basename(zmd)}: ${disk.length} B, the cart ZX0-packed inside`);
    // A Zig cart also links the console bridge the browser loader gives it (sealed-loader.js).
    const m = await boot(wasm, null, 0, { jsConsoleLogWrite: () => {}, jsConsoleLogFlush: () => {} });
    const frames = [];
    for (let f = 1; f <= 120; f++) {
        step(m);
        if (f % 30 === 0) frames.push(picture(m));
    }
    check("plane", m.demo.isPlaneEnabled(0) === 1, "plane 0 enabled");
    const hashes = new Set(frames.map((p) => sha(p.px)));
    check("moving", hashes.size === frames.length, `${hashes.size} different pictures in ${frames.length} samples`);
    check("rasters", rasterColours(frames.at(-1)) >= 8, `${rasterColours(frames.at(-1))} colours down the background column`);
    const song = m.demo.pollSongRequest() ? new TextDecoder().decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())) : "";
    check("song", song !== "" && existsSync(path.join(ROOT, "docs/music", song)), `requests "${song}", ${song && existsSync(path.join(ROOT, "docs/music", song)) ? "in" : "NOT in"} docs/music/`);
    return failed;
}

// The window's left column (x = 0 of the 320x200 plane, centred in the physical frame): entry 0 as the
// copper set it for each line, but where a scroller glyph covers it (the ink: one more colour at most).
function rasterColours(pic) {
    const x0 = (pic.W - 320) >> 1, y0 = (pic.H - 200) >> 1;
    const seen = new Set();
    for (let y = 0; y < 200; y++) {
        const i = ((y0 + y) * pic.W + x0) * 4;
        seen.add(pic.px[i] | (pic.px[i + 1] << 8) | (pic.px[i + 2] << 16));
    }
    return seen.size;
}

const dir = makeProject();
let failed;
try {
    execFileSync(process.env.ZIG || "zig", ["build"], { cwd: dir, stdio: ["ignore", "inherit", "inherit"] });
    failed = await run(dir);
} finally {
    rmSync(dir, { recursive: true, force: true });
}
if (brk) {
    const caught = failed.has(BREAKS[brk][2]);
    console.log(caught ? `\nsdk --break ${brk}: caught ✅` : `\nsdk --break ${brk}: NOT caught ❌`);
    process.exitCode = caught ? 0 : 1;
} else {
    console.log(failed.size ? `\nsdk: FAILED ❌ (${[...failed].join(", ")})` : "\nsdk: the template cart builds outside the repo and runs ✅");
    process.exitCode = failed.size ? 1 : 0;
}
