// Headless HMDFAC driver (cart 105): HMD's "HMDFAC" Team Factory tribute, a
// Falcon 030 intro ported from the depacked original. This harness holds the
// cart to its OWN model of the machine, written from the port's documented
// timeline (apps/zig/scenes/hmdfac.zig) and the ripped tables, not from the Zig:
//
//   state   every frame, the three wheel counters, the camera walk ($1356 down
//           to $79e, hold, back up), the queue pair and its index equal the
//           model's 68k-register story
//   model   the composited 800x280 raster equals the model's pixel for pixel,
//           every frame to 1300 then checkpoints to past the text's end:
//           * 199 dark frames: sixteen $0011 registers hide the painted plate,
//           * the 12-frame color0 flash 777/EEE/666/DDD/555/CCC,
//           * 498 cube frames: the frustum projected in the model's own exact
//             68k word maths (Q9 matrix, asr, divs.w overflow rule, add.w
//             wraps) and filled with each face's row stripe, over the FULL
//             art re-blit (so the cart's restore-only-dirty-rows is pinned to
//             give the same picture),
//           * phase 4: the plane cleared, band B, the 9-glyph wave scroller
//             over a FULL clear every frame (pinning the cart's erase-only-
//             the-boxes), the borders open and colour 0 = $011
//   music   hmd_cracoucass.sndh #1 requested once at start
//   keys    Space pops colour 0 to $711 and back; Escape and Back leave
//   soak    no zg.mem allocation refused
//
//   node apps/hmdfac_headless.mjs [outdir]
//   node apps/hmdfac_headless.mjs --break state|pixels|music   (each must FAIL)
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/hmdfac";
const TICK_MS = 20.0;

