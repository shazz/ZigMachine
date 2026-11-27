// Headless RACER, the 32X feel (R82, apps/zig/scenes/racer/arcade*.zig, wall.zig, docs/ports/kestrel_racing/FEEL.md). Checks:
//   1. an ARCADE race (the default PHYSICS) on Salt Flats, the player flown by the AI's controller in the arcade model (key L,
//      warp): grid, countdown, race, finish, results; every car finishes, none off the asphalt or on a wall for 2 s; the
//      result hash pinned (the Zig model is the arcade's oracle); the grid view pinned (the cars drawn at the track's car
//      scale, the camera grown with them), and it differs from the CLASSIC grid's (key T: the car at freds72's size);
//   2. the same race in CLASSIC (key T, logged racer,physics,CLASSIC) finishes with another result: the option is in force;
//   3. a running bench lap (x) is left with Backspace for the select (racer,front,select), its lap CRCs stopped;
//   4. --break feel (key I: the arcade's drag doubled) must move the arcade result and be caught.
//   node apps/harness/racer_feel.mjs [<shot dir>] [--break feel] [--print-pins]
import { createHash } from "node:crypto";
import { mkdir, readFile } from "node:fs/promises";
import { diskHook, ZMD } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && BREAK !== "feel") { console.error(`racer_feel: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100, SALT_TAPS = 2;
const PINS = { result: "6434df19", grid: "caafab3fc3b7" };
const errors = [];
const fail = (m) => errors.push(m);

async function boot() {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook(new Uint8Array(await readFile(ZMD))));
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p))[0] ?? 0;
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * shown(), true), W * H).slice();
    };
    const lines = (kind) => log.filter((l) => l.startsWith(`racer,${kind},`)).map((l) => l.split(",").slice(2));
    const until = (kind, state, max) => { for (let i = 0; i < max; i++) { S.frame(); if (lines(kind).some((l) => l[0] === state)) return true; } return false; };
    if (BREAK) key(S, "I");
    for (let i = 0; i < SALT_TAPS; i++) { key(S, "t"); run(3); }
    return { S, log, run, view, lines, until };
}
const hash = (px) => createHash("sha256").update(px.subarray(Y0 * W, Y1 * W)).digest("hex").slice(0, 12);

async function shot(name, B, px) {
    if (!OUT) return;
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(`${OUT}/${name}`, Uint32Array.from(px, (v) => (v ? pal[v] : 0xff000000)), W, H);
}

/** A race on SALT flown by the AI's controller (key L) in the PHYSICS option's model; `classic` flips the option first. */
async function race(classic) {
    const B = await boot();
    if (classic) key(B.S, "T");
    key(B.S, "e"); B.run(2);
    key(B.S, "L"); B.run(40);
    const grid = B.view();
    await shot(`feel_grid_${classic ? "classic" : "arcade"}.png`, B, grid);
    B.S.demo.input(5); B.S.demo.inputRelease(5);
    B.run(400);
    await shot(`feel_race_${classic ? "classic" : "arcade"}.png`, B, B.view());
    key(B.S, "w");
    if (!B.until("state", "results", 4000)) fail(`${classic ? "classic" : "arcade"} race: the results are never reached`);
    const [r] = B.lines("result"), [w] = B.lines("watch");
    return { B, grid: hash(grid), r, w };
}

function arcadeChecks(a) {
    if (!a.r || !a.w) return fail("arcade race: no racer,result / racer,watch line");
    const [outcome, h, ...rest] = a.r;
    const finish = rest.slice(0, 8).map(Number);
    if (PRINT) console.log(`PIN result "${h}" grid "${a.grid}"`, `// ${outcome} finish ${finish}`);
    else if (h !== PINS.result) fail(`arcade race: result hash ${h} != the pin ${PINS.result}`);
    if (!PRINT && !BREAK && a.grid !== PINS.grid) fail(`arcade grid: view ${a.grid} != the pin ${PINS.grid}`);
    if (finish.some((f) => f === 0)) fail(`arcade race: a car never finished (${finish})`);
    const off = a.w.slice(0, 8).map(Number), wall = a.w.slice(8, 16).map(Number);
    if (Math.max(...off) > 60 || Math.max(...wall) > 60) fail(`arcade race: a car left the asphalt (${off}) or stuck to a wall (${wall}) for over 2 s`);
}

async function bench() {
    const B = await boot();
    key(B.S, "x");
    B.run(300);
    const n = B.lines("crc").length;
    key(B.S, 8);
    B.run(200);
    if (B.log.filter((l) => l.startsWith("racer,front,")).at(-1) !== "racer,front,select") fail("Backspace in a running bench lap: not the select");
    if (B.lines("crc").length !== n) fail("Backspace in a running bench lap: its CRC lines go on");
}

const a = await race(false);
arcadeChecks(a);
if (!BREAK) {
    const c = await race(true);
    if (!c.B.log.includes("racer,physics,CLASSIC")) fail("key T: no racer,physics,CLASSIC line");
    if (c.r && a.r && c.r[1] === a.r[1]) fail("CLASSIC and ARCADE races end with the same result hash: the option is not in force");
    if (c.grid === a.grid) fail("the arcade grid looks like the classic one: no car scale");
    await bench();
}
if (BREAK) {
    if (errors.length === 0) { console.error("racer_feel --break feel: NOT caught"); process.exit(1); }
    console.log(`racer_feel --break feel: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`racer_feel: ${e}`); process.exit(1); }
console.log("racer_feel: PASS (an arcade race on Salt Flats at its scales, pinned; CLASSIC differs; Backspace leaves a bench lap)");
