// Headless SB SPIKE driver (apps/zig/scenes/sb_spike.zig: Suicide Barbie's mix3 on CHISEL
// AFFINE). Boots the cart as docs/ loads it (apps/obj_machine.mjs) and checks:
//   1. the FLIP: every frame exactly one of planes 0 and 1 is on, and they alternate;
//   2. the VIEW: rows 10..189 of the plane on screen are covered (the backdrop fills the
//      view: under 1 % index 0), the letterbox rows 0, 9, 190, 199 are index 0;
//   3. the COUNTS the cart logs every 64 frames: 1x submits 12,147 triangles, draws
//      4,000+, drops none, in 3+ AFFINE ops; keys 2-4 give 6,100 / 4,097 / 3,082 and
//      fewer drawn each time, and the HUD line changes;
//   4. E hides the env meshes (fewer drawn, another picture), P freezes the picture;
//   5. PINS: the view at frame 60 at 1x and at 4x, pixel for pixel (regression pins:
//      the float reference of the conventions is tools/sb_mix3/preview.py).
//   node apps/sb_spike_headless.mjs [<shot dir>] [--break lod|pin]
// --break lod: the LOD keys are not sent; --break pin: one view pixel flips. Each must be
// caught (the run then PASSes, exit 0). With a shot dir: sb_spike_1x.png, sb_spike_4x.png.
import { mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { bootObj, key } from "./obj_machine.mjs";
import { png } from "./skystrike_zig_frame.mjs";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["lod", "pin"].includes(BREAK)) { console.error(`sb_spike: unknown --break ${BREAK}`); process.exit(1); }
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;
if (OUT) await mkdir(OUT, { recursive: true });
const W = 320, H = 200, Y0 = 10, Y1 = 190, REG_FB_BASE = 0x44, OFF_PAL = 0x0100;
const LOD_TRIS = [12147, 6100, 4097, 3082];
// sha256 (16 hex) of rows 10..189 of the plane on screen at frame 60 (dt 1000/60), 1x and 4x
const PINS = { 1: "c91307cd7d172564", 4: "fd7447f636acc24b" };
const errors = [];
const fail = (m) => errors.push(m);

async function boot() {
    const log = [];
    const S = await bootObj("docs/demo-sb_spike.wasm", (s) => log.push(s));
    const shown = () => [0, 1].filter((p) => S.demo.isPlaneEnabled(p));
    const plane = (p) => {
        const vb = S.machine.hwVideoBase(), dv = new DataView(S.memory.buffer, vb, OFF_PAL);
        return new Uint8Array(S.memory.buffer, vb + dv.getUint32(REG_FB_BASE + 4 * p, true), W * H).slice();
    };
    const view = () => plane(shown()[0] ?? 0);
    const counts = () => {
        for (let i = log.length - 1; i >= 0; i--) {
            const m = /lod (\d+) verts (\d+) tris (\d+) near \d+ off \d+ culled \d+ drawn (\d+) dropped (\d+) spans (\d+) pixels (\d+) ops (\d+)/.exec(log[i]);
            if (m) return { lod: +m[1], tris: +m[3], drawn: +m[4], dropped: +m[5], spans: +m[6], ops: +m[8] };
        }
        return null;
    };
    const run = (n) => { for (let i = 0; i < n; i++) S.frame(); };
    return { S, log, shown, view, counts, run };
}
const rowsHash = (px, y0 = Y0, y1 = Y1) => createHash("sha256").update(px.subarray(y0 * W, y1 * W)).digest("hex").slice(0, 16);
const press = (B, ch) => { if (BREAK === "lod" && "234".includes(ch)) return; key(B.S, ch); };

async function shot(B, name) {
    if (!OUT) return;
    const vb = B.S.machine.hwVideoBase(), pal = new Uint32Array(B.S.memory.buffer, vb + OFF_PAL, 256).slice();
    await png(`${OUT}/${name}`, Uint32Array.from(B.view(), (v) => (v ? pal[v] : 0xff000000)), W, H);
}

