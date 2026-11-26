// Headless RACER car files (R82 Kestrel Racing M5, apps/zig/scenes/racer/cars.zig + carfile.zig, docs/ports/kestrel_racing/M5.md
// "Car scale and car files"). A C: image built here (KOS GEMDOS, env.kosDriveRead as the page serves it) holds SYNTHETIC car
// files made by tools/racer/carc.py from our own GT (no other data):
//   1. no car file: the built-in GT ("racer,car,GT"), its ramp 12 the track's red;
//   2. \HD\RACER\CAR.KCR, a v2 set (the GT at its scale and at 3x, a palette): loaded for every track ("racer,car,CAR.KCR,2"),
//      the car ramps 12..18 take the file's colours, and the race grid draws the AI cars with the second model (more pixels
//      of the AI's ramps than with the built-in GT);
//   3. \HD\RACER\SALT.KCR corrupted (a body byte flipped: the CRC): refused by name on SALT ("racer,car,refused,SALT.KCR,BadCrc"),
//      no trap, CAR.KCR drawn instead; a truncated CAR.KCR alone is refused too and the built-in GT drawn.
//   node apps/harness/racer_carfile.mjs [--break crc]   (--break crc: the 'corrupted' file left whole: check 3 must catch it)
import { execFileSync } from "node:child_process";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { makeCDrive } from "./scene_hash_disk.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && BREAK !== "crc") { console.error(`racer_carfile: unknown --break ${BREAK}`); process.exit(1); }
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const errors = [];
const fail = (m) => errors.push(m);

// The C: image: CAR.KCR (a set) and SALT.KCR (the same set, a body byte flipped unless --break crc), or a truncated CAR.KCR.
const CIMG = (mode) => `
import sys; sys.path[:0] = ["tools", "fpga/tools"]
import sd_layout; from kos_fat_fixture import Image
from racer import carc, kcar_export
doc = kcar_export.loads(open("tools/racer/cars/gt.kcar.json").read())
pal = [(250, 250, 40), (20, 20, 20), (90, 200, 250), (40, 220, 90), (250, 120, 30), (200, 40, 220), (240, 240, 240)]
s = carc.pack_set([carc.convert(doc, scale=carc.GT_SCALE), carc.convert(doc, scale=3.0)], pal)
img = Image("SD CARD", 2048); hd = sd_layout.HD
img.mkdir(hd); img.mkdir(hd + "/RACER")
if "${mode}" == "short":
    img.write(hd + "/RACER/CAR.KCR", s[:len(s) - 40])
else:
    img.write(hd + "/RACER/CAR.KCR", s)
    bad = bytearray(s); bad[len(s) // 2] ^= ${BREAK === "crc" ? 0 : 0x5a}
    img.write(hd + "/RACER/SALT.KCR", bytes(bad))
sys.stdout.buffer.write(img.bytes())`;

async function run(cimg, keys) {
    const log = [];
    const hook = cimg ? (env) => { diskHook()(env); env.kosDriveRead = makeCDrive(env.memory, cimg); } : diskHook();
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), hook);
    key(S, "5");
    for (const k of keys) { key(S, k); for (let i = 0; i < 4; i++) S.frame(); }
    key(S, "x"); // lap v2: the grid, the 8 cars in view
    for (let i = 0; i < 40; i++) S.frame();
    key(S, "p");
    S.frame(); S.frame();
    const shown = [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
    const px = new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown, true), W * H).slice();
    const pal = new Uint32Array(S.memory.buffer, vb + OFF_PAL, 256).slice();
    return { log, px, pal, cars: log.filter((l) => l.startsWith("racer,car,") && !l.startsWith("racer,cars,")) };
}
const rampPixels = (px, lo, hi) => { let n = 0; for (let i = Y0 * W; i < Y1 * W; i++) if (px[i] >= 16 + lo * 8 && px[i] < 16 + (hi + 1) * 8) n++; return n; };
const cimg = (mode) => new Uint8Array(execFileSync("python3", ["-I", "-c", CIMG(mode)], { maxBuffer: 8 << 20 }));

const gt = await run(null, []);
if (gt.cars.at(-1) !== "racer,car,GT,1,0") fail(`no car file: want the built-in GT, got ${gt.cars.at(-1)}`);
const set = await run(cimg("set"), []);
if (!set.cars.at(-1)?.startsWith("racer,car,CAR.KCR,2,")) fail(`CAR.KCR: want the set loaded, got ${set.cars.at(-1)}`);
const top12 = set.pal[16 + 12 * 8 + 7] & 0xffffff, want12 = (((40 * 253) >> 8) << 16) | (((250 * 253) >> 8) << 8) | ((250 * 253) >> 8);
if (top12 === (gt.pal[16 + 12 * 8 + 7] & 0xffffff)) fail("CAR.KCR: ramp 12 kept the track's colour, not the file's");
const aiGt = rampPixels(gt.px, 15, 18), aiSet = rampPixels(set.px, 12, 18);
if (aiSet <= rampPixels(gt.px, 12, 18)) fail(`CAR.KCR: the AI cars at 3x draw ${aiSet} car-ramp pixels, no more than the GT's ${rampPixels(gt.px, 12, 18)}`);
const salt = await run(cimg("set"), ["t", "t"]);
const refused = salt.cars.find((l) => l.startsWith("racer,car,refused,SALT.KCR,"));
if (!refused || !salt.cars.at(-1)?.startsWith("racer,car,CAR.KCR,2,")) fail(`a corrupted SALT.KCR: ${refused ?? "not refused"}; then ${salt.cars.at(-1)}`);
const short = await run(cimg("short"), []);
if (!short.cars.some((l) => l.startsWith("racer,car,refused,CAR.KCR,")) || short.cars.at(-1) !== "racer,car,GT,1,0")
    fail(`a truncated CAR.KCR: ${short.cars.join(" | ")}`);
if (BREAK) {
    if (!errors.some((e) => e.startsWith("a corrupted SALT.KCR"))) { console.error(`racer_carfile: --break ${BREAK} was NOT caught`); process.exit(1); }
    console.log(`racer_carfile PASS (--break ${BREAK} caught: ${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const m of errors) console.error(`racer_carfile: ${m}`); process.exit(1); }
console.log(`racer_carfile: PASS (no file = the GT; CAR.KCR's set loaded, its ramps installed (ramp 12 top ${top12.toString(16)}, the file's ${want12.toString(16)}), AI pixels ${aiGt} -> ${aiSet}; ${refused}; a truncated CAR.KCR refused, the GT drawn)`);
