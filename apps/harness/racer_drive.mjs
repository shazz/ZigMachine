// Headless RACER driving (apps/zig/scenes/racer.zig, R82 Kestrel Racing M2). Boots the cart as the page loads it and checks:
//   1. LAP v1 (key b): 720 frames of the Lua reference's lap buttons. The physics line the cart logs every 60 frames
//      (racer,phys,<ticks>,<px>,<py>,<pz>,<angle>,<u>,<hits>,<slides>) equals the reference's state at that tick,
//      bit for bit (the fixture tools/racer/phys_fixture.py wrote from z8lua: apps/zig/assets/screens/racer/phys_lap.bin);
//      the view's CRC list is the same twice, with the CPU fill and the CHISEL AFFINE fill, and pinned;
//   2. the car is drawn (its ramps 12-14 are in the view) in the far and near POVs and not in the cockpit's; tyre smoke
//      (R82 bug pass, racer/smoke.zig) appears while the lap slides: against the same lap with the smoke hidden (key 1),
//      every changed pixel is lighter in its own ramp, one level a puff over it (real transparency: no dither, no colour of its own); the cockpit's view differs;
//   3. DRIVING (key n): the arrows and the joystick fire move the car, left / right turn it, release slows it, r puts
//      it back on the grid; consecutive frames are all different (the 60 Hz pose interpolation: no 30 Hz stutter);
//   4. the --break slip switch (key Z, car.break_slip) moves the slide count off the reference and is caught.
//   node apps/harness/racer_drive.mjs [<shot dir>] [--break slip|pin] [--print-pins]
import { mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["slip", "pin"].includes(BREAK)) { console.error(`racer_drive: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const LAP_FRAMES = 720, CAR = [16 + 12 * 8, 16 + 14 * 8 + 8];
// the lap v1 CRC32 list (every 60 frames; oval, R = 5, CPU fill, mulsh, the far POV): the benchmark's proof of sameness
// M5 car scale (the GT drawn 2x, the far POV shows it every frame): re-pinned; the physics line is unchanged
const LAP_PIN = "1997ac9a c3548c6a b36c0d91 a40d1cc6 28ccd8f5 19e1272f 3bb1ccf3 f5a427d2 8664cf04 152f6aef e1cfc83b ed67b6f0"; // board batch: the wheels turn and steer (wheelspin.zig) and the near chase camera pulled back (the physics lines unmoved), the footprint shadow
const errors = [];
const fail = (m) => errors.push(m);

const fixture = async () => {
    const b = await readFile("apps/zig/assets/screens/racer/phys_lap.bin"), dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    const n = dv.getUint32(4, true), rows = [];
    for (let i = 0; i < n; i++) rows.push(Array.from({ length: 15 }, (_, k) => dv.getInt32(8 + 60 * i + 4 * k, true)));
    return rows; // btn hits px py pz vx vy vz angle face u v tr sa slide
};

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
    return { S, log, view, lines, run };
}

const count = (px, lo, hi) => { let n = 0; for (let i = Y0 * W; i < Y1 * W; i++) if (px[i] >= lo && px[i] < hi) n++; return n; };
const hashOf = (px) => createHash("sha256").update(px.subarray(Y0 * W, Y1 * W)).digest("hex").slice(0, 12);

/** One bench lap: the CRC list, the physics lines, the car's pixel count and the sampled views. */
async function lap(opts = {}) {
    const B = await boot();
    if (opts.affine) key(B.S, "f");
    if (BREAK === "slip") key(B.S, "Z");
    if (opts.nosmoke) key(B.S, "1");
    key(B.S, "b");
    for (let i = 0; i < (opts.cockpit ?? 0); i++) key(B.S, "v");
    const seen = { car: 0, views: [], px: [] };
    B.run(LAP_FRAMES, (i) => {
        if (i % 10 !== 9) return;
        const px = B.view();
        seen.car = Math.max(seen.car, count(px, CAR[0], CAR[1]));
        seen.views.push(hashOf(px));
        seen.px.push(px);
    });
    return { B, crcs: B.lines("crc").map((l) => l[1]), phys: B.lines("phys").map((l) => l.map(Number)), seen };
}

function checkPhysics(rows, phys, tag) {
    if (phys.length !== 12) return fail(`${tag}: ${phys.length} physics lines, expected 12`);
    let slides = 0, done = 0;
    for (const [ticks, px, py, pz, angle, u, hits, sl] of phys) {
        for (; done < ticks; done++) slides += rows[89 + done][14]; // bench tick i is the reference's row 88 + i
        const r = rows[88 + ticks];
        const want = [r[2], r[3], r[4], r[8], r[10], r[1], slides];
        const got = [px, py, pz, angle, u, hits, sl];
        if (want.some((w, k) => w !== got[k])) fail(`${tag}: tick ${ticks} state ${got} != the Lua reference's ${want}`);
    }
}

