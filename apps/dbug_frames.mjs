// Headless D-BUG frame check (apps/zig/scenes/dbug.zig): EVERY frame of the first
// 100 seconds (6000 VBLs: the still intro, the scroller's fall at 12.8 s, the
// beat-driven bounces with the logo's spring, the settle after 89.6 s, and the
// credit panel writing, holding and erasing its texts throughout) is the
// reference picture, byte for byte: the COMPOSED screen (scene_hash --composite,
// the overscan borders and the per-line raster included), with the tune's clock
// driven at 1000/60 ms a frame (--song-clock: the bounce follows song_ms).
// The reference is apps/dbug_expected.json, taken from the cart as it was before
// the credit panel moved from plane 1 onto the overscan plane 0 (cecc6dd0,
// 2026-10-23: two enabled planes), so the one-plane cart is proven to show the
// same frames.
//
//   node apps/dbug_frames.mjs [--break skip] [--cart X.wasm --disk X.zmd] [--write]
//     --break skip   one extra VBL at frame 3000: the later parts must fail
//     --write        (re)write apps/dbug_expected.json from --cart (never in the gate)
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const EXPECTED = "apps/dbug_expected.json";
const FRAMES = 6000;
// dbug_sync.zig at 1000/60 ms a frame: the fall at 12800 ms, beats until 89600 ms.
const PARTS = [
    ["intro", 1, 768], ["fall and first beats", 769, 1500], ["beats", 1501, 2999],
    ["beats (later)", 3000, 5376], ["settle and rest", 5377, FRAMES],
];

const argv = process.argv.slice(2);
const opt = (name, dflt) => { const i = argv.indexOf(name); return i < 0 ? dflt : argv[i + 1]; };
const brk = opt("--break", null);
if (brk && brk !== "skip") throw new Error(`--break takes skip, not ${brk}`);
const cart = opt("--cart", "docs/demo-dbug.wasm");
const disk = opt("--disk", "docs/demo-dbug.zmd");

const args = ["apps/scene_hash.mjs", cart, String(FRAMES), "1", "--disk", disk, "--composite", "--song-clock"];
if (brk === "skip") args.push("--call", "3000:frame:16.6");
const run = JSON.parse(execFileSync(process.execPath, args, { maxBuffer: 64 << 20 }).toString());
const byFrame = new Map(run.samples.map((s) => [s.frame, s.hash]));

const got = PARTS.map(([name, from, to]) => {
    const h = createHash("sha256");
    for (let f = from; f <= to; f++) {
        if (!byFrame.has(f)) throw new Error(`dbug: no hash for frame ${f}`);
        h.update(byFrame.get(f));
    }
    return { name, from, to, sha: h.digest("hex") };
});

if (argv.includes("--write")) {
    writeFileSync(EXPECTED, JSON.stringify({ frames: FRAMES, parts: got }, null, 1) + "\n");
    console.log(`dbug: wrote ${EXPECTED} from ${cart}`);
    process.exit(0);
}

const want = JSON.parse(readFileSync(EXPECTED, "utf8")).parts;
const bad = got.filter((p, i) => p.sha !== want[i].sha || p.from !== want[i].from || p.to !== want[i].to);
for (const p of got) console.log(`  ${bad.includes(p) ? "FAIL" : "ok  "} ${p.name} (frames ${p.from}..${p.to})`);
if (brk) {
    // the extra VBL lands at frame 3000: every part from there on shifts
    const caught = bad.length > 0 && got.slice(0, 3).every((p) => !bad.includes(p));
    console.log(caught ? `dbug: PASS (--break ${brk} caught in ${bad.length} parts, the first three untouched)`
        : `dbug: FAIL, --break ${brk} was NOT caught as expected`);
    process.exit(caught ? 0 : 1);
}
console.log(bad.length ? `dbug: FAIL, ${bad.length} of ${got.length} parts differ` : `dbug: PASS, all ${FRAMES} frames are the reference`);
process.exit(bad.length ? 1 : 0);
