// Headless ANIMA (cart 107): one continuous run through every part (apps/anima_lib.mjs boots it
// as the browser does) and checks what each part is about:
//   music     cuddly_reset.sndh at boot, silence ("none") at the gag's freeze, breath_2000.sndh
//             at the tunnel: the request sequence, nothing else
//   DARK      every line closed: the border columns show the machine background
//   OPEN      the sides opening from line 140 out, the bands still closed
//   OLDSCHOOL every line open; a REAL raster: each index-0 border pixel is its line's entry 0
//   GAG       mistimed flicker: the borders show noise, not the raster
//   NEWSCHOOL every line open, the picture covering the borders
//   pins      the composed 800x280 picture hashed at a frame of every part
//   CHISEL    ops a frame under MAX_BLITS (each costs ~800 cycles on the board)
//   cost      est. board Mc/frame (apps/frame_cost.mjs) of every part under CEILING_MC
//   node apps/anima_headless.mjs [outdir] [--pin] [--no-cost] [--break hash|border|raster|music|cost|noise]
// --pin prints the hashes for PINS. --break plants one fault and PASSES only if it is caught.
import { mkdir } from "node:fs/promises";
import { costOf, parseArgs } from "./frame_cost.mjs";
import { CART, boot, step, shot, borderMisses, background } from "./anima_lib.mjs";

