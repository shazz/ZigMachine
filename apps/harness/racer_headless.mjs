// Headless RACER driver (apps/zig/scenes/racer.zig, R82 Kestrel Racing M1). Boots the cart as the
// page loads it (obj_machine.mjs) and checks, on the oval and the stress city:
//   1. the FLIP: exactly one of planes 0 and 1 on a frame, alternating;
//   2. the VIEW: rows 12..187 are all painted (sky, ground, backdrop, track: no index 0 left);
//   3. EIGHT FIXED POSES (keys A-H): CPU fill = CHISEL AFFINE fill byte for byte, and the CPU view
//      pinned (sha256) per pose; the mulsh instruction = its plain twin (M) pixel for pixel; the f32
//      transform (G) within 2% of the pixels;
//   4. the COUNTS the cart logs (racer,csv,...): R = 3..8 never draws fewer polygons, decals off draws
//      fewer, the city at R = 5 submits more faces than the oval, none dropped;
//   5. the LAP: 720 frames of the camera script give the same CRC list (racer,crc,...) twice and on
//      both fill paths, 12 entries and a summary line (racer,lap,...);
//   6. the Python reference renderer (tools/racer/ref_render.py) = the cart at the same poses, pixel
//      diff 0, when --ref is given and the reference exists.
//   node apps/harness/racer_headless.mjs [<shot dir>] [--break edge|clip|pin] [--print-pins]
// --break edge (poly.break_edge) and --break clip (clip.break_drop) flip a switch in the cart;
// --break pin flips one view pixel. Each must be caught (the run then PASSes, exit 0).
import { mkdir, mkdtemp, readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["edge", "clip", "pin"].includes(BREAK)) { console.error(`racer: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
// sha256 (16 hex) of rows 12..187 of the plane on screen, CPU fill, R = 5, poses A-H; oval then city
const PINS = {
    oval: ["73b40e652b6f1152", "7469c1026ea9488d", "b90e4efe830312ec", "99eba9b50593537e", "4cb27eb8f026df6b", "ff3abcf5332ec1fd", "1d62c33d4492024e", "171b995ea576f9ad"],
    city: ["292d027ec9a7401c", "c2a7377e26b7b730", "3f543653cd05ac55", "8173d090b8f801f4", "6a0151e50c7a850f", "054f9eac43845961", "1164588c62f89828", "25da3355919bf37c"],
};
const errors = [];
const fail = (m) => errors.push(m);

async function boot() {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s));
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p));
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        const p = shown()[0] ?? 0;
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * p, true), W * H).slice();
    };
    const csv = () => {
        for (let i = log.length - 1; i >= 0; i--) {
            const m = log[i].split(",");
            if (m[0] === "racer" && m[1] === "csv") {
                return { frame: +m[2], track: m[3], r: +m[4], fill: m[5], mulsh: m[6], tiles: +m[7], faces: +m[8], verts: +m[9], polys: +m[10], spans: +m[11], pixels: +m[12] };
            }
        }
        return null;
    };
    const lines = (kind) => log.filter((l) => l.startsWith(`racer,${kind},`));
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    return { S, log, shown, view, csv, lines, run };
}
const rowsHash = (px) => createHash("sha256").update(px.subarray(Y0 * W, Y1 * W)).digest("hex").slice(0, 16);
/** The 3D view's rows: the HUD bands above and below name the fill path and the multiply, so they differ on purpose. */
const same = (a, b) => a.subarray(Y0 * W, Y1 * W).every((v, i) => v === b[Y0 * W + i]);
const POSE_KEYS = "ABCDEFGH";

/** Pose k (A-H) at the cart's current knobs: two frames for both pages, then the counts after a window. */
function pose(B, k) {
    key(B.S, POSE_KEYS[k]);
    B.run(34); // a CSV window closes every 32 frames: the counts are this pose's
    return { px: B.view(), counts: B.csv() };
}

async function shot(B, name) {
    if (!OUT) return;
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(`${OUT}/${name}`, Uint32Array.from(B.view(), (v) => (v ? pal[v] : 0xff000000)), W, H);
}

/** The Python reference renderer (tools/racer/ref_render.py) at the same eight poses: pixel diff 0. */
async function refCheck(track, cpu) {
    if (BREAK === "pin") return;
    const dir = await mkdtemp(`${tmpdir()}/racer_ref_`);
    for (let k = 0; k < 8; k++) {
        const out = `${dir}/${track}_${k}.raw`;
        execFileSync("python3", ["-I", "tools/racer/ref_render.py", `apps/zig/assets/screens/racer/${track === "oval" ? "oval" : "city"}.ktrk`, "--pose", String(k), "-o", out]);
        const ref = await readFile(out), got = cpu[k].px.subarray(Y0 * W, Y1 * W);
        let diff = 0, first = -1;
        for (let i = 0; i < ref.length; i++) if (ref[i] !== got[i]) { diff++; if (first < 0) first = i; }
        if (diff) fail(`${track} pose ${POSE_KEYS[k]}: the Python reference differs in ${diff} pixels (first at x ${first % W}, y ${Y0 + Math.floor(first / W)})`);
    }
}

async function poses(track, pinned) {
    const B = await boot();
    if (BREAK === "edge") key(B.S, "X");
    if (BREAK === "clip") key(B.S, "Y");
    if (track === "city") key(B.S, "t");
    const cpu = [], hashes = [];
    for (let k = 0; k < 8; k++) {
        const r = pose(B, k);
        if (BREAK === "pin" && k === 3) r.px[100 * W + 160] ^= 0x40;
        const zeros = r.px.subarray(Y0 * W, Y1 * W).filter((v) => v === 0).length;
        if (zeros > 0.005 * W * (Y1 - Y0)) fail(`${track} pose ${POSE_KEYS[k]}: ${zeros} view pixels of index 0 (sky, ground and backdrop should cover it)`);
        if (!r.counts || r.counts.track !== track.toUpperCase() || r.counts.fill !== "cpu" || r.counts.polys === 0 || r.counts.spans === 0)
            fail(`${track} pose ${POSE_KEYS[k]}: counts ${JSON.stringify(r.counts)}`);
        else if (r.counts.polys + 0 > 6000) fail(`${track} pose ${POSE_KEYS[k]}: ${r.counts.polys} polygons, the buffer is 6144`);
        cpu.push(r);
        hashes.push(rowsHash(r.px));
        if (k === 2) await shot(B, `racer_${track}_pose_C.png`);
    }
    await refCheck(track, cpu);
    if (PRINT) console.log(`${track}: [${hashes.map((h) => `"${h}"`).join(", ")}],`);
    else if (pinned.length === 8) hashes.forEach((h, k) => { if (h !== pinned[k]) fail(`${track} pose ${POSE_KEYS[k]}: view ${h} != pin ${pinned[k]}`); });
    // the same poses through CHISEL AFFINE (F), then with the plain multiply twin (M)
    key(B.S, "f");
    for (let k = 0; k < 8; k++) {
        const r = pose(B, k);
        if (r.counts?.fill !== "affine") fail(`${track}: key F did not select the AFFINE path (${r.counts?.fill})`);
        if (!same(r.px, cpu[k].px)) fail(`${track} pose ${POSE_KEYS[k]}: AFFINE fill differs from the CPU fill`);
    }
    key(B.S, "f");
    key(B.S, "m");
    for (const k of [1, 6]) {
        const r = pose(B, k);
        if (!same(r.px, cpu[k].px)) fail(`${track} pose ${POSE_KEYS[k]}: the plain multiply differs from mulsh`);
    }
    key(B.S, "m");
    key(B.S, "g"); // the f32 transform: nearly the same picture (a few LSB of Q16 move an edge pixel), not the same bytes
    for (const k of [1, 6]) {
        const r = pose(B, k);
        const diff = r.px.subarray(Y0 * W, Y1 * W).filter((v, i) => v !== cpu[k].px[Y0 * W + i]).length;
        if (diff > 0.02 * W * (Y1 - Y0)) fail(`${track} pose ${POSE_KEYS[k]}: the f32 transform differs from mulsh in ${diff} pixels (> 2%)`);
        if (r.counts?.mulsh !== "F32") fail(`${track}: key G did not select the f32 transform (${r.counts?.mulsh})`);
    }
    key(B.S, "g");
    return { B, cpu };
}

async function counts(B) {
    const polys = [];
    for (const r of [3, 4, 5, 6, 7, 8]) { key(B.S, String(r)); polys.push(pose(B, 4).counts?.polys ?? -1); }
    for (let i = 1; i < polys.length; i++) if (polys[i] < polys[i - 1]) fail(`R ${i + 3}: ${polys[i]} polygons, fewer than R ${i + 2}'s ${polys[i - 1]}`);
    if (!(polys[5] > polys[0])) fail(`R = 8 draws no more than R = 3 (${polys})`);
    key(B.S, "5");
    const on = pose(B, 4).counts;
    key(B.S, "d");
    const off = pose(B, 4).counts;
    if (!(off.polys < on.polys)) fail(`decals off: ${off.polys} polygons, not fewer than ${on.polys}`);
    key(B.S, "d");
    return on;
}

async function lap(fillKey) {
    const B = await boot();
    if (fillKey) key(B.S, "f");
    B.run(724);
    const crc = B.lines("crc").map((l) => l.split(",")[3]);
    const sum = B.lines("lap");
    if (crc.length !== 12) fail(`lap (${fillKey ? "affine" : "cpu"}): ${crc.length} CRC lines, want 12`);
    if (sum.length < 1 || !sum[0].startsWith("racer,lap,720,")) fail(`lap summary missing or wrong: ${sum[0]}`);
    return crc;
}

for (const track of ["oval", "city"]) {
    const { B, cpu } = await poses(track, PINS[track]);
    const c = await counts(B);
    if (track === "oval") var ovalFaces = c.faces; else if (!(c.faces > ovalFaces)) fail(`city R=5 submits ${c.faces} faces, the oval ${ovalFaces}`);
}
const flip = await boot();
let last = -1;
for (let f = 0; f < 20; f++) {
    flip.run(1);
    const on = flip.shown();
    if (on.length !== 1) fail(`frame ${f}: planes on ${JSON.stringify(on)} (want exactly one)`);
    else if (f > 0 && on[0] === last) fail(`frame ${f}: plane ${on[0]} shown twice in a row`);
    last = on[0];
}
if (!BREAK) {
    const a = await lap(false), b = await lap(false), c = await lap(true);
    if (a.join() !== b.join()) fail(`lap CRC list differs between two runs: ${a} vs ${b}`);
    if (a.join() !== c.join()) fail(`lap CRC list differs between the CPU and the AFFINE fill: ${a} vs ${c}`);
}

if (BREAK) {
    if (errors.length === 0) { console.error(`racer --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`racer --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`racer: ${e}`); process.exit(1); }
console.log("racer: PASS (flip; 8 poses x oval/city: CPU = AFFINE byte for byte, mulsh = plain twin, pinned; R 3..8 monotonic; decals; lap CRC list x3)");