// 1, 2, 5: the flip, the view, the 1x pin
const A = await boot();
let last = -1;
for (let f = 0; f < 60; f++) {
    A.run(1);
    const on = A.shown();
    if (on.length !== 1) fail(`frame ${f}: planes on ${JSON.stringify(on)} (want exactly one)`);
    else if (f > 0 && on[0] === last) fail(`frame ${f}: plane ${on[0]} shown twice in a row (no flip)`);
    last = on[0];
}
const v1 = A.view();
if (BREAK === "pin") v1[100 * W + 160] ^= 0x40;
const zeros = v1.subarray(Y0 * W, Y1 * W).filter((v) => v === 0).length;
if (zeros > 0.01 * W * (Y1 - Y0)) fail(`view: ${zeros} pixels of index 0 in rows ${Y0}..${Y1 - 1} (the backdrop should cover it)`);
for (const y of [0, 9, 190, 199]) if (v1.subarray(y * W, (y + 1) * W).some((v) => v !== 0)) fail(`letterbox row ${y} is not index 0`);
if (rowsHash(v1) !== PINS[1]) fail(`1x pin: frame 60 view ${rowsHash(v1)} != ${PINS[1]}`);
await shot(A, "sb_spike_1x.png");

// 3: the counts at 1x, then the LOD keys
A.run(80);
const c1 = A.counts();
if (!c1 || c1.lod !== 1 || c1.tris !== LOD_TRIS[0] || c1.drawn < 4000 || c1.dropped !== 0 || c1.ops < 3)
    fail(`1x counts ${JSON.stringify(c1)} (want 12147 submitted, 4000+ drawn, none dropped, 3+ ops)`);
let prev = c1, hud = rowsHash(A.view(), 0, 9);
for (const lod of [2, 3, 4]) {
    press(A, String(lod));
    A.run(70);
    const c = A.counts(), h = rowsHash(A.view(), 0, 9);
    if (!c || c.lod !== lod || c.tris !== LOD_TRIS[lod - 1]) fail(`key ${lod}: counts ${JSON.stringify(c)} (want lod ${lod}, ${LOD_TRIS[lod - 1]} triangles)`);
    else if (prev && c.drawn >= prev.drawn) fail(`key ${lod}: ${c.drawn} drawn, not fewer than ${prev.drawn}`);
    if (h === hud) fail(`key ${lod}: the HUD line did not change`);
    prev = c; hud = h;
}

// 4: E and P (at 4x, as left above)
const before = A.counts(), pic = rowsHash(A.view());
key(A.S, "e");
A.run(70);
const ce = A.counts();
if (!ce || !before || ce.drawn >= before.drawn) fail(`E: drawn ${ce?.drawn} not fewer than ${before?.drawn} (env meshes still drawn)`);
if (rowsHash(A.view()) === pic) fail("E: the picture did not change");
key(A.S, "e");
key(A.S, "p");
A.run(2);
const p0 = rowsHash(A.view());
A.run(3);
if (rowsHash(A.view()) !== p0) fail("P: the picture still moves when paused");

// 5: the 4x pin, from a fresh boot
const B = await boot();
press(B, "4");
B.run(60);
const v4 = B.view();
if (rowsHash(v4) !== PINS[4] && BREAK !== "lod") fail(`4x pin: frame 60 view ${rowsHash(v4)} != ${PINS[4]}`);
await shot(B, "sb_spike_4x.png");

if (BREAK) {
    if (errors.length === 0) { console.error(`sb_spike --break ${BREAK}: NOT caught`); process.exit(1); }
    console.log(`sb_spike --break ${BREAK}: caught (${errors[0]})`);
    process.exit(0);
}
if (errors.length) { for (const e of errors) console.error(`sb_spike: ${e}`); process.exit(1); }
console.log(`sb_spike: PASS (1x ${c1.drawn}/${c1.tris} drawn, ${c1.spans} spans in ${c1.ops} AFFINE ops; LODs 2-4, E, P, pins)`);
