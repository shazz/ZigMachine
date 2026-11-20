// Headless check of RAYTRACE's keys 4 and 5: NUCLEUS's GfA Punch Raytrace (ST Magazine),
// apps/zig/scenes/raytrace/gfa*.zig. No host clock (env.hostMicros left to the stub), so a
// frame does a fixed 512 items and every frame count below is exact.
//
// Key 4, GFA PUNCH (ST MAGAZINE), the 16-colour plane (plane 1):
//   1. it draws PROGRESSIVELY, bottom row first as the listing's loops do: frame 1 has only
//      the bottom rows, the drawn rows only grow, the LINE read-out climbs, and the picture
//      is complete at exactly frame ceil(319*153 / 512) = 96; then nothing changes;
//   2. the title is PRINTed at the top in colour 15, exactly the system font's pixels;
//   3. the picture is the LISTING's: every pixel's colour index against an independent
//      JavaScript run of the 21 lines (apps/gfa_punch_lib.mjs, f64, same RAND stream);
//      measured: all 48,807 equal; the cart's f32 may still move a pixel by one level
//      at a threshold, so up to 50 pixels one level apart pass;
//   4. pinned (SHA-256 of rows 0..198).
// Key 5, GFA PUNCH, KESTREL (the true-colour plane 0):
//   5. coarse to fine: frame 2 is the 8x8-block preview; the first picture at exactly frame
//      320*160/512 = 100, pass 16 at 1600, then nothing changes;
//   6. the same scene: its 8x8-block brightness follows the listing's (the JS run), and
//      refinement smooths it (fewer distinct steps on the sphere's edge);
//   7. both pictures pinned.
// Keys: 4 -> 5 -> 1 and Fire restart the run in the right plane.
//
//   node apps/gfa_punch_headless.mjs [outdir]       outdir gets PPMs (finished + mid-way)
//   node apps/gfa_punch_headless.mjs --break true   the oracle with TRUE = +1 (GFA's TRUE is
//       -1: the floor text and the shadow SUBTRACT); the pictures must then disagree.
import { mkdir, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import * as R from "./raytrace_lib.mjs";
import * as G from "./gfa_punch_lib.mjs";

const W = 320, H = 200;
const PINNED = {
    st: "7f4d77e5dbd71ed081d47c3c9a76aef783af1ab96d8bb31b5d095ec9030359a7",
    first: "95241d6d6ac9c78828c4ab0766d2f255d7bfa8f3caf944cff357f56bae0cbfbb",
    conv: "97ee29bccf4f1968c74dbfec39aa631661df0e6f2631de84e7367089dea63c06",
};
const ST_FRAMES = Math.ceil((319 * 153) / 512), TC_FIRST = (320 * 160) / 512, TC_CONV = 16 * TC_FIRST;
const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/gfa_punch";
const errors = [];
const check = (ok, m) => { if (!ok) { errors.push(m); console.log(`  FAIL ${m}`); } };

function frame(m) {
    m.machine.hwClear();
    m.demo.frame(16.6);
    const p = m.demo.isPlaneEnabled(1) ? 1 : 0;
    m.machine.hwRenderPlane(p);
    const pw = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * m.machine.hwPhysHeight() * 4);
    const rgb = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const s = ((40 + y) * pw + 80 + x * 2) * 4, d = (y * W + x) * 3;
        rgb[d] = pfb[s]; rgb[d + 1] = pfb[s + 1]; rgb[d + 2] = pfb[s + 2];
    }
    return { rgb, plane: p };
}
const px = (rgb, x, y) => { const i = (y * W + x) * 3; return [rgb[i], rgb[i + 1], rgb[i + 2]]; };
const bits = (rgb, x0, n) => { let v = 0; for (let i = 0; i < n; i++) v = v * 2 + (px(rgb, x0 + i, 199)[0] > 30 ? 1 : 0); return v; };
const tap = (rgb) => ({ frames: bits(rgb, 0, 16), done: bits(rgb, 16, 1), pass: bits(rgb, 17, 6), ms: bits(rgb, 23, 24), key: bits(rgb, 47, 3) });
const sha = (rgb) => createHash("sha256").update(rgb.subarray(0, W * 199 * 3)).digest("hex");
const ppm = (rgb) => Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), rgb]);
const PAL = G.PALETTE.map(G.stRgb);
const index = (rgb, x, y) => { const p = px(rgb, x, y); return PAL.findIndex((c) => c.every((v, i) => v === p[i])); };
const luma = (p) => p[0] * 0.3 + p[1] * 0.59 + p[2] * 0.11;
const isHud = (y) => (y >= 16 && y < 40) || y === 199;