const CEILING_MC = 1.75; // the board's knee: above it the frame drops below 60 fps (lead, 2026-10-23)
const MAX_BLITS = 260;
const BREAKS = ["hash", "border", "raster", "music", "cost", "noise"];
const argv = process.argv.slice(2);
const bi = argv.indexOf("--break");
const broke = bi >= 0 ? argv[bi + 1] : null;
if (bi >= 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const PIN = argv.includes("--pin");
const NO_COST = argv.includes("--no-cost");
const out = argv.find((a, i) => !a.startsWith("--") && argv[i - 1] !== "--break") ?? "/tmp/anima";

// part -> [tick to measure the cost at, frame to pin]
const PARTS = {
    dark: [20, 60], open: [150, 170], breathe: [260, 330], cube: [700, 700], octa: [1300, 1300],
    slip: [1760, 1790], freeze: [1860, 1860], terminal: [1950, 2000], tunnel: [2500, 2500],
    roto: [3500, 3300], knot: [4400, 4400], ico: [5300, 5300], star: [5800, 5800], burn: [6400, 6400],
};
const PINS = {
    60: "2ffcc7dae0b41e2cfd6d545cfaadb1ac73019dbbece3491845294ce2bfc7896c",
    170: "9d50fdc7a502806abdc5711004b6090b849874696be74f2c23c734c06ae1266b",
    330: "ee448db17f829187c73577f669147127cd3894c038a0cd32a2eb4e776efa19c3",
    700: "1c2f26edf1e254cfff6d61bc5c457297cbb6fc013dead7faba682e5dd0544be5",
    1300: "d91f8cb26310f9fdf34190175a5369cec811e6f73360c7e374df284979106650",
    1790: "6444b23bc770d6eacdb6ca9c001c0207a4a4df62dec7aff17fa6f00756dcd076",
    1860: "7c74d3fb43ac7bce9b73aeca31f514bb12cc0bf63eb4535d333f65c6962a13ea",
    2000: "4b8f2f7d12f38707a27f791b0afb74572328fc69e9ba77c2b4903dac3aadd177",
    2500: "d38c6b2cbd581443f60ebad9b452cd0fd3371f2856efb269122711d05dc237b3",
    3300: "a779d0d38ae2adfbc6fc5f6ab0db5157a7615c0b67914786887907bf819d4cd9",
    4400: "e351b6b3fc5582f6feb8f83e059b50038ea9ccfdbb64a96bb4f395b0e2defbbc",
    5300: "68bf6129d397a8b89bc5f68525f5e603f06c46b35861059daf6508c9b1d283c8",
    5800: "4ff03d84a12f39640f6977fb4c4eb2fbee27daa09a1ff17e1f206df6e959e315",
    6400: "cbf830ab04a2497c713310d395cb3f777941940900cf67f1669ef2cc6b4a8606",
};
const SONGS = ["cuddly_reset.sndh", "none", "breath_2000.sndh"];

const errors = [];
let injected = false;
const ok = (cond, msg) => { if (!cond) errors.push(msg); };
const catchIf = (when, cond, msg) => { ok(cond, msg); if (broke === when && !cond) injected = true; };
await mkdir(out, { recursive: true });
const m = await boot();
const { demo } = m;
const raster = (r) => ((demo.animaRasterAt(r) ^ (broke === "raster" && r === 150 ? 0xffffff : 0)) >>> 0);
const lines = () => Array.from({ length: 280 }, (_, r) => demo.animaLineOpen(r) === 1);

const checks = {
    30() { // DARK
        const open = lines().filter(Boolean).length + (broke === "border" ? 1 : 0);
        const b = borderMisses(m, () => background(m));
        catchIf("border", open === 0 && b.miss === 0, `dark: ${open} lines open, ${b.miss} border pixels not the background`);
    },
    120() { // OPEN: timeline.zig, sides from line 140 out over 60 ticks from tick 90
        const t = demo.animaTick();
        const sides = Math.floor(Math.floor((t - 90) * 256 / 60) * 100 / 256);
        const bad = lines().filter((o, r) => o !== (r >= 40 && r < 240 && Math.abs(r - 140) <= sides)).length;
        ok(t > 90 && t < 150 && bad === 0, `open: tick ${t}, ${bad} lines open or closed out of turn`);
    },
    600() { // OLDSCHOOL: the real raster in both side borders
        const b = borderMisses(m, raster);
        const colours = new Set(Array.from({ length: 280 }, (_, r) => raster(r))).size;
        ok(lines().every(Boolean), "oldschool: a line is closed");
        catchIf("raster", b.miss === 0, `oldschool: ${b.miss} border pixels are not their line's raster colour`);
        ok(b.seen > 300 && colours >= 30, `oldschool: ${b.seen} raster samples, ${colours} colours`);
    },
    1860() { // GAG: the freeze, every flicker mistimed
        const b = borderMisses(m, raster);
        ok(demo.animaPhase() === 5 && b.miss > b.seen * 0.8, `gag: ${b.miss}/${b.seen} border pixels show noise`);
    },
    2500() { // NEWSCHOOL: every line open, the tunnel over the borders
        const b = borderMisses(m, () => background(m));
        ok(lines().every(Boolean) && b.seen === 0, `tunnel: borders not covered (${b.seen} index-0 samples)`);
    },
    3300() { // THE MELT: a palette per line (slot 8 = light level 8 takes a hue a line)
        const hues = new Set(Array.from({ length: 280 }, (_, r) => demo.animaLineColour(r, 8) >>> 0)).size;
        ok(demo.animaPhase() === 7 && hues >= 24, `roto: ${hues} different level-8 colours over 280 lines`);
    },
    4400() { // THE KNOT: the sunset sky is a real raster again, through both borders
        const b = borderMisses(m, raster);
        ok(lines().every(Boolean) && b.miss === 0 && b.seen > 200, `knot: ${b.miss}/${b.seen} border pixels off the raster`);
    },
};
if (broke === "noise") checks[1860] = () => catchIf("noise", borderMisses(m, raster).miss === 0, "noise: the freeze shows noise");

const pins = Object.fromEntries(Object.values(PARTS).map(([, f]) => [f, null]));
const hashes = {};
const last = Math.max(...Object.keys(pins).map(Number));
while (m.frame < last) {
    step(m);
    checks[m.frame]?.();
    if (m.frame in pins) hashes[m.frame] = await shot(m, `${out}/anima-${String(m.frame).padStart(4, "0")}.ppm`, broke === "hash" && m.frame === 330);
}
ok(m.maxBlits <= MAX_BLITS, `CHISEL: ${m.maxBlits} ops in one frame (ceiling ${MAX_BLITS})`);
console.log(`  CHISEL ops: at most ${m.maxBlits} a frame`);
const songs = m.songs.map((s) => s.name);
if (broke === "music") songs[1] = "breath_2000.sndh";
catchIf("music", JSON.stringify(songs) === JSON.stringify(SONGS), `music: ${JSON.stringify(m.songs)}`);
if (PIN) console.log(JSON.stringify(hashes, null, 4));
for (const f of Object.keys(pins)) {
    if (PINS[f] === undefined) { ok(PIN, `frame ${f}: no pinned hash`); continue; }
    catchIf("hash", hashes[f] === PINS[f], `frame ${f}: picture hash ${hashes[f].slice(0, 16)} != pinned ${PINS[f].slice(0, 16)}`);
}

if (!NO_COST) {
    const ceiling = broke === "cost" ? 0.5 : CEILING_MC;
    for (const [name, [t]] of Object.entries(PARTS)) {
        const r = await costOf(CART, parseArgs([CART, "--frames", "30", "--warmup", "5", "--call", `1:animaJump:${t}`]));
        console.log(`  cost ${name.padEnd(9)} tick ${String(t).padStart(4)}: est. ${r.mc.avg} Mc/frame avg, ${r.mc.max} max (cart ${r.split.cart}, CHISEL ${r.split.blit}, FRESCO ${r.split.fresco})`);
        catchIf("cost", r.mc.max <= ceiling, `cost ${name}: ${r.mc.max} Mc > ${ceiling}`);
    }
}

if (broke) {
    console.log(injected ? `anima: PASS (--break ${broke} caught: ${errors[0]})` : `anima: FAILED -- --break ${broke} was not caught`);
    process.exit(injected ? 0 : 1);
}
for (const e of errors) console.log(`  FAIL ${e}`);
console.log(errors.length ? `anima: FAILED (${errors.length})` : "anima: PASS (music sequence, borders closed/opening/open, real raster, gag noise, newschool covering the borders, pinned frames of every part, CHISEL ops, est. cost of every part)");
process.exit(errors.length ? 1 : 0);
