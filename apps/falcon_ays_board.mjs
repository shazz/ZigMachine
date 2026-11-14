// falcon_ays: the four bugs of Matt's board run of 13 Nov 2026, pinned (prototypes/falcon_ays_re/
// ANALYSIS.md §8). Boots the committed cart (apps/falcon_ays_boot.mjs) and checks the raster:
//   smear   825's feedback blur on the RG ship: one pass every 6 ticks, 11 in all (the Hatari
//           capture), so the picture still changes after the jolt (41.0-41.8 s), then holds
//   flash   821's inverted blobs and 822's push to white: the border shows the picture's
//           background (a white screen in a black border read as a flash out of sync)
//   shake   833's sideways jolt on the credits: no CODE plaque pixel wraps into the left columns
//           (the line list's early start showed the row above's tail: a rot, not an asl), and
//           the mask plane is off once the jolt is over
//   band    829, the grey ball-oid: the left of the screen is 824's white band, black above it
//   node apps/falcon_ays_board.mjs [--break smear|flash|shake|band]
//   (--break moves each check onto a time or place where it must fail)
import { readFile } from "node:fs/promises";
import { boot, raster, at, W, H } from "./falcon_ays_boot.mjs";

const ART = "apps/zig/assets/screens/falcon_ays";
const BRK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const errors = [];
const want = (ok, msg) => { if (!ok) errors.push(msg); };
const same = (a, b) => a.every((v, i) => v === b[i]);
const to565 = (v) => (((v & 255) >> 3) << 11) | ((((v >> 8) & 255) >> 2) << 5) | ((v >> 16) >> 3);
const be565 = (buf, i) => (buf[i * 2] << 8) | buf[i * 2 + 1];
function commonest(img) {
    const n = new Map();
    for (const v of img) n.set(v, (n.get(v) ?? 0) + 1);
    return [...n.entries()].sort((a, b) => b[1] - a[1])[0][0];
}
const m = await boot();

// flash: the border = the picture's background on 822's white (35.4 s) and 821's (64.8 s)
// (the machine runs forwards only: the checks go in song order)
function flashAt(t) {
    const r = raster(m, t);
    const bg = commonest(at(m, t));
    want(bg === 0xFFFFFF && r[0] === bg, `flash: at ${t} s the border is ${r[0].toString(16)}, the picture's background ${bg.toString(16)}`);
}
flashAt(BRK === "flash" ? 33.0 : 35.4);

// smear (825 at 40.32 s; its jolt is over at 40.94 s, 826's starts at 42.56 s)
const [s0, s1] = BRK === "smear" ? [41.7, 42.4] : [40.95, 41.8];
let changes = 0, prev = at(m, s0);
for (let t = s0 + 1 / 60; t <= s1; t += 1 / 60) {
    const img = at(m, t);
    changes += !same(prev, img);
    prev = img;
}
want(changes >= 4 && changes <= 6, `smear: ${changes} passes from ${s0} to ${s1} s, not 5 (one every 6 ticks)`);
want(same(at(m, 41.75), at(m, 42.4)), "smear: the ship still changes after the 11th pass");

flashAt(64.8);

// shake: 833 jolts the credits from 72.52 s for 31 ticks
const plaque = await readFile(`${ART}/plaque_code.bin`);
const pw = (plaque[2] << 8) | plaque[3], ph = (plaque[4] << 8) | plaque[5];
const ink = new Set(Array.from({ length: pw * ph }, (_, k) => be565(plaque, 3 + k)).filter((c) => c !== 0));
const cols = BRK === "shake" ? [W - 10, W] : [0, 10];
// A wrap is the plaque's edge down the whole plaque height; a landing particle (the picture shares
// its colours) is a 4x4 block: a frame counts as wrapped when half the plaque's rows show ink.
let wrapped = 0;
for (let t = 72.55; t < 73.2; t += 1 / 60) {
    const img = at(m, t);
    let rowsInked = 0;
    for (let y = H - ph; y < H; y++) {
        let inked = false;
        for (let x = cols[0]; x < cols[1]; x++) inked ||= ink.has(to565(img[y * W + x]));
        rowsInked += inked;
    }
    wrapped += rowsInked >= ph / 2;
}
want(wrapped === 0, `shake: ${wrapped} frames with the CODE plaque in columns ${cols[0]}..${cols[1] - 1} during the jolt`);
at(m, 73.5);
want(!m.demo.isPlaneEnabled(2), "shake: the mask plane is still on after the jolt");

// band: 829 at 161.28 s, the ball in x 160..319
const img = at(m, 162.5);
const rows = BRK === "band" ? [0, 20] : [30, 170];
let white = 0, n = 0;
for (let y = rows[0]; y < rows[1]; y++) for (let x = 0; x < 150; x++, n++) white += img[y * W + x] === 0xFFFFFF;
want(white === n, `band: at 162.5 s ${n - white} of ${n} pixels left of the ball not white (rows ${rows[0]}..${rows[1] - 1})`);
let lit = 0;
for (let i = 0; i < 20 * W; i++) lit += img[i] !== 0;
want(lit === 0, `band: at 162.5 s ${lit} lit pixels above the band`);

if (BRK) {
    const hit = errors.find((e) => e.startsWith(`${BRK}:`));
    console.log(hit ? `falcon_ays_board: PASS (--break ${BRK} caught: ${hit})` : `falcon_ays_board: FAILED -- --break ${BRK} not caught`);
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `falcon_ays_board: FAILED -- ${errors.join("; ")}` : `falcon_ays_board: all pass (smear ${changes} passes, border on the white, no wrap, the band)`);
    process.exitCode = errors.length ? 1 : 0;
}
