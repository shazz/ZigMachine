// Headless OBJ DEMO driver (apps/zig/scenes/obj_demo.zig): boots the cart as
// docs/ loads it (apps/obj_machine.mjs) and checks the keys and the pictures.
//
//   node apps/obj_headless.mjs [<shot dir>] [--break res|shade|erase|pin]
// (with a shot dir: a PNG of each sphere pin and of the icosahedron in FLAT)
//
// Checked:
//   1. the OLD PICTURES: the icosahedron and the gem in FLAT, GLENZ, WIRE and SOFT
//      give the object rows (24..175) pinned below every 30 frames to frame 240
//      (PINS_OLD: see its note on where they come from);
//   2. the KEYS: 3 picks the sphere at 20 verts / 36 faces, + walks every level
//      up to 1986 / 3968 and stops there, - walks back and stops at the first;
//      + / - do nothing on the icosahedron or GLENZ NEST; 4 picks the nest at
//      60 / 104; 1 and 2 pick the models back;
//   3. S cycles nine distinct modes and the tenth press is the first again;
//      their inks: GLENZ ORs bits past the 12-step ramp, GOURAUD uses more
//      than 12 levels, WIRE and HIDDEN only the wire ink, HIDDEN fewer pixels
//      than WIRE, DOTS one pixel a vertex at most, in several depth inks;
//   4. the ERASE: only last frame's box is cleared, and every frame is the
//      same as one drawn on cleared rows (no stale pixel left), in every mode
//      on the sphere, and on GLENZ NEST in GLENZ, FLAT and DOTS;
//   5. pins of five sphere states (PINS_SPHERE) and three GLENZ NEST ones
//      (PINS_NEST), each the same under all six CPU/CHISEL splits (key C),
//      the HUD lines change with the resolution, and Escape leaves.
// --break res: + and - are not sent. --break shade: S is not sent. --break
// erase: a stray pixel is left in the object rows. --break pin: one pixel of
// the pinned rows flips. Each must be caught (then the run PASSes, exit 0).
import { bootObj, key, OBJ_Y0, OBJ_Y1, W } from "./obj_machine.mjs";
import { PINS_OLD, PINS_SPHERE, PINS_NEST } from "./obj_pins.mjs";
import { mkdir } from "node:fs/promises";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["res", "shade", "erase", "pin"].includes(BREAK)) { console.error(`obj: unknown --break ${BREAK}`); process.exit(1); }
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const errors = [];
const fail = (m) => errors.push(m);
const K_ESC = 0xE012;
// sphere.zig LEVELS: V = 2 + lon (lat - 1), F = 2 lon (lat - 1)
const LEVELS = [[6, 4], [8, 5], [10, 6], [12, 8], [16, 10], [20, 12], [24, 14], [28, 16], [32, 18], [40, 20], [48, 24], [56, 28], [64, 32]]
    .map(([lon, lat]) => [2 + lon * (lat - 1), 2 * lon * (lat - 1)]);

let log = [];
const boot = () => bootObj("docs/demo-obj.wasm", (s) => log.push(s));
const press = (S, ch) => {
    if (BREAK === "res" && (ch === "+" || ch === "-")) return;
    if (BREAK === "shade" && ch === "s") return;
    key(S, ch);
};
// The V/F the cart reports (its Console.log line on every model change).
const lastVF = () => {
    for (let i = log.length - 1; i >= 0; i--) {
        const m = /-> (\d+) verts, (\d+) faces/.exec(log[i]);
        if (m) return [Number(m[1]), Number(m[2])];
    }
    return null;
};
const pinHash = (S) => {
    if (BREAK === "pin") { const r = S.rows(OBJ_Y0, OBJ_Y1); r[(100 - OBJ_Y0) * W + 160] ^= 0x40; return S.hashOf(r); }
    return S.hash();
};

// --- 1: the old pictures -----------------------------------------------------
for (const [name, pins] of Object.entries(PINS_OLD)) {
    const S = await boot();
    const [, m, s] = /m(\d)s(\d)/.exec(name);
    press(S, String(Number(m) + 1));
    for (let i = 0; i < Number(s); i++) press(S, "s");
    const got = [];
    for (let f = 1; f <= 240; f++) { S.frame(); if (f % 30 === 0) got.push(pinHash(S)); }
    if (OUT && name === "m0s0") await S.shot(`${OUT}/obj_icosahedron_flat.png`);
    const bad = got.findIndex((h, i) => h !== pins[i]);
    if (bad >= 0) fail(`${name}: frame ${(bad + 1) * 30} rows ${OBJ_Y0}..${OBJ_Y1 - 1} hash ${got[bad]}, pinned ${pins[bad]}`);
}

// --- 2: the keys ---------------------------------------------------------------
{
    const S = await boot();
    S.frame();
    press(S, "+");
    if (JSON.stringify(lastVF()) !== "[12,20]") fail(`+ on the icosahedron changed V/F to ${lastVF()}`);
    press(S, "3");
    const seen = [lastVF()];
    for (let i = 0; i < LEVELS.length; i++) { press(S, "+"); S.frame(); seen.push(lastVF()); }
    const want = [...LEVELS, LEVELS[LEVELS.length - 1]];
    if (JSON.stringify(seen) !== JSON.stringify(want)) fail(`+ from the sphere's first level: V/F ${JSON.stringify(seen)}, want ${JSON.stringify(want)}`);
    const down = [];
    for (let i = 0; i < LEVELS.length; i++) { press(S, "-"); down.push(lastVF()); }
    const wantDown = [...LEVELS.slice(0, -1).reverse(), LEVELS[0]];
    if (JSON.stringify(down) !== JSON.stringify(wantDown)) fail(`- back down: V/F ${JSON.stringify(down)}, want ${JSON.stringify(wantDown)}`);
    press(S, "4");
    if (JSON.stringify(lastVF()) !== "[60,104]") fail(`4 does not pick GLENZ NEST: V/F ${lastVF()}`);
    log = [];
    press(S, "+");
    press(S, "-");
    if (lastVF() !== null) fail(`+ / - on GLENZ NEST rebuilt a model: V/F ${lastVF()}`);
    press(S, "2");
    if (JSON.stringify(lastVF()) !== "[8,12]") fail(`2 does not pick the gem: ${lastVF()}`);
    press(S, "1");
    if (JSON.stringify(lastVF()) !== "[12,20]") fail(`1 does not pick the icosahedron: ${lastVF()}`);
}

await import("./obj_modes.mjs").then((m) => m.checkModes({ boot, press, fail, BREAK, LEVELS, PINS_SPHERE, PINS_NEST, pinHash, K_ESC, OUT }));

if (BREAK) { // a break must be caught, and by the check it aims at
    const WANT = { res: "V/F", shade: "m0s1", erase: "stale", pin: "pinned" }[BREAK];
    const hit = errors.find((e) => e.includes(WANT));
    console.log(hit ? `obj: PASS (--break ${BREAK} caught: ${hit.slice(0, 120)})` : `obj: FAIL, --break ${BREAK} was NOT caught`);
    process.exit(hit ? 0 : 1);
}
if (errors.length) {
    console.log("obj: FAIL");
    for (const e of errors) console.log(`  - ${e}`);
    process.exit(1);
}
console.log("obj: OK - the old pictures pinned, 1-5 pick the object (4: GLENZ NEST 60/104, 5: RNO CUBE), +/- walk the sphere's 13 levels (V/F from 20/36 to 1986/3968), S cycles 9 modes (ENVMAP last), only last frame's box erased, sphere + nest pins under every split, HUD, Escape");
