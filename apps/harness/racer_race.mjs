// Headless RACER race (apps/zig/scenes/racer.zig, R82 Kestrel Racing M3). Boots the cart as the page loads it and checks:
//   1. LAP v2 (key x): the start grid (all 8 cars in view, the AI cars in their four liveries, the player red) and a full race
//      lap, 2,880 frames. The cart's `racer,cars,<ticks>,<crc>` line every 60 frames equals the Lua reference's CRC of all eight
//      cars' state at that tick (apps/zig/assets/screens/racer/race_full.bin, written by tools/racer/race_fixture.py from z8lua);
//      the view CRC list is the same twice, on the CPU and AFFINE fills, and pinned; `racer,aius` is printed;
//   2. the 3-LAP RACE (key e, recorded driver a, warp w): the FSM walks grid, countdown, race, finish, results; the player wins;
//      every car finishes, at the reference's ticks; none leaves the asphalt or sticks to a wall for 2 s; the result hash is pinned;
//      the HUD bands (rows 0-11 and 188-199, minimap included) are hashed at each state and pinned;
//   3. the crest pose (key k): the car before the crest is drawn, the view pinned;
//   4. the --break switches: `pid` (key W, the AI's PID gain moved) changes the race against the reference; `pin` moves one pin. Both must fail.
//   node apps/harness/racer_race.mjs [<shot dir>] [--break pid|pin] [--print-pins]
import { mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["pid", "pin"].includes(BREAK)) { console.error(`racer_race: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const ROUND = 2880, LIVERY = [16 + 15 * 8, 16 + 19 * 8], BODY = [16 + 12 * 8, 16 + 13 * 8];
const PINS = {
    lap: "6b27a42414bd", // R82 bug pass: the footprint shadow, the cars keyed over the ground under their footprint (view only)
    result: "ef4ce056",
    hud: { grid: "4797fa32a488", countdown: "30976b49f7a9", race: "41c20dc562b7", finish: "2a2a37d0c99c", results: "bb3a878d5568" },
    crest: "ae1b67f32f4a", // R82 bug pass: the footprint shadow under the two cars at the crest
};
const errors = [];
const fail = (m) => errors.push(m);
const sha = (px) => createHash("sha256").update(px).digest("hex").slice(0, 12); // a short pin

async function boot(opts) {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook());
    if (!opts?.raw) key(S, "5"); // every pin was taken at R = 5; the cart's default is 8 (racer.zig PLAY_R)
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown(), true), W * H).slice();
    };
    const lines = (kind) => log.filter((l) => l.startsWith(`racer,${kind},`)).map((l) => l.split(",").slice(2));
    const run = (n, each) => { for (let i = 0; i < n; i++) { S.frame(); if (each) each(i); } };
    const until = (kind, state, max) => { for (let i = 0; i < max; i++) { S.frame(); if (lines(kind).some((l) => l[0] === state)) return true; } return false; };
    return { S, log, view, lines, run, until };
}
const count = (px, [lo, hi], rows = [Y0, Y1]) => { let n = 0; for (let i = rows[0] * W; i < rows[1] * W; i++) if (px[i] >= lo && px[i] < hi) n++; return n; };
const bands = (px) => sha(Buffer.concat([px.subarray(0, Y0 * W), px.subarray(Y1 * W, H * W)]));
const viewHash = (px) => sha(px.subarray(Y0 * W, Y1 * W));
/** The reference fixture's per-tick CRC list and each car's finish tick (tools/racer/race_fixture.py, "RCRC"). */
async function fixture() {
    const b = await readFile("apps/zig/assets/screens/racer/race_full.bin"), dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    const n = dv.getUint32(4, true), nt = dv.getUint32(8, true);
    const finish = Array.from({ length: n }, (_, i) => dv.getUint32(24 + 4 * i, true));
    const crcs = Array.from({ length: nt }, (_, i) => dv.getUint32(24 + 4 * n + 4 * i, true).toString(16).padStart(8, "0"));
    return { finish, crcs };
}

async function lap(opts = {}) {
    const B = await boot();
    if (opts.affine) key(B.S, "f");
    if (BREAK === "pid") key(B.S, "W");
    key(B.S, "x");
    const seen = { grid: null };
    B.run(ROUND, (i) => { if (i === 40) seen.grid = B.view(); });
    return { B, seen, crcs: B.lines("crc").map((l) => l[1]), cars: B.lines("cars") };
}

async function lapChecks(ref) {
    const base = await lap();
    if (BREAK === "pin") base.crcs[3] = "00000000";
    const list = base.crcs.join(" ");
    if (PRINT) console.log(`PIN_LAP = "${list}"`, `// hash ${sha(list)}`);
    else if (base.crcs.length !== 48 || sha(list) !== PINS.lap) fail(`lap v2 CRC list hash ${sha(list)} != the pin ${PINS.lap}`);
    let raced = 0;
    for (const [ticks, crc, state] of base.cars) {
        if (state !== "race" || Number(ticks) < 1) continue;
        raced++;
        if (ref.crcs[Number(ticks) - 1] !== crc) fail(`lap v2: tick ${ticks} state CRC ${crc} != the Lua reference's ${ref.crcs[Number(ticks) - 1]}`);
    }
    if (raced < 20) fail(`lap v2: only ${raced} racer,cars lines in the race state`);
    const aius = base.B.lines("aius");
    if (aius.length !== 1 || Number(aius[0][0]) !== 1320) fail(`lap v2: expected one racer,aius line at tick 1320, got ${JSON.stringify(aius)}`);
    const g = base.seen.grid;
    const ai = count(g, LIVERY), me = count(g, BODY);
    if (ai < 60 || me < 30) fail(`lap v2 grid: the 8 cars are not all in view (${ai} livery pixels, ${me} player pixels)`);
    for (let k = 0; k < 4; k++) if (count(g, [LIVERY[0] + 8 * k, LIVERY[0] + 8 * k + 8]) < 6) fail(`lap v2 grid: livery ${k} is not in view`);
    if (BREAK === "pid") return;
    const again = await lap();
    if (again.crcs.join(" ") !== list) fail("lap v2's CRC list changes between two runs");
    const aff = await lap({ affine: true });
    if (aff.crcs.join(" ") !== list) fail("lap v2: the AFFINE fill's CRC list differs from the CPU fill's");
    if (OUT) await shot(`${OUT}/race_grid.png`, base.B, g);
}

async function shot(path, B, px) {
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(path, Uint32Array.from(px, (v) => (v ? pal[v] : 0xff000000)), W, H);
}

/** The whole race at the recorded driver: states, result lines, HUD hashes. */
async function race(ref) {
    const B = await boot();
    key(B.S, "e");
    key(B.S, "a");
    const hud = {};
    B.run(10);
    hud.grid = bands(B.view());
    B.S.demo.input(5); // fire starts the countdown
    B.S.demo.inputRelease(5);
    B.run(20);
    hud.countdown = bands(B.view());
    B.run(200);
    hud.race = bands(B.view());
    if (OUT) await shot(`${OUT}/race_race.png`, B, B.view());
    key(B.S, "w");
    if (!B.until("state", "finish", 900)) return fail("race: the finish state is never reached");
    B.run(2); // the shown page is the previous frame
    hud.finish = bands(B.view());
    if (!B.until("state", "results", 300)) return fail("race: the results are never reached");
    B.run(2);
    hud.results = bands(B.view());
    if (OUT) await shot(`${OUT}/race_results.png`, B, B.view());
    B.run(2);
    raceChecks(B, ref, hud);
    return B;
}

function raceChecks(B, ref, hud) {
    const states = B.lines("state").map((l) => l[0]).join(" ");
    if (states !== "countdown race finish results") fail(`race: states ${states}`);
    const [r] = B.lines("result");
    const [w] = B.lines("watch");
    if (!r || !w) return fail("race: no racer,result / racer,watch line");
    const [outcome, hash, ...rest] = r;
    const finish = rest.slice(0, 8).map(Number), order = rest.slice(8, 16).map(Number);
    if (PRINT) console.log(`PIN_RESULT = "${hash}"`, `// order ${order} finish ${finish}`);
    else if (hash !== PINS.result) fail(`race: result hash ${hash} != the pin ${PINS.result}`);
    if (outcome !== "win") fail(`race: outcome ${outcome}, expected a win`);
    if (finish.join() !== ref.finish.join()) fail(`race: finish ticks ${finish} != the Lua reference's ${ref.finish}`);
    if (order[0] !== 0 || new Set(order).size !== 8) fail(`race: the player does not win, or the order ${order} is not a permutation`);
    const off = w.slice(0, 8).map(Number), wall = w.slice(8, 16).map(Number);
    if (Math.max(...off) > 60 || Math.max(...wall) > 60) fail(`race: a car left the asphalt (${off}) or stuck to a wall (${wall}) for over 2 s`);
    for (const [s, h] of Object.entries(hud)) {
        if (PRINT) console.log(`PIN_H ${s} = "${h}"`);
        else if (h !== PINS.hud[s]) fail(`race: HUD bands at ${s} hash ${h} != the pin ${PINS.hud[s]}`);
    }
}

async function crest() {
    const B = await boot();
    key(B.S, "k");
    B.run(6);
    const px = B.view();
    const near = count(px, [LIVERY[0], LIVERY[0] + 8]); // AI car 1: the car before the crest
    const h = viewHash(px);
    if (PRINT) console.log(`PIN_CREST = "${h}"`);
    else if (h !== PINS.crest) fail(`crest pose: view hash ${h} != the pin ${PINS.crest}`);
    const hidden = count(px, [LIVERY[0] + 8, LIVERY[0] + 16]); // AI car 2 (yellow), past the crest: painted over by the road
    if (near < 4) fail(`crest pose: the car before the crest is not drawn (${near} pixels)`);
    if (hidden !== 0) fail(`crest pose: the car past the crest shows ${hidden} pixels through the road`);
    if (OUT) await shot(`${OUT}/race_crest.png`, B, px);
}

async function keys() {
    const B = await boot();
    key(B.S, "e");
    B.run(4);
    key(B.S, "s"); // the grid starts the countdown; the second s is refused (no second line), r aborts to the grid
    B.run(2);
    key(B.S, "s");
    B.run(2);
    key(B.S, "r");
    B.run(2);
    const seq = B.lines("state").map((l) => l[0]).join(" ");
    if (seq !== "countdown grid") fail(`keys: s, s, r logged the states "${seq}", expected "countdown grid"`);
    key(B.S, "n"); // M2's keys still work: n leaves the race and drives
    B.run(4);
    key(B.S, "b");
    B.run(120);
    if (B.lines("phys").length < 1) fail("keys: lap v1 (b) prints no physics line after the race");
}

const ref = await fixture();
await lapChecks(ref);
if (BREAK !== "pid") {
    await race(ref);
    await crest();
    await keys();
}
if (BREAK) {
    const want = BREAK === "pid" ? "reference's" : "pin";
    if (!errors.some((e) => e.includes(want))) { console.error(`racer_race: --break ${BREAK} was NOT caught (${errors.length} errors, none naming ${want})`); process.exit(1); }
    console.log(`racer_race PASS (--break ${BREAK} caught: ${errors[0]})`);
} else if (errors.length) {
    console.error(errors.map((e) => `racer_race: ${e}`).join("\n"));
    process.exit(1);
} else console.log("racer_race PASS");