const BREAKS = ["state", "pixels", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

// ---------------- boot (the ikplus shape) -----------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-hmdfac.wasm");
const env = {
    ...romEnv,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
    hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;

async function startCart() {
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
}
await startCart();
await mkdir(OUT, { recursive: true });
console.log("boot ok");

const errors = [];
const ok = (cond, msg) => {
    console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`);
    if (!cond) errors.push(msg);
};

// ---------------- the rips ---------------------------------------------------
const A = "apps/zig/assets/screens/hmdfac/";
const logo = await readFile(A + "logo.raw"); // 320x249
const bandA = await readFile(A + "band_a.raw"); // 320x46
const bandB = await readFile(A + "band_b.raw"); // 320x51
const font = await readFile(A + "font.bin"); // 64 glyphs, 16 rows of 4 B, MSB left
const text = await readFile(A + "text.raw");
const words = async (f) => { const b = await readFile(A + f); return Array.from({ length: b.length / 2 }, (_, i) => b.readUInt16LE(2 * i)); };
const SINE = await words("sine.blob"), QUEUE = await words("queue.raw"), ROWS = await words("rows.raw"), WAVE = await words("wave.raw");
const BOOT_PAL = await words("boot_pal.raw"), ART_PAL = await words("art_pal.raw"), PAL4 = await words("pal4.raw");
const gun = (n) => ((((n & 7) << 1) | ((n >> 3) & 1)) * 16);
const st = (w) => (0xFF000000 | (gun(w) << 16) | (gun(w >> 4) << 8) | gun(w >> 8)) >>> 0;

const PW = 400, PH = 280, PFB_W = 800;
const AX = 40, AY = 15, AW = 320, AH = 249;
const BOOT_END = 200, FLASH_END = 212, CUBE1_END = 332, CUBE2_END = 582, CUBE_END = 710;
const FLASH_C0 = [0x777, 0xeee, 0x666, 0xddd, 0x555, 0xccc];

// ---------------- the machine's registers, modelled ---------------------------
const M = { frame: 0, ca: 0, cb: 0, cc: 0x80, camera: 0x1356, sy: 0, sx: 0, qi: 0, popped: false };
const adv = (c, s) => { const v = (c + s) & 0xffff; return v > 0x2ce ? 0 : v; };
function step() {
    const f = M.frame;
    if (f >= FLASH_END && f < CUBE_END) {
        if (f < CUBE1_END) { if (M.camera !== 0x79e) { const n = M.camera - 0x28; M.camera = n <= 0x79e ? 0x79e : n; } }
        else if (f >= CUBE2_END) M.camera += 0x28;
        M.ca = adv(M.ca, 4); M.cb = adv(M.cb, 2); M.cc = adv(M.cc, 4);
        M.sy = QUEUE[M.qi * 2]; M.sx = QUEUE[M.qi * 2 + 1];
        M.qi = (M.qi + 1) % 360;
    }
    M.frame++;
}

// 68k word maths. Values reach 2^37, so asr is a floor division, never >>.
const s16 = (v) => { const u = ((v % 65536) + 65536) % 65536; return u >= 32768 ? u - 65536 : u; };
const asr = (v, n) => Math.floor(v / 2 ** n);
const divs = (a, b) => { if (b === 0) return a; const q = Math.trunc(a / b); return q < -32768 || q > 32767 ? a : q; };
const VERTS = [[-136, -136, 120], [-136, 120, 120], [120, 120, 120], [120, -136, 120], [-56, 40, -56], [40, 40, -56], [40, -56, -56], [-56, -56, -56]];
const TRI = [[6, 5, 4], [0, 1, 2], [3, 2, 5], [7, 4, 1], [1, 4, 5]];
const PAT = [15, 2, 13, 14, 7], INK = [14, 6, 13, 9, 8];
function project() {
    const w = (c, o) => s16(SINE[(c >> 1) + o]);
    const coA = w(M.ca, 0), sA = w(M.ca, 360), coB = w(M.cb, 0), sB = w(M.cb, 360), coC = w(M.cc, 0), sC = w(M.cc, 360);
    const t4 = asr(coC * sB, 9), t7 = asr(sC * sB, 9);
    const m = [-sB, asr(coB * sA, 9), asr(coB * coA, 9), asr(coC * coB, 9), asr(t4 * sA, 9) - asr(sC * coA, 9),
        asr(t4 * coA, 9) + asr(sC * sA, 9), asr(sC * coB, 9), asr(t7 * sA, 9) + asr(coC * coA, 9), asr(t7 * coA, 9) - asr(coC * sA, 9)].map(s16);
    return VERTS.map(([x, y, z]) => {
        const depth = s16(-asr(x * m[0] + y * m[1] + z * m[2], 8));
        const dist = s16((M.camera & 0xffff) - depth);
        const sy = divs(x * m[3] + y * m[4] + z * m[5], dist), sx = divs(x * m[6] + y * m[7] + z * m[8], dist);
        return [s16(sy + M.sy), s16(sx + M.sx)];
    });
}

const plane = new Uint8Array(PW * PH);
function paintArt() {
    for (let y = 0; y < AH; y++) for (let x = 0; x < AW; x++) plane[(AY + y) * PW + AX + x] = logo[y * AW + x];
    for (let y = 0; y < 46; y++) for (let x = 0; x < AW; x++) plane[(AY + 194 + y) * PW + AX + x] = bandA[y * AW + x];
}
function drawFaces(p) {
    for (let fi = 4; fi >= 0; fi--) {
        const q = TRI[fi].map((i) => p[i]);
        const cross = (q[2][1] - q[0][1]) * (q[1][0] - q[0][0]) - (q[2][0] - q[0][0]) * (q[1][1] - q[0][1]);
        if (cross >= 0) continue;
        const ylo = Math.max(Math.min(q[0][0], q[1][0], q[2][0]), 0), yhi = Math.min(Math.max(q[0][0], q[1][0], q[2][0]), AH - 1);
        for (let y = ylo; y <= yhi; y++) {
            if (((PAT[fi] >> (y & 3)) & 1) === 0) continue;
            const xs = [];
            for (const [a, b] of [[0, 1], [1, 2], [2, 0]]) {
                const ay = q[a][0], by = q[b][0];
                if (ay !== by && y >= Math.min(ay, by) && y < Math.max(ay, by))
                    xs.push(q[a][1] + Math.trunc((y - ay) * (q[b][1] - q[a][1]) / (by - ay)));
            }
            if (xs.length < 2) continue;
            const x0 = Math.max(Math.min(...xs), 0), x1 = Math.min(Math.max(...xs) + 1, AW);
            for (let x = x0; x < x1; x++) plane[(AY + y) * PW + AX + x] = INK[fi];
        }
    }
}
function drawScroller(t) {
    plane.fill(0);
    for (let y = 0; y < 51; y++) for (let x = 0; x < AW; x++) plane[(AY + 199 + y) * PW + AX + x] = bandB[y * AW + x];
    for (let i = 0; i < 9; i++) {
        const ci = Math.floor(t / 10) + i;
        if (ci >= 2105) break;
        const x0 = i * 40 - 4 * (t % 10);
        if (x0 <= -40 || x0 >= AW) continue;
        let y0 = ROWS[(t + i) % 5040] + ((WAVE[(t + i) % 189] - 100) >> 1);
        if (y0 < -2) y0 = -2;
        const ch = text[ci];
        if (ch < 0x20 || ch >= 0x60) continue;
        for (let py = 0; py < 16; py++)
            for (let px = 0; px < 32; px++) {
                if (!(font[(ch - 0x20) * 64 + py * 4 + (px >> 3)] & (0x80 >> (px & 7)))) continue;
                const x = x0 + px, y = y0 + py;
                if (x >= 0 && x < AW && y >= 0 && y < AH) plane[(AY + y) * PW + AX + x] = 13;
            }
    }
}
function expected() {
    const f = M.frame;
    let pal;
    if (f < BOOT_END) pal = BOOT_PAL.slice();
    else if (f < CUBE_END) { pal = ART_PAL.slice(); pal[0] = f < FLASH_END ? FLASH_C0[(f - BOOT_END) >> 1] : 0xccc; }
    else { pal = PAL4.slice(); pal[0] = M.popped ? 0x711 : 0x011; }
    if (f < CUBE_END) { plane.fill(0); paintArt(); if (f >= FLASH_END) drawFaces(project()); }
    else drawScroller(f - CUBE_END);
    const rgba = pal.map(st);
    const out = new Uint32Array(PFB_W * PH);
    for (let i = 0; i < out.length; i++) out[i] = rgba[plane[((i / PFB_W) | 0) * PW + ((i % PFB_W) >> 1)]];
    return out;
}

const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PFB_W * PH);
const hx = (v) => "0x" + (v >>> 0).toString(16).padStart(8, "0");
function compare(frame) {
    const want = expected();
    if (broke === "pixels" && frame === 400) want[(100 * PFB_W) + 300] ^= 0x10;
    for (let i = 0; i < want.length; i++)
        if (pfb[i] !== want[i]) return `frame ${frame}: physical (${i % PFB_W},${(i / PFB_W) | 0}) is ${hx(pfb[i])} not ${hx(want[i])}`;
    return null;
}
function checkState(frame) {
    const got = [0, 1, 2, 3, 4, 5, 6, 7, 8].map((f) => demo.hmState(f));
    const want = [M.frame, M.ca, M.cb, M.cc, M.camera, M.sy, M.sx, M.qi, M.popped ? 1 : 0];
    if (broke === "state" && frame === 300) want[4]++;
    for (let f = 0; f < 9; f++) if (got[f] !== want[f]) return `state frame ${frame}: word ${f} is ${got[f]}, model ${want[f]}`;
    return null;
}
function ppm(px) {
    const body = Buffer.alloc(PFB_W * PH * 3);
    for (let i = 0; i < px.length; i++) { body[3 * i] = px[i] & 255; body[3 * i + 1] = (px[i] >> 8) & 255; body[3 * i + 2] = (px[i] >> 16) & 255; }
    return Buffer.concat([Buffer.from(`P6\n${PFB_W} ${PH}\n255\n`), body]);
}

// ---------------- 1. music + timeline ---------------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = broke === "music" ? "cracoucass.sndh" : "hmd_cracoucass.sndh";
    ok(pending === 1 && name === want && demo.songTune() === 1,
        pending === 1 ? `music: asked for ${name} #${demo.songTune()} (want ${want} #1)` : "music: no song requested at start");
    const ends = [0, 1, 2, 3, 4].map((i) => demo.hmPhaseEnd(i)).join();
    ok(ends === [BOOT_END, FLASH_END, CUBE1_END, CUBE2_END, CUBE_END].join(), `timeline: phase ends ${ends} (200 dark, 12 flash, 120+250+128 cube)`);
}

// ---------------- 2. state every frame, pixels ------------------------------
const EVERY = 1300;
const CHECK = [2000, 5000, 10000, 15000, 21000, 21800];
const LAST = CHECK[CHECK.length - 1];
let compared = 0, failure = null, camLow = 1e9;
for (let frame = 1; frame <= LAST && !failure; frame++) {
    machine.hwClear();
    step();
    demo.frame(TICK_MS);
    failure = checkState(frame);
    camLow = Math.min(camLow, M.camera);
    if (failure || !(frame <= EVERY || CHECK.includes(frame))) continue;
    machine.hwRenderPlane(0);
    failure = compare(frame);
    compared++;
    if ([100, 205, 213, 400, 600, 709, 711, 1000].includes(frame)) await writeFile(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, ppm(pfb));
}
if (failure) errors.push(failure);
else {
    ok(compared === EVERY + CHECK.length, `${compared} frames equal the model pixel for pixel (every frame to ${EVERY}: boot, flash, all 498 cube frames, phase 4; then ${CHECK.join("/")})`);
    ok(camLow === 0x79e && M.camera === 0x1b9e, `camera: $1356 walks down to $${camLow.toString(16)}, holds, and phase 3 climbs to $${M.camera.toString(16)} (the dis: $79e, $1b9e)`);
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");

    // ---------------- 3. keys -----------------------------------------------
    demo.key(32);
    demo.frame(TICK_MS);
    machine.hwRenderPlane(0);
    const popped = demo.hmState(8) === 1 && pfb[0] === st(0x711);
    demo.key(32);
    demo.frame(TICK_MS);
    machine.hwRenderPlane(0);
    ok(popped && demo.hmState(8) === 0 && pfb[0] === st(0x011), "keys: Space pops colour 0 (the border) to $711 and back to $011");
    demo.key(0xE012);
    demo.frame(TICK_MS);
    ok(demo.pollCartRequest() === -1, "keys: Escape hands the screen back (pollCartRequest -1)");
    await startCart();
    demo.input(6);
    demo.frame(TICK_MS);
    ok(demo.pollCartRequest() === -1, "keys: Back hands the screen back (pollCartRequest -1)");
}

if (broke) {
    console.log(errors.length ? `hmdfac: PASS (--break ${broke} caught: ${errors[0]})` : `hmdfac: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `hmdfac: FAILED -- ${errors.join("; ")}` : "hmdfac: all pass");
process.exit(errors.length ? 1 : 0);
