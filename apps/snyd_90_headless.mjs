// Headless SWEDISH NEW YEAR DEMO 89-90 driver (apps/zig/scenes/snyd_90.zig):
// boots the sealed machine + the cart as docs/sealed-loader.js does and plays
// the key path -- intro, Space, the menu for 1200 VBLs (through a full slide
// and the swap to the SYNC letters), F2 for 1500 VBLs, Space back to a fresh
// menu, the same for F1, then the best-effort parts F3..F6 (checked for motion,
// look and borders: apps/snyd_90_parts.mjs), Escape.
// Every shot is checked against the REAL demo: SHA-256 prefixes from
// prototypes/snyd90_re/snyd90_expect.py --
//   intro    the Spectrum 512 picture as decoded by spu.py, which matches a
//            Hatari capture of the running intro pixel for pixel;
//   menu-J   the screen the menu's J-th iteration drew, from menu_model.py,
//            which reproduces Hatari's RAM byte for byte (and so does the Zig:
//            apps/zig/scenes/snyd_90/menu_test.zig);
//   f2-J,    what F2 / F1 show during VBL J: the original code run on the
//   f1-J     Musashi oracle (prototypes/snyd90_re/m68run), which matches
//            Hatari's RAM of the real parts (f2_test.zig / f1_test.zig check
//            the Zig on it).
// Per shot: the window's palette indices, and the whole physical 400x280 frame
// in RGB (the colours come from the plane's HBL, line by line: 48 registers a
// line in the intro; the borders are colour 0 from the global HBL).
// Then: the song requests (snyd90.sndh #4 in the intro, #1 in the menu,
// snyd90_f2.sndh #1 in F2, the archive's Overlander.sndh #1 in F1), each
// tune plays on the sealed YM, Escape asks for the menu disk, the frame cost.
//
//   node apps/snyd_90_headless.mjs [outdir] [--break hbl|step|tune|f3..f6]
//     hbl   the plane's HBL is not called during a shot: the colours fail
//     step  the cart runs one VBL the reference does not: the menu/F2 shots fail
//     tune  a wrong subtune is reported: the music check fails
//     fN    part fN gets no host time (it never runs a VBL): its checks fail
import { writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { boot, tuneFault, PW, PH } from "./snyd_90_machine.mjs";
import { EXPECT } from "./snyd_90_expect.mjs";
import { PARTS, LOOK, look, borders } from "./snyd_90_parts.mjs";

const VBL = 20; // the parts run at the ST's 50 Hz: one VBL a 20 ms frame
const K = { space: 32, esc: 0xe012, f: (n) => 0xe000 + n };
const SONGS = [["snyd90.sndh", 4], ["snyd90.sndh", 1], ["snyd90_f2.sndh", 1], ["snyd90.sndh", 1],
    ["Overlander.sndh", 1], ["snyd90.sndh", 1], ["snyd90_f3.sndh", 4], ["snyd90.sndh", 1],
    ["Noisy_Pillars.sndh", 1], ["snyd90.sndh", 1]];

const argv = process.argv.slice(2);
const bi = argv.indexOf("--break");
const brk = bi < 0 ? null : argv.splice(bi, 2)[1];
const BREAKS = ["hbl", "step", "tune", ...PARTS.map((p) => p.name)];
if (brk && !BREAKS.includes(brk)) throw new Error(`--break takes ${BREAKS.join(", ")}, not ${brk}`);
const outdir = argv[0] || "/tmp/snyd_90";
await mkdir(outdir, { recursive: true });
const errors = [];
const fail = (msg) => { errors.push(msg); console.log(`  FAIL ${msg}`); };
const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);
const dec = new TextDecoder();

const m = await boot();
const got = [];
let frames = 0;
const cost = { intro: [0, 0], menu: [0, 0], f1: [0, 0], f2: [0, 0] };
for (const p of PARTS) cost[p.name] = [0, 0];

function frame(part, dt = VBL) {
    const t = performance.now();
    m.machine.hwClear();
    m.demo.frame(dt);
    m.machine.hwRenderPlane(0);
    cost[part][0] += performance.now() - t;
    cost[part][1]++;
    if (m.demo.pollSongRequest()) {
        got.push([dec.decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())), m.demo.songTune()]);
    }
    frames++;
}

/// The shot just rendered: window indices, physical frame (also written out).
async function capture(name) {
    m.setMute(brk === "hbl");
    m.machine.hwRenderPlane(0);
    m.setMute(false);
    const plane = m.plane();
    const win = new Uint8Array(320 * 200);
    for (let y = 0; y < 200; y++) win.set(plane.subarray((y + 40) * PW + 40, (y + 40) * PW + 360), y * 320);
    const pw = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * m.machine.hwPhysHeight() * 4);
    const rgb = Buffer.alloc(PW * PH * 3);
    for (let y = 0; y < PH; y++) for (let x = 0; x < PW; x++) rgb.set(pfb.subarray((y * pw + 2 * x) * 4, (y * pw + 2 * x) * 4 + 3), (y * PW + x) * 3);
    await writeFile(`${outdir}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${PW} ${PH}\n255\n`), rgb]));
    return { win, rgb };
}

