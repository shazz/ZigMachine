// Headless RACER car + shadow (apps/zig/scenes/racer/carview.zig, shadow.zig; R82 Kestrel Racing M5 step 3). Boots the cart as
// the page loads it, starts lap v2 (key x: the start grid, all 8 GT cars in view), pauses, and checks:
//   1. the 8 liveries: each AI body ramp (15-18) and the player's (12) in view, and the stripes (13, 16, 18 among them);
//   2. the REAL shadow is the default: key y toggles the checkerboard and back (the frame comes back byte for byte). Between
//      the two frames, every pixel that differs is under a shadow: where (x + y) is even the checkerboard's DITHER (index 0);
//      where it is odd the dithered frame shows the untouched pixel p and the real frame shows ONE level down of it
//      (shadow.darken: p - 1 inside a ramp, p at a ramp's bottom). At least 8 x 40 shadow pixels a frame (eight cars);
//   3. the same real frame on the AFFINE fill (the shadow syncs CHISEL then reads the plane) = the CPU fill's;
//   4. the --break switches: `two` (key S: two levels down) and `dither` (key Q: the checkerboard by default). Both must fail.
//   node apps/harness/racer_car.mjs [<shot dir>] [--break two|dither]
import { mkdir } from "node:fs/promises";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["two", "dither"].includes(BREAK)) { console.error(`racer_car: unknown --break ${BREAK}`); process.exit(1); }
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100, DITHER = 0;
const MIN_UNDER = 60; // the grid at R 5, far POV: the 8 cars are 3-16 px wide (freds72's scale), their shadows a fringe left and behind
const darken = (p) => (p >= 16 && (p - 16) % 8 !== 0 ? p - 1 : p);
const errors = [];
const fail = (m) => errors.push(m);

async function boot() {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook());
    key(S, "5");
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown(), true), W * H).slice();
    };
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    return { S, log, view, run };
}

/** The grid, paused at frame 40 of lap v2 (both pages drawn from the same state). */
async function grid({ affine = false, pov = 0 } = {}) {
    const B = await boot();
    if (affine) key(B.S, "f");
    if (BREAK === "two") key(B.S, "S");
    if (BREAK === "dither") key(B.S, "Q");
    key(B.S, "x");
    for (let k = 0; k < pov; k++) key(B.S, "v");
    B.run(40);
    key(B.S, "p");
    B.run(2);
    return B;
}

const ramp = (p) => (p - 16) >> 3;
function liveries(px) {
    const seen = new Set();
    for (let i = Y0 * W; i < Y1 * W; i++) if (px[i] >= 16) seen.add(ramp(px[i]));
    for (const r of [12, 13, 15, 16, 17, 18]) if (!seen.has(r)) fail(`grid: no pixel of ramp ${r} (a body or a stripe) in view`);
}

function shadowChecks(real, dith) {
    let under = 0, darker = 0;
    for (let y = Y0; y < Y1; y++) for (let x = 0; x < W; x++) {
        const i = y * W + x, a = real[i], b = dith[i];
        if (a === b) continue;
        under++;
        if ((x + y) % 2 === 0) {
            if (b !== DITHER) return fail(`shadow: (${x},${y}) even cell is ${b} in the checkerboard frame, not DITHER ${DITHER}`);
        } else if (a !== darken(b)) {
            return fail(`shadow: (${x},${y}) is ${a} in the default frame, ${b} under the checkerboard: not one level down (want ${darken(b)})`);
        } else darker++;
    }
    if (under < MIN_UNDER || darker < MIN_UNDER / 3) fail(`shadow: only ${under} pixels under the shadows (${darker} darkened), want >= ${MIN_UNDER}`);
    return under;
}

async function shot(path, B, px) {
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(path, Uint32Array.from(px, (v) => (v ? pal[v] : 0xff000000)), W, H);
}

const B = await grid();
const real = B.view();
liveries(real);
key(B.S, "y");
B.run(2);
const dith = B.view();
if (!B.log.some((l) => l === "racer,shadow,DITHER")) fail("key y did not log racer,shadow,DITHER");
const under = shadowChecks(real, dith);
key(B.S, "y");
B.run(2);
if (Buffer.compare(Buffer.from(B.view()), Buffer.from(real)) !== 0) fail("key y twice: the default shadow frame does not come back");
if (BREAK === null) {
    const A = await grid({ affine: true });
    if (Buffer.compare(Buffer.from(A.view()), Buffer.from(real)) !== 0) fail("the AFFINE fill's grid (real shadow) differs from the CPU fill's");
}
if (OUT) {
    await shot(`${OUT}/car_grid_real.png`, B, real);
    await shot(`${OUT}/car_grid_dither.png`, B, dith);
    const N = await grid({ pov: 1 }); // the near POV: the player's car close
    await shot(`${OUT}/car_near_real.png`, N, N.view());
    key(N.S, "y");
    N.run(2);
    await shot(`${OUT}/car_near_dither.png`, N, N.view());
}

if (BREAK) {
    if (!errors.some((e) => e.startsWith("shadow:"))) { console.error(`racer_car: --break ${BREAK} was NOT caught (${errors.length} errors)`); process.exit(1); }
    console.log(`racer_car PASS (--break ${BREAK} caught: ${errors[0]})`);
} else if (errors.length) {
    for (const e of errors) console.error(`racer_car FAIL: ${e}`);
    process.exit(1);
} else console.log(`racer_car PASS (8 liveries in view, ${under} shadow pixels at the grid: real = one ramp level down, key y = the checkerboard, CPU = AFFINE)`);
