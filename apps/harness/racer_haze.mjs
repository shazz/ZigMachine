// RACER M6 the horizon haze (apps/zig/scenes/racer/haze.zig, docs/ports/kestrel_racing/M6.md): far faces drawn in palette
// entries blended toward the track's haze colour, by depth band, no per-pixel maths. For --track GLACIER | SALT (moods with a
// haze), the 8 attract poses (keys A-H, R = 5) and the race's grid (8 cars, R = 8):
//   1. haze OFF (key q) = the M5 hashes: the poses' views are racer_tracks.mjs' M5 pins byte for byte, index 4 the baked ground;
//   2. haze ON changes the far view: each differing pixel moves from a track colour to a pool entry (past the ramps) whose
//      colour is nearer the haze than the one it replaces, and most are an exact band blend; the near rows (the bottom 16) are
//      untouched; the far ground (index 4) is the full-strength blend (no seam at R); the views pinned; CPU = AFFINE;
//   3. the race's grid: the haze changes the far view only, the cars and their shadows at the bottom untouched;
//   4. NEON (no haze in its mood): q changes nothing.
//   node apps/harness/racer_haze.mjs [<shot dir>] [--track GLACIER|SALT] [--break absent|near] [--print-pins]
// --break absent (key N: the haze built, never applied) and --break near (key P: every band one nearer) must be caught.
import { mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { diskHook } from "./racer_disk.mjs";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
const TRACK = argv.includes("--track") ? argv[argv.indexOf("--track") + 1] : "GLACIER";
const T = {
    // M5's pins: racer_tracks.mjs' attract poses (haze off there too); the ON pins are this harness' own
    SALT: { taps: 2, blob: "salt",
        m5: ["857f9dc956282586", "86f5b3f55f4341d0", "4d45cb7a00b52097", "9b11c0bd9f975226", "650c9ac4b3dbb9d7", "0bfa26f4df1f0d5d", "7546f1170ff9ccbe", "74941d9bf24c074a"],
        on: ["e5d6038370ca4766", "52b42e65f2021bec", "fac9e82868071d3a", "4cd0a5b85b0381ef", "a042eca70f4fc6d8", "16fd0ad204ab1f80", "74c5c442a23ab7ef", "a19b0fed71e89623"] },
    GLACIER: { taps: 4, blob: "glacier",
        m5: ["5cf940239a50f36a", "12bc58aa9778e2f1", "c477ca483985dab1", "81bb06680d0fba6a", "98a8fdb4608d4226", "8f23c0029ce0893e", "d2cf52a857ea8d7d", "60c8758a297f5db8"],
        on: ["9c35f1b299ea2bd2", "e171f7691c9d26e9", "25deba36da3ca2e1", "125059e619ab3da6", "e167460f17a00db4", "c8aa25569d4e767a", "adf200baa73672ac", "afdbd1ced396df19"] },
}[TRACK];
const TAG = `racer_haze ${TRACK}`;
if (!T) { console.error(`${TAG}: unknown track`); process.exit(1); }
if (BREAK !== null && !["absent", "near"].includes(BREAK)) { console.error(`${TAG}: unknown --break ${BREAK}`); process.exit(1); }
const PRINT = argv.includes("--print-pins");
const OUT = argv.find((a, i) => !a.startsWith("--") && !["--track", "--break"].includes(argv[i - 1])) ?? null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 12, Y1 = 188, NEAR = 16, REG_FB_BASE = 0x44, OFF_PAL = 0x0100, BANDS = 4;
const blob = await readFile(`apps/zig/assets/screens/racer/${T.blob}.ktrk`), dvb = new DataView(blob.buffer, blob.byteOffset);
const moodAt = dvb.getUint32(100, true);
const HAZE = { rgb: [...blob.subarray(moodAt + 27, moodAt + 30)], start: blob[moodAt + 30], strength: blob[moodAt + 31] };
const POOL_LO = Math.min(256, 16 + 8 * Math.max(dvb.getUint32(36, true), 19)); // haze.zig: past the track's and the cars' ramps
const errors = [];
const fail = (m) => errors.push(m);
if (HAZE.strength === 0) fail(`${T.blob}.ktrk has no haze in its mood`);

async function boot(taps = T.taps) {
    const log = [];
    const S = await bootObj("site/carts/demo-racer.wasm", (s) => log.push(s), diskHook());
    key(S, "5");
    for (let i = 0; i < taps; i++) key(S, "t");
    if (BREAK === "absent") key(S, "N");
    if (BREAK === "near") key(S, "P");
    const view = () => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        const p = [0, 1].find((q) => S.demo.isPlaneEnabled(q)) ?? 0;
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * p, true), W * H).slice();
    };
    const pal = () => new Uint32Array(S.memory.buffer, S.machine.hwVideoBase() + OFF_PAL, 256).slice();
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    return { S, log, view, pal, run };
}
const rowsHash = (px) => createHash("sha256").update(px.subarray(Y0 * W, Y1 * W)).digest("hex").slice(0, 16);
const rgb = (c) => [c & 0xff, (c >> 8) & 0xff, (c >> 16) & 0xff];
const dist = (a, b) => a.reduce((s, v, i) => s + (v - b[i]) ** 2, 0);
const mix = (a, f) => a.map((x, i) => (HAZE.rgb[i] >= x ? x + Math.floor((HAZE.rgb[i] - x) * f / 255) : x - Math.floor((x - HAZE.rgb[i]) * f / 255)));

