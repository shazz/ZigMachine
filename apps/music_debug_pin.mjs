// MUSIC DEBUG pixel pin: the composited picture (borders, rasters and HBL
// included) hashed every 60 frames over 1200 frames, with no tune (scope off)
// and with a YM tune's registers mirrored in (the square-wave + noise scope on),
// must equal apps/music_debug_pin.json.
//
// WHY a recorded pin and not a model: the screen is ZigMachine's own test screen,
// with no original to compare against. Its picture changed ON PURPOSE on
// 2026-10-24 (Matt: fixed-point sines, stars and scope, two logo trails instead
// of three, to reach 60 fps on the board), and this pin holds that picture from
// then on. A deliberate change re-blesses it:  node apps/music_debug_pin.mjs --bless
//
//   node apps/music_debug_pin.mjs [--bless] [--cart other.wasm]
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const ci = process.argv.indexOf("--cart"); // another build of the cart, to see the pin fail
const CART = ci > 0 ? process.argv[ci + 1] : "docs/demo-music.wasm";
const PIN = "apps/music_debug_pin.json";
// A YM tune's registers: three tones (periods 284, 142, 672), noise on voice C,
// volumes 15 / 12 / envelope (the loader mirrors these from the playing song).
const YM = "28,1,142,0,160,2,16,24,15,12,16,0,0,0,0,0";
const RUNS = {
    silent: [],
    ym: ["--call", "1:set8@getAudioModePointer:2", "--call", `1:set8@getYmRegsPointer:${YM}`],
};

function hashes(extra) {
    const out = execFileSync("node", ["apps/scene_hash.mjs", CART, "1200", "60", "--composite", ...extra], { maxBuffer: 1 << 26 });
    return JSON.parse(out).samples.map((s) => s.hash.slice(0, 16));
}

const got = Object.fromEntries(Object.entries(RUNS).map(([k, extra]) => [k, hashes(extra)]));
if (process.argv.includes("--bless")) {
    writeFileSync(PIN, JSON.stringify(got, null, 1) + "\n");
    console.log(`music_debug_pin: blessed ${PIN}`);
    process.exit(0);
}
const want = JSON.parse(readFileSync(PIN, "utf8"));
let bad = 0;
for (const k of Object.keys(RUNS)) {
    const i = got[k].findIndex((h, j) => h !== want[k][j]);
    const moving = new Set(got[k]).size > got[k].length / 2;
    if (i >= 0) { bad++; console.log(`  FAIL ${k}: frame ${(i + 1) * 60} differs from the pin`); }
    else console.log(`  ok   ${k}: ${got[k].length} pinned frames identical`);
    if (!moving) { bad++; console.log(`  FAIL ${k}: the picture does not move`); }
}
const ymDiffers = got.ym.some((h, j) => h !== got.silent[j]);
if (!ymDiffers) { bad++; console.log("  FAIL the YM scope changes nothing on screen"); }
console.log(bad ? "music_debug_pin: FAIL" : "music_debug_pin: all pass");
process.exit(bad ? 1 : 0);