async function main() {
    const rows = await fixture();
    const base = await lap();
    if (BREAK === "pin") base.crcs[3] = "00000000";
    const list = base.crcs.join(" ");
    if (PRINT) console.log(`LAP_PIN = "${list}"`);
    else if (base.crcs.length !== 12 || list !== LAP_PIN) fail(`lap v1 CRC list ${list} != the pin ${LAP_PIN}`);
    const slipChecked = BREAK === "slip";
    checkPhysics(rows, base.phys, "lap v1");
    if (slipChecked) return;
    const again = await lap();
    if (again.crcs.join(" ") !== base.crcs.join(" ")) fail("lap v1's CRC list changes between two runs");
    const aff = await lap({ affine: true });
    if (aff.crcs.join(" ") !== base.crcs.join(" ")) fail("lap v1: the AFFINE fill's CRC list differs from the CPU fill's");
    if (base.seen.car < 150) fail(`the car is not drawn in the far POV (${base.seen.car} pixels of its ramps at most)`);
    smokeChecks(base, await lap({ nosmoke: true }));
    const cock = await lap({ cockpit: 2 });
    if (cock.seen.car > 0) fail(`the cockpit POV draws the car body (${cock.seen.car} pixels)`);
    if (cock.crcs.join(" ") === base.crcs.join(" ")) fail("the cockpit's CRC list equals the far POV's");
    checkPhysics(rows, cock.phys, "lap v1 (cockpit)");
    await driving();
    await shots();
}

/** The smoke: the lap with it against the lap without (key 1), sampled frames: each changed pixel exactly one level up. */
function smokeChecks(base, bare) {
    // one level up a puff (n levels where n puffs overlap: each its own lightening), never out of the ramp, never darker
    const ok = (a, b) => b >= 16 && a > b && (a - 16) >> 3 === (b - 16) >> 3;
    let changed = 0, wrong = 0, twice = 0;
    base.seen.px.forEach((a, k) => {
        const b = bare.seen.px[k];
        for (let i = Y0 * W; i < Y1 * W; i++) if (a[i] !== b[i]) { changed++; twice += a[i] - b[i] >= 2; if (!ok(a[i], b[i])) wrong++; }
    });
    if (changed < 200) fail(`no tyre smoke in a lap that slides 258 ticks (${changed} lightened pixels over the samples)`);
    if (wrong) fail(`tyre smoke: ${wrong} of ${changed} changed pixels are not lighter in their own ramp (one level a puff)`);
    else console.log(`  tyre smoke: ${changed} pixels lightened over the lap's samples (${twice} more than one level, under overlapping puffs), none otherwise changed`);
}

async function driving() {
    const B = await boot();
    key(B.S, "n");
    B.run(4);
    const pos = () => { const p = B.lines("phys"); return p.length ? p[p.length - 1].map(Number) : null; };
    B.S.demo.input(5); // the joystick fire accelerates
    const hashes = [];
    B.run(180, () => hashes.push(hashOf(B.view())));
    const moved = pos();
    if (!moved || moved[0] < 60) fail(`driving: after 180 frames of fire the car has made ${moved && moved[0]} ticks`);
    const stuck = hashes.slice(60).filter((h, i) => h === hashes[59 + i]).length;
    if (stuck > 0) fail(`driving: ${stuck} frames in 120 repeat the previous view (the pose must change every frame, not every tick)`);
    B.S.demo.input(2);
    B.run(120);
    B.S.demo.inputRelease(2);
    const left = pos();
    if (!left || left[4] === moved[4]) fail("driving: holding left does not turn the car");
    B.S.demo.input(3);
    B.run(120);
    B.S.demo.inputRelease(3);
    const right = pos();
    if (right[4] === left[4]) fail("driving: holding right does not turn the car");
    key(B.S, "r");
    B.run(62);
    const reset = pos();
    if (!reset || reset[0] > 31) fail("driving: r does not put the car back on the grid (the tick count restarts)");
    B.S.demo.inputRelease(5);
}

async function shots() {
    if (!OUT) return;
    for (const [name, vs] of [["far", 0], ["near", 1], ["cockpit", 2]]) {
        const B = await boot();
        key(B.S, "b");
        for (let i = 0; i < vs; i++) key(B.S, "v");
        B.run(400);
        const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
        await png(`${OUT}/drive_${name}.png`, Uint32Array.from(B.view(), (v) => (v ? pal[v] : 0xff000000)), W, H);
    }
}

await main();
if (BREAK) {
    const want = BREAK === "slip" ? "reference's" : "pin"; // slip must be seen in the physics state, not only in the pixels
    if (!errors.some((e) => e.includes(want))) { console.error(`racer_drive: --break ${BREAK} was NOT caught (${errors.length} errors, none naming ${want})`); process.exit(1); }
    console.log(`racer_drive PASS (--break ${BREAK} caught: ${errors[0]})`);
} else if (errors.length) {
    console.error(errors.map((e) => `racer_drive: ${e}`).join("\n"));
    process.exit(1);
} else console.log("racer_drive PASS");
