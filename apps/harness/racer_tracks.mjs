// Headless RACER on a Track Kit track (R82 Kestrel Racing M5: Salt Flats, Neon Docks, Glacier Pass: tools/racer/tracks/,
// docs/ports/kestrel_racing/M5.md), a FILE on the cart's disk (racer_disk.mjs). Key t from the oval walks the disk's tracks
// (CITY, SALT, NEON, GLACIER: tools/mkdisks.sh's order). Checks, for --track NAME (default SALT):
//   1. the track loads off the disk (its name in the racer,csv lines) and the cart still has RAM to spare;
//   2. the ATTRACT poses (keys A-H, R = 5): the views pinned, CPU fill = CHISEL AFFINE fill byte for byte, no index 0 left;
//   3. the FIVE HEAVIEST poses of the converter's priced-frame walk (tools/racer/tracks/salt_flats.heavy.json: lap v0 script
//      frames): the Python reference renderer (tools/racer/ref_render.py --frame) = the cart, pixel diff 0;
//   4. the FLYBY (lap v0, 720 frames): its 12-entry CRC list pinned, the same on both fill paths;
//   5. key i: LIT and SOFT change the baked view, three presses give it back;
//   6. the race benchmark (x) runs on it with the player on the pilot.
//   7. the far ground (palette index 4) = a baked flat face of the far-ground ramp at the mood's level (no seam).
//   node apps/harness/racer_tracks.mjs [<shot dir>] [--track SALT|NEON|GLACIER] [--break pin|ref] [--print-pins]
// --break pin flips one view pixel, --break ref asks the reference for the frame after a heavy one: each must be caught.
import { mkdir, mkdtemp, readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
const TRACK = argv.includes("--track") ? argv[argv.indexOf("--track") + 1] : "SALT";
const T = {
    SALT: { taps: 2, blob: "salt", heavy: "salt_flats",
        // M5 finish: re-pinned for Salt Flats' own noon sky and peaks backdrop (its faces did not change)
        pins: ["857f9dc956282586", "86f5b3f55f4341d0", "4d45cb7a00b52097", "9b11c0bd9f975226", "650c9ac4b3dbb9d7", "0bfa26f4df1f0d5d", "7546f1170ff9ccbe", "74941d9bf24c074a"],
        lap: "4beb6522 2e091990 95dcf954 7224d3f1 6cfd58b7 f2957eca 8ec88c66 eccf331e af67c2bb 6138680d 74fdc3ea b3eedf24" },
    NEON: { taps: 3, blob: "neon", heavy: "neon_docks",
        pins: ["f5b2843e157bae0c", "e1f2e7d5cc9ded64", "4e6cbf09d3175def", "2c9ad79430a5347c", "c9eda8386708d4dc", "98d8893e573e9c9b", "5a387c19a1025c22", "d70c82de3fbb6453"],
        lap: "f68eba4b d04c85c3 9a4279c8 3387cb2c 77a459af 42ddf8e9 6e3d167d e32242eb 67f83142 a331d770 5f086e22 9ca23ac9" },
    GLACIER: { taps: 4, blob: "glacier", heavy: "glacier_pass",
        // M5 finish: re-pinned for the snow banks' toe (the seam at the valley floor); its tunnel's zone is in the cockpit third
        pins: ["5cf940239a50f36a", "12bc58aa9778e2f1", "c477ca483985dab1", "81bb06680d0fba6a", "98a8fdb4608d4226", "8f23c0029ce0893e", "d2cf52a857ea8d7d", "60c8758a297f5db8"],
        lap: "2ea9bcde 436b3aea 75e5573e 23dcde1d 00ac7446 ca5da7df a4b923d8 f89c332b b9ba39cb 97a74682 6dedea32 0779f691" },
}[TRACK];
if (!T) { console.error(`racer_tracks: unknown --track ${TRACK}`); process.exit(1); }
const TAG = `racer_tracks ${TRACK}`;
if (BREAK !== null && !["pin", "ref"].includes(BREAK)) { console.error(`${TAG}: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv.find((a, i) => !a.startsWith("--") && !["--track", "--break"].includes(argv[i - 1])) ?? null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const BLOB = `apps/zig/assets/screens/racer/${T.blob}.ktrk`;
const HEAVY = JSON.parse(await readFile(`tools/racer/tracks/${T.heavy}.heavy.json`, "utf8")).frames;
const PINS = T.pins; // sha256 (16 hex) of rows 12..187, CPU fill, R = 5, poses A-H
const LAP_PIN = T.lap; // the flyby, R = 5, CPU, mulsh
const blob = await readFile(BLOB), dvb = new DataView(blob.buffer, blob.byteOffset);
const moodAt = dvb.getUint32(100, true);
const FAR = moodAt ? { ramp: blob[moodAt], level: blob[moodAt + 1] } : { ramp: 1, level: 4 }; // tools/racer/mood.py
const errors = [];
const fail = (m) => errors.push(m);

async function boot() {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook());
    key(S, "5");
    key(S, "q"); // M6: the horizon haze off, so every pin here is still M5's (racer_haze.mjs checks the haze on)
    for (let i = 0; i < T.taps; i++) key(S, "t"); // oval -> CITY -> SALT -> NEON -> GLACIER; the lap script restarts at frame 0
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
    const flatAt = 16 + FAR.ramp * 8 + FAR.level;
    if (pal[4] !== pal[flatAt]) fail(`the far ground (index 4) ${pal[4].toString(16)} != a baked flat face (ramp ${FAR.ramp}, level ${FAR.level}) ${pal[flatAt].toString(16)}: a seam at the draw distance`);
    const cpu = [], hashes = [];
    for (let k = 0; k < 8; k++) {
        key(B.S, "ABCDEFGH"[k]);
        B.run(34);
        const px = B.view(), c = B.csv();
        if (BREAK === "pin" && k === 5) px[90 * W + 200] ^= 0x40;
        if (!c || c.track !== TRACK || c.fill !== "cpu" || c.polys === 0) fail(`pose ${"ABCDEFGH"[k]}: counts ${JSON.stringify(c)}`);
        const zeros = px.subarray(Y0 * W, Y1 * W).filter((v) => v === 0).length;
        if (zeros > 0.005 * W * (Y1 - Y0)) fail(`pose ${"ABCDEFGH"[k]}: ${zeros} view pixels of index 0`);
        cpu.push(px);
        hashes.push(rowsHash(px));
        if (k === 0 || k === 6) await shot(B, `racer_${T.blob}_pose_${"ABCDEFGH"[k]}.png`);
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
    const dir = await mkdtemp(`${tmpdir()}/racer_tracks_`);
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
        if (f === HEAVY[0]) await shot(B, `racer_${T.blob}_heavy_${f}.png`);
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
    if (!c || c.track !== TRACK || c.polys === 0) fail(`race benchmark: counts ${JSON.stringify(c)}`);
    if (cars === 0) fail("race benchmark: no racer,cars lines");
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
    if (errors.length === 0) { console.error(`${TAG} --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`${TAG} --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`${TAG}: ${e}`); process.exit(1); }
console.log(`${TAG}: PASS (8 attract poses pinned, CPU = AFFINE; ${HEAVY.length} heaviest poses = the Python reference; flyby CRC list x2; key i; race on the pilot)`);