async function shot(B, name) {
    if (!OUT) return;
    const pal = B.pal();
    await png(`${OUT}/${name}`, Uint32Array.from(B.view(), (v) => (v ? pal[v] : 0xff000000)), W, H);
}

/** Compare a haze-off and a haze-on view: what moved must be far, a pool entry, toward the haze. Returns [changed, exact]. */
function judge(what, off, on, palOff, palOn) {
    let changed = 0, exact = 0;
    for (let y = Y0; y < Y1; y++) for (let x = 0; x < W; x++) {
        const a = off[y * W + x], b = on[y * W + x];
        if (a === b) continue;
        changed++;
        if (y >= Y1 - NEAR) { fail(`${what}: a near pixel (x ${x}, y ${y}) changed ${a} -> ${b}`); return [changed, exact]; }
        if (b < POOL_LO && !(a >= 112 && a < 168)) { fail(`${what}: (x ${x}, y ${y}) ${a} -> ${b}, not a haze pool entry`); return [changed, exact]; }
        const ca = rgb(palOff[a]), cb = rgb(palOn[b]);
        if (dist(cb, HAZE.rgb) > dist(ca, HAZE.rgb)) { fail(`${what}: (x ${x}, y ${y}) ${a} -> ${b} moved away from the haze`); return [changed, exact]; }
        for (let k = 1; k <= BANDS; k++) if (dist(cb, mix(ca, Math.floor(HAZE.strength * k / BANDS))) === 0) { exact++; break; }
    }
    return [changed, exact];
}

async function poses() {
    const B = await boot();
    key(B.S, "q");
    B.run(2);
    const palOff = B.pal(), off = [];
    for (let k = 0; k < 8; k++) {
        key(B.S, "ABCDEFGH"[k]);
        B.run(34);
        off.push(B.view());
        if (k === 0 || k === 6) await shot(B, `racer_haze_${T.blob}_${"ABCDEFGH"[k]}_off.png`);
        if (rowsHash(off[k]) !== T.m5[k]) fail(`haze off, pose ${"ABCDEFGH"[k]}: view ${rowsHash(off[k])} != M5's ${T.m5[k]}`);
    }
    key(B.S, "q");
    B.run(2);
    const palOn = B.pal(), hashes = [];
    const want4 = mix(rgb(palOff[4]), HAZE.strength);
    if (dist(rgb(palOn[4]), want4) !== 0) fail(`haze on: the far ground (index 4) ${rgb(palOn[4])} != the full blend ${want4}: a seam at R`);
    let total = 0, exact = 0;
    for (let k = 0; k < 8; k++) {
        key(B.S, "ABCDEFGH"[k]);
        B.run(34);
        const on = B.view(), [c, e] = judge(`pose ${"ABCDEFGH"[k]}`, off[k], on, palOff, palOn);
        total += c;
        exact += e;
        hashes.push(rowsHash(on));
        if (k === 0 || k === 6) await shot(B, `racer_haze_${T.blob}_${"ABCDEFGH"[k]}.png`);
    }
    if (total < 2000) fail(`haze on: only ${total} pixels changed over the 8 poses (the haze is absent)`);
    if (exact < total / 2) fail(`haze on: ${exact} of ${total} changed pixels an exact band blend (want most)`);
    if (PRINT) console.log(`on: [${hashes.map((h) => `"${h}"`).join(", ")}],`);
    else if (!BREAK) hashes.forEach((h, k) => { if (h !== T.on[k]) fail(`haze on, pose ${"ABCDEFGH"[k]}: view ${h} != pin ${T.on[k]}`); });
    key(B.S, "f");
    for (let k = 0; k < 8; k++) {
        key(B.S, "ABCDEFGH"[k]);
        B.run(34);
        if (rowsHash(B.view()) !== hashes[k]) fail(`haze on, pose ${"ABCDEFGH"[k]}: AFFINE fill differs from the CPU fill`);
    }
    return { total, exact };
}

async function grid() {
    const views = [];
    for (const on of [false, true]) {
        const B = await boot();
        key(B.S, "8");
        if (!on) key(B.S, "q");
        key(B.S, "e");
        B.run(40);
        views.push({ px: B.view(), pal: B.pal() });
        if (on) await shot(B, `racer_haze_${T.blob}_grid.png`);
    }
    const [c] = judge("race grid", views[0].px, views[1].px, views[0].pal, views[1].pal);
    if (c === 0) fail("race grid: the haze changed nothing at R 8");
}

async function neon() {
    const B = await boot(3);
    key(B.S, "C");
    B.run(34);
    const a = B.view();
    key(B.S, "q");
    B.run(4);
    if (rowsHash(B.view()) !== rowsHash(a)) fail("NEON (no haze in its mood): key q changed the view");
}

const r = await poses();
if (!BREAK) {
    await grid();
    await neon();
}
if (BREAK) {
    if (errors.length === 0) { console.error(`${TAG} --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`${TAG} --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`${TAG}: ${e}`); process.exit(1); }
console.log(`${TAG}: PASS (haze off = M5's 8 pins; on: ${r.total} far pixels moved toward the haze, ${r.exact} exact band blends, the near rows untouched, pinned, CPU = AFFINE; the race grid; NEON unchanged)`);