/// The shot just rendered against the original: window indices, physical frame.
async function shot(name) {
    const { win, rgb } = await capture(name);
    const have = [sha(win), sha(rgb)];
    const what = ["the screen (window indices)", "the physical frame (colours per line, borders)"];
    let ok = true;
    for (let k = 0; k < 2; k++) {
        if (have[k] === EXPECT[name][k]) continue;
        ok = false;
        fail(`${name}: ${what[k]} ${have[k]}, the original's ${EXPECT[name][k]}`);
    }
    console.log(`  ${name}: frame ${frames}${ok ? " -- the original's screen and colours" : ""}`);
}

// ------------------------------------------------------------------ the tour
const t0 = performance.now();
frame("intro");
await shot("intro");
for (let i = 0; i < 49; i++) frame("intro");
await shot("intro"); // a still picture: unchanged 50 VBLs on
m.demo.key(K.space);
const MENU_SHOTS = [1, 2, 100, 531, 1000, 1200];
for (let j = 1; j <= 1200; j++) {
    const isShot = MENU_SHOTS.includes(j);
    if (isShot && brk === "step") m.demo.frame(VBL);
    frame("menu");
    if (isShot) await shot(`menu-${String(j).padStart(4, "0")}`);
}
// A part from the menu: the shot after its VBL J shows (one host frame later:
// a capture is presented at the start of the next frame) what the original
// shows during VBL J. Then Space: back to the menu, read afresh.
async function part(fkey, name, shots) {
    m.demo.key(K.f(fkey));
    const last = Math.max(...shots);
    for (let j = 1; j <= last + 1; j++) {
        const isShot = shots.includes(j - 1);
        if (isShot && brk === "step") m.demo.frame(VBL);
        frame(name);
        if (isShot) await shot(`${name}-${String(j - 1).padStart(4, "0")}`);
    }
    m.demo.key(K.space);
    frame("menu");
    await shot("menu-0001"); // its first iteration again
}
await part(2, "f2", [1, 2, 3, 51, 194, 701, 1501]);
await part(1, "f1", [1, 2, 300, 701, 1501]);
// A best-effort part: it moves, it looks like Hatari's capture of the real
// one, its borders are open where the original opens them. Then Space.
async function bestEffort(p) {
    m.demo.key(K.f(p.key));
    const seen = [];
    for (let j = 1; j <= p.frames + 1; j++) {
        frame(p.name, brk === p.name ? 0 : VBL);
        if (!p.shots.includes(j - 1)) continue;
        const name = `${p.name}-${String(j - 1).padStart(4, "0")}`;
        const { win, rgb } = await capture(name);
        seen.push(sha(win));
        const sim = look(p.name, rgb, PW);
        const why = borders(p.open, rgb, PW);
        if (sim < LOOK) fail(`${name}: colours ${sim.toFixed(3)} like Hatari's capture of the original, want >= ${LOOK}`);
        if (why) fail(`${name}: ${why}`);
        console.log(`  ${name}: frame ${frames}, colours ${sim.toFixed(3)} like the original's${why ? "" : `, borders as the original (${p.open})`}`);
    }
    if (new Set(seen).size !== seen.length) fail(`${p.name}: the screen does not move (${seen.join(" ")})`);
    m.demo.key(K.space);
    frame("menu");
    await shot("menu-0001");
}
for (const p of PARTS) await bestEffort(p);
const ms = (performance.now() - t0) / frames;

// ------------------------------------------------------------------ music
if (brk === "tune") got[1] = ["snyd90.sndh", 2];
if (JSON.stringify(got) !== JSON.stringify(SONGS)) fail(`song requests ${JSON.stringify(got)}, want ${JSON.stringify(SONGS)}`);
else console.log(`  music: ${got.map((g) => g.join(" #")).join(", then ")}`);
for (const [file, sub] of SONGS) {
    const out = {};
    const why = await tuneFault(file, sub, out);
    if (why) fail(why);
    else console.log(`    ${file} #${sub} plays through the sealed YM (peak ${out.peak.toFixed(3)})`);
}

// ------------------------------------------------------------------ leaving + cost
if (m.machine.hwRamAllocFailures()) fail(`${m.machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
m.demo.key(K.esc);
if (m.demo.pollCartRequest() !== -1) fail("Escape does not ask for the menu disk");
console.log(`  cart frame cost (update + render + composite): intro ${(cost.intro[0] / cost.intro[1]).toFixed(3)} ms, menu ${(cost.menu[0] / cost.menu[1]).toFixed(3)} ms, F1 ${(cost.f1[0] / cost.f1[1]).toFixed(3)} ms, F2 ${(cost.f2[0] / cost.f2[1]).toFixed(3)} ms, ${PARTS.map((p) => `${p.name.toUpperCase()} ${(cost[p.name][0] / cost[p.name][1]).toFixed(3)} ms`).join(", ")}; ${frames} frames, ${ms.toFixed(2)} ms/frame with the checks`);

if (brk) {
    console.log(errors.length ? `snyd_90: PASS (--break ${brk} caught: ${errors.length} failures)` : `snyd_90: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `snyd_90: FAILED (${errors.length})` : "snyd_90: all pass");
process.exit(errors.length ? 1 : 0);
