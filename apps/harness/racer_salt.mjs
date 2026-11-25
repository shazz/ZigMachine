// Headless RACER on Salt Flats (R82 Kestrel Racing M5, the first Track Kit track: tools/racer/tracks/, docs/ports/kestrel_racing/M5.md).
// Key t twice from the oval selects it (oval, city, salt). Checks:
//   1. the track loads (its name SALT in the racer,csv lines) and the cart still has RAM to spare;
//   2. the ATTRACT poses (keys A-H, R = 5): the views pinned, CPU fill = CHISEL AFFINE fill byte for byte, no index 0 left;
//   3. the FIVE HEAVIEST poses of the converter's priced-frame walk (tools/racer/tracks/salt_flats.heavy.json: lap v0 script
//      frames): the Python reference renderer (tools/racer/ref_render.py --frame) = the cart, pixel diff 0;
//   4. the FLYBY (lap v0, 720 frames): its 12-entry CRC list pinned, the same on both fill paths;
//   5. key i: LIT and SOFT change the baked view, three presses give it back;
//   6. the race benchmark (x) runs on it with the player on the pilot.
//   node apps/harness/racer_salt.mjs [<shot dir>] [--break pin|ref] [--print-pins]
// --break pin flips one view pixel, --break ref asks the reference for the frame after a heavy one: each must be caught.
import { mkdir, mkdtemp, readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["pin", "ref"].includes(BREAK)) { console.error(`racer_salt: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const BLOB = "apps/zig/assets/screens/racer/salt.ktrk";
const HEAVY = JSON.parse(await readFile("tools/racer/tracks/salt_flats.heavy.json", "utf8")).frames;
const PINS = ["6c63abb48e21acf9", "b0b99ba7221639b9", "ba237358eac43561", "179d9911b57f1a84", "f0906add95c192aa", "5ac291cefd345ccc", "3e53c193f4bbf931", "5fc1aa0bcc0bf96f"]; // sha256 (16 hex) of rows 12..187, CPU fill, R = 5, poses A-H
const LAP_PIN = "c8e666a7 e001688f c4f59708 96ac61f8 68292081 bc177071 8192ea42 577507b6 483815ac d03bc05d a22be921 1a0efa2d"; // the flyby, R = 5, CPU, mulsh
const errors = [];
const fail = (m) => errors.push(m);

async function boot() {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s));
    key(S, "5");
    key(S, "t");
    key(S, "t"); // oval -> city -> salt; the lap script restarts at frame 0
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        const p = [0, 1].find((q) => S.demo.isPlaneEnabled(q)) ?? 0;
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * p, true), W * H).slice();
    };
    const csv = () => {
        const l = log.filter((s) => s.startsWith("racer,csv,")).pop();
        return l ? { track: l.split(",")[3], fill: l.split(",")[5], polys: +l.split(",")[10] } : null;
    };
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    return { S, log, view, csv, run, lines: (k) => log.filter((s) => s.startsWith(`racer,${k},`)) };
}
const rowsHash = (px) => createHash("sha256").update(px.subarray(Y0 * W, Y1 * W)).digest("hex").slice(0, 16);
const same = (a, b) => a.subarray(Y0 * W, Y1 * W).every((v, i) => v === b[Y0 * W + i]);

async function shot(B, name) {
    if (!OUT) return;
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(`${OUT}/${name}`, Uint32Array.from(B.view(), (v) => (v ? pal[v] : 0xff000000)), W, H);
}

async function attract() {
    const B = await boot();
    const ram = B.log.find((l) => l.includes("cart RAM free"));
    const free = ram ? +ram.match(/RAM free (\d+) KB/)[1] : -1;
    if (free < 64) fail(`cart RAM free ${free} KB with the three tracks (want >= 64): ${ram}`);
    B.run(2);
    const pal = new Uint32Array(B.S.memory.buffer, B.S.machine.hwVideoBase() + OFF_PAL, 256);
    if (pal[4] !== pal[16 + 8 + 7]) fail(`the far ground (index 4) ${pal[4].toString(16)} != a baked flat salt face (ramp 1, level 7) ${pal[31].toString(16)}: a seam at the draw distance`);
    const cpu = [], hashes = [];
    for (let k = 0; k < 8; k++) {
        key(B.S, "ABCDEFGH"[k]);
        B.run(34);
        const px = B.view(), c = B.csv();
        if (BREAK === "pin" && k === 5) px[90 * W + 200] ^= 0x40;
        if (!c || c.track !== "SALT" || c.fill !== "cpu" || c.polys === 0) fail(`pose ${"ABCDEFGH"[k]}: counts ${JSON.stringify(c)}`);
        const zeros = px.subarray(Y0 * W, Y1 * W).filter((v) => v === 0).length;
        if (zeros > 0.005 * W * (Y1 - Y0)) fail(`pose ${"ABCDEFGH"[k]}: ${zeros} view pixels of index 0`);
        cpu.push(px);
        hashes.push(rowsHash(px));
        if (k === 0 || k === 6) await shot(B, `racer_salt_pose_${"ABCDEFGH"[k]}.png`);
    }
    if (PRINT) console.log(`const PINS = [${hashes.map((h) => `"${h}"`).join(", ")}];`);
    else hashes.forEach((h, k) => { if (h !== PINS[k]) fail(`pose ${"ABCDEFGH"[k]}: view ${h} != pin ${PINS[k]}`); });
    key(B.S, "f");
    for (let k = 0; k < 8; k++) {
        key(B.S, "ABCDEFGH"[k]);
        B.run(34);
        if (!same(B.view(), cpu[k])) fail(`pose ${"ABCDEFGH"[k]}: AFFINE fill differs from the CPU fill`);
    }
    key(B.S, "f");
    key(B.S, "C");
    B.run(4);
    const flat = B.view(), tags = [];
    for (let i = 0; i < 3; i++) {
        key(B.S, "i");
        B.run(4);
        tags.push(B.lines("shade").pop());
        if (i < 2 && same(B.view(), flat)) fail(`key i (${tags[i]}): the view did not change`);
    }
    if (!same(B.view(), flat)) fail(`key i three times: the baked view did not come back (${tags})`);
}

/** The flyby at script frame f, paused there; both pages hold it after one more frame. */
async function heavy() {
    const dir = await mkdtemp(`${tmpdir()}/racer_salt_`);
    for (const f of HEAVY) {
        const B = await boot();
        B.run(f);
        key(B.S, "p");
        B.run(2);
        const out = `${dir}/h${f}.raw`;
        execFileSync("python3", ["-I", "tools/racer/ref_render.py", BLOB, "--frame", String(BREAK === "ref" ? f + 1 : f), "-o", out]);
        const ref = await readFile(out), got = B.view().subarray(Y0 * W, Y1 * W);
        let diff = 0, first = -1;
        for (let i = 0; i < ref.length; i++) if (ref[i] !== got[i]) { diff++; if (first < 0) first = i; }
        if (diff) fail(`heavy frame ${f}: the Python reference differs in ${diff} pixels (first at x ${first % W}, y ${Y0 + Math.floor(first / W)})`);
        if (f === HEAVY[0]) await shot(B, `racer_salt_heavy_${f}.png`);
    }
}

async function lap(affine) {
    const B = await boot();
    if (affine) key(B.S, "f");
    B.run(724);
    return B.lines("crc").map((l) => l.split(",")[3]).join(" ");
}

async function race() {
    const B = await boot();
    key(B.S, "x");
    B.run(400);
    const c = B.csv(), cars = B.lines("cars").length;
    if (!c || c.track !== "SALT" || c.polys === 0) fail(`race benchmark on salt: counts ${JSON.stringify(c)}`);
    if (cars === 0) fail("race benchmark on salt: no racer,cars lines");
}

await attract();
if (BREAK !== "pin") await heavy();
if (!BREAK) {
    const a = await lap(false), b = await lap(true);
    if (a.split(" ").length !== 12) fail(`flyby: ${a.split(" ").length} CRC lines, want 12`);
    if (a !== b) fail(`flyby CRC list differs between the CPU and the AFFINE fill: ${a} vs ${b}`);
    if (PRINT) console.log(`const LAP_PIN = "${a}";`);
    else if (a !== LAP_PIN) fail(`flyby CRC list ${a} != pin`);
    await race();
}
if (BREAK) {
    if (errors.length === 0) { console.error(`racer_salt --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`racer_salt --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`racer_salt: ${e}`); process.exit(1); }
console.log(`racer_salt: PASS (8 attract poses pinned, CPU = AFFINE; ${HEAVY.length} heaviest poses = the Python reference; flyby CRC list x2; key i; race on the pilot)`);