const oracle = G.run(G.screenWithTitle(), brk === "true" ? 1 : -1).map((c) => c & 15);
const oracleRgb = G.toRgb(oracle);

async function keyFour(m) {
    console.log("key 4, GFA PUNCH (ST MAGAZINE):");
    m.demo.setShadeMode(3);
    let r, t, lastRows = 0, mid = null, doneAt = 0;
    for (let f = 1; f <= 200 && !doneAt; f++) {
        r = frame(m); t = tap(r.rgb);
        check(r.plane === 1 && t.key === 4, `key 4: plane ${r.plane}, tap key ${t.key} at frame ${f}`);
        let rows = 0; // rows from the bottom (198) up that hold anything
        for (let y = 198; y >= 46; y--) { let any = false; for (let x = 0; x < 319; x++) any ||= index(r.rgb, x, y) !== 0; if (any) rows = 199 - y; }
        if (f === 1) check(rows > 0 && rows < 10, `key 4: frame 1 should hold only the bottom rows (${rows})`);
        check(rows >= lastRows, `key 4: drawn rows fell at frame ${f}`);
        lastRows = rows;
        if (f === ST_FRAMES >> 1) mid = r.rgb;
        if (t.done) doneAt = f;
    }
    check(doneAt === ST_FRAMES, `key 4: finished at frame ${doneAt}, expected ${ST_FRAMES}`);
    check(t.frames === doneAt, `key 4: frame counter ${t.frames}`);
    check(sha(frame(m).rgb) === sha(r.rgb), "key 4: the picture changed after it was finished");
    const title = G.screenWithTitle();
    let titleBad = 0, diff = 0, worst = 0;
    for (let y = 0; y < 199; y++) for (let x = 0; x < W; x++) {
        if (isHud(y)) continue;
        const c = index(r.rgb, x, y);
        if (y < 8) titleBad += c !== title[y * W + x];
        const d = Math.abs(c - oracle[y * W + x]);
        if (d) diff++;
        worst = Math.max(worst, c < 0 ? 99 : d);
    }
    check(titleBad === 0, `key 4: ${titleBad} title pixels differ from the system font's`);
    console.log(`  finished at frame ${doneAt}; against the listing (JS f64): ${diff} pixels differ, worst by ${worst} levels`);
    check(diff <= 50 && worst <= 1, `key 4: ${diff} pixels differ from the listing's picture (worst ${worst} levels)`);
    return { done: r.rgb, mid };
}

// The mean brightness of each 8x8 block of the scene (rows 40..198, the HUD rows apart).
function blocks(rgb) {
    const out = [];
    for (let by = 40; by + 8 <= 199; by += 8) for (let bx = 0; bx < 312; bx += 8) {
        let s = 0;
        for (let y = by; y < by + 8; y++) for (let x = bx; x < bx + 8; x++) s += luma(px(rgb, x, y));
        out.push(s / 64);
    }
    return out;
}

// Fraction of the window's 8x8 cells (rows 40..191) whose corners are within the 565 dither.
function blocky(rgb) {
    let flat = 0, n = 0;
    for (let by = 40; by < 192; by += 8) for (let bx = 0; bx < W; bx += 8) {
        const a = px(rgb, bx, by), b = px(rgb, bx + 7, by + 7);
        n++; if (a.every((v, i) => Math.abs(v - b[i]) <= 12)) flat++;
    }
    return flat / n;
}

