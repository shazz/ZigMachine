// Headless STCS STARGOOSE check (apps/zig/scenes/stcs.zig): EVERY frame of one
// whole choreography cycle (9420 VBLs, all seven scroller shapes: three lines,
// big font, interlaced mirror, interlaced big font, inverted, interlaced steam,
// inverted mirror, then the wrap back to three lines) is the reference picture,
// byte for byte, both planes rendered with their HBLs (the per-line rasters, the
// per-band font palettes, the border colour per physical line).
// The reference is apps/stcs_expected.json: per period, the SHA-256 of the
// frames' apps/scene_hash.mjs hashes, taken from the cart as it was BEFORE the
// scroller moved onto CHISEL (CPU strip + row copies, 2026-10-20), so the
// CHISEL path is proven to draw the same frames.
//
//   node apps/stcs_headless.mjs [--break skip] [--cart X.wasm --disk X.zmd] [--write]
//     --break skip   one extra VBL at frame 4000: the later periods must fail
//     --write        (re)write apps/stcs_expected.json from --cart (never in the gate)
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const EXPECTED = "apps/stcs_expected.json";
const FRAMES = 9500;
// The cart's own schedule (stcs.zig update): frame f runs with frame_counter = f.
const PERIODS = [
    ["threelines", 1, 599], ["big_font", 600, 779], ["threelines", 780, 1799],
    ["big_font", 1800, 2999], ["interlaced_mirror", 3000, 4799],
    ["interlaced_big_font", 4800, 6359], ["inverted", 6360, 6959],
    ["interlaced_steam", 6960, 8219], ["inverted_mirror", 8220, 9420],
    ["threelines (wrapped)", 9421, FRAMES],
];

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i < 0 ? dflt : argv[i + 1]; };
const brk = opt("--break", null);
if (brk && brk !== "skip") throw new Error(`--break takes skip, not ${brk}`);
const cart = opt("--cart", "docs/demo-stcs.wasm");
const disk = opt("--disk", "docs/demo-stcs.zmd");

const args = ["apps/scene_hash.mjs", cart, String(FRAMES), "1", "--disk", disk];
if (brk === "skip") args.push("--call", "4000:frame:16.6");
const run = JSON.parse(execFileSync(process.execPath, args, { maxBuffer: 64 << 20 }).toString());
const byFrame = new Map(run.samples.map((s) => [s.frame, s.hash]));

const got = PERIODS.map(([name, from, to]) => {
    const h = createHash("sha256");
    for (let f = from; f <= to; f++) {
        if (!byFrame.has(f)) throw new Error(`stcs: no hash for frame ${f}`);
        h.update(byFrame.get(f));
    }
    return { name, from, to, sha: h.digest("hex") };
});

if (argv.includes("--write")) {
    writeFileSync(EXPECTED, JSON.stringify({ frames: FRAMES, periods: got }, null, 1) + "\n");
    console.log(`stcs: wrote ${EXPECTED} from ${cart}`);
    process.exit(0);
}

const want = JSON.parse(readFileSync(EXPECTED, "utf8")).periods;
const bad = got.filter((p, i) => p.sha !== want[i].sha || p.from !== want[i].from || p.to !== want[i].to);
for (const p of got) console.log(`  ${bad.includes(p) ? "FAIL" : "ok  "} ${p.name} (frames ${p.from}..${p.to})`);
if (brk) {
    // the extra VBL lands in interlaced_mirror: every period from there on shifts
    const caught = bad.length > 0 && got.slice(0, 4).every((p) => !bad.includes(p));
    console.log(caught ? `stcs: PASS (--break ${brk} caught in ${bad.length} periods, the first four untouched)`
        : `stcs: FAIL, --break ${brk} was NOT caught as expected`);
    process.exit(caught ? 0 : 1);
}
console.log(bad.length ? `stcs: FAIL, ${bad.length} of ${got.length} periods differ` : `stcs: PASS, all ${FRAMES} frames are the reference`);
process.exit(bad.length ? 1 : 0);