async function keyFive(m) {
    console.log("key 5, GFA PUNCH, KESTREL:");
    m.demo.setShadeMode(4);
    let r, t, first = null, mid = null, convAt = 0, lastPass = 0;
    for (let f = 1; f <= TC_CONV + 10 && !convAt; f++) {
        r = frame(m); t = tap(r.rgb);
        check(r.plane === 0 && t.key === 5, `key 5: plane ${r.plane}, tap key ${t.key} at frame ${f}`);
        if (f === 2) check(blocky(r.rgb) > 0.9, `key 5: frame 2 should be the 8x8-block preview (${blocky(r.rgb).toFixed(2)})`);
        if (f === TC_FIRST >> 1) mid = r.rgb;
        check(t.pass === lastPass || t.pass === lastPass + 1, `key 5: pass ${lastPass} -> ${t.pass} at frame ${f}`);
        if (t.pass === 1 && lastPass === 0) { first = r.rgb; check(f === TC_FIRST, `key 5: first picture at frame ${f}, expected ${TC_FIRST}`); }
        lastPass = t.pass;
        if (t.done) convAt = f;
    }
    check(convAt === TC_CONV, `key 5: converged at frame ${convAt}, expected ${TC_CONV}`);
    check(sha(frame(m).rgb) === sha(r.rgb), "key 5: the picture changed after the last pass");
    const a = blocks(r.rgb), b = blocks(oracleRgb);
    const err = a.reduce((s, v, i) => s + Math.abs(v - b[i]), 0) / a.length;
    console.log(`  first picture at ${TC_FIRST}, converged at ${convAt}; 8x8 brightness against the listing's: mean error ${err.toFixed(2)}`);
    check(err < 4, `key 5: the scene's brightness drifts from the listing's (mean block error ${err.toFixed(2)})`);
    let changed = 0;
    for (let i = 0; i < W * 199 * 3; i++) changed += first[i] !== r.rgb[i];
    check(changed > W * 199 * 0.3, `key 5: refinement changed only ${changed} channel values`);
    return { first, done: r.rgb, mid };
}

function keys(m) {
    for (const [what, act, key] of [["Fire", () => m.demo.input(5), 5], ["key 4", () => m.demo.setShadeMode(3), 4]]) {
        act();
        const t = tap(frame(m).rgb);
        check(t.frames === 1 && !t.done && t.key === key, `${what} did not restart (frames ${t.frames}, key ${t.key})`);
    }
    m.demo.setShadeMode(0);
    const r = frame(m);
    check(r.plane === 0 && R.readTap(r.rgb).frames === 1, "key 1 after key 4 did not bring the fixed-point mode back on plane 0");
}

await mkdir(outdir, { recursive: true });
const m = await R.boot("demo-raytrace", null);
const st = await keyFour(m);
const tc = await keyFive(m);
keys(m);
const hashes = { st: sha(st.done), first: sha(tc.first), conv: sha(tc.done) };
console.log(`fingerprints ${Object.entries(hashes).map(([k, v]) => `${k} ${v}`).join(" ")}`);
for (const k of Object.keys(PINNED)) check(hashes[k] === PINNED[k], `${k} fingerprint ${hashes[k].slice(0, 16)} != pinned ${PINNED[k].slice(0, 16)}`);
if (!brk) {
    for (const [n, rgb] of [["st-done", st.done], ["st-mid", st.mid], ["kestrel-first", tc.first], ["kestrel-mid", tc.mid], ["kestrel-done", tc.done], ["listing-js", oracleRgb]])
        await writeFile(`${outdir}/gfa-${n}.ppm`, ppm(rgb));
}
if (brk) {
    console.log(errors.length ? `gfa_punch: PASS (--break ${brk} caught: ${errors.length} failures)` : `gfa_punch: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
if (errors.length) { console.log(`${errors.length} FAILURE(S)`); process.exit(1); }
console.log("gfa_punch: OK");
