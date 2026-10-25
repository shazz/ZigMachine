// Headless HMDFAC driver (cart 105): Hemoroids' "Factory Cracktro" (HMDFAC.PRG),
// a Team Factory tribute for the Atari STe, ported from the original. This
// harness holds the cart to its OWN model of the machine (apps/hmdfac_model.mjs,
// written from the 68000 code and the RAM rips, not from the Zig), and holds
// that model to the ORIGINAL (apps/hmdfac_original.json, pages the original drew
// in Hatari):
//
//   original  at four cube frames across the three phases, the model's wheel
//             words equal the original's, and the page the model draws (logo,
//             band A, the solid six-face frustum by the $1047e edge walk and
//             $bc08 span fill) hashes to the page the original drew
//   state     every frame, the wheel counters, the camera walk ($1356 down to
//             $79e, hold, back up), the queue pair and index, and the opening's
//             screen offset (the $2d1ea bob words / 160) equal the model's
//   model     the composited 800x280 raster equals the model's pixel for pixel,
//             every frame to 1300 then checkpoints past the text's end: the
//             bobbing logo (193 frames), the 777/EEE/666/DDD/555/CCC flash and
//             4 grey frames, the 498 cube frames over a FULL art re-blit (so the
//             cart's dirty-row restore is pinned), phase 4's stand-in scroller
//             over a FULL clear; on every line the Timer B chain's palettes
//             (bottom palette to line 17, top from 18, bottom from 212) and the
//             two laser lines' 12-pixel colour-0 writes
//   music     hmd_cracoucass.sndh #1 requested once at start
//   keys      Space pops colour 0 to $711 over lines 0..17 and back; Escape and
//             Back leave
//   soak      no zg.mem allocation refused
//
//   node apps/hmdfac_headless.mjs [outdir]
//   node apps/hmdfac_headless.mjs --break state|pixels|music|original   (each must FAIL)
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam } from "../docs/wasm_hiwater.js";
import * as H from "./hmdfac_model.mjs";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/hmdfac";
const TICK_MS = 20.0;

const BREAKS = ["state", "pixels", "music", "original"];
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

// ---------------- the model's registers ----------------------------------------
const M = { frame: 0, ca: 0, cb: 0, cc: 0x80, camera: 0x1356, qx: 0, qy: 0, qi: 0, popped: false };
const T = { l: new Array(200).fill(0), r: new Array(200).fill(0) }; // $56a1a / $56ecc persist
const adv = (c, s) => { const v = (c + s) & 0xffff; return v > 0x2ce ? 0 : v; };
function step() {
    const f = M.frame;
    if (f >= H.HOLD_END && f < H.CUBE_END) {
        if (f < H.CUBE1_END) { if (M.camera !== 0x79e) { const n = M.camera - 0x28; M.camera = n <= 0x79e ? 0x79e : n; } }
        else if (f >= H.CUBE2_END) M.camera += 0x28;
        M.ca = adv(M.ca, 4); M.cb = adv(M.cb, 2); M.cc = adv(M.cc, 4);
        M.qx = H.R.QUEUE[M.qi * 2]; M.qy = H.R.QUEUE[M.qi * 2 + 1];
        M.qi = (M.qi + 1) % 360;
    }
    M.frame++;
}
/// The plate page of the frame just stepped (the cube's tables run every cube frame).
function page() {
    const f = M.frame - 1;
    if (f < H.HOLD_END) return H.artPage(false);
    if (f < H.CUBE_END) { const p = H.artPage(true); H.drawCube(p, H.project(M), T); return p; }
    return H.scrollerPage(f < H.P4_START ? -1 : f - H.P4_START);
}

const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), 800 * 280);
const hx = (v) => "0x" + (v >>> 0).toString(16).padStart(8, "0");
function compare(frame, pg) {
    const want = H.composite(pg, { f: frame - 1, popped: M.popped });
    if (broke === "pixels" && frame === 400) want[(100 * 800) + 300] ^= 0x10;
    for (let i = 0; i < want.length; i++)
        if (pfb[i] !== want[i]) return `frame ${frame}: physical (${i % 800},${(i / 800) | 0}) is ${hx(pfb[i])} not ${hx(want[i])}`;
    return null;
}
function checkState(frame) {
    const got = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((f) => demo.hmState(f));
    const want = [M.frame, M.ca, M.cb, M.cc, M.camera, M.qx, M.qy, M.qi, M.popped ? 1 : 0, H.bobLines(M.frame - 1)];
    if (broke === "state" && frame === 300) want[4]++;
    for (let f = 0; f < want.length; f++) if (got[f] !== want[f]) return `state frame ${frame}: word ${f} is ${got[f]}, model ${want[f]}`;
    return null;
}
function ppm(px) {
    const body = Buffer.alloc(800 * 280 * 3);
    for (let i = 0; i < px.length; i++) { body[3 * i] = px[i] & 255; body[3 * i + 1] = (px[i] >> 8) & 255; body[3 * i + 2] = (px[i] >> 16) & 255; }
    return Buffer.concat([Buffer.from(`P6\n800 280\n255\n`), body]);
}

// ---------------- 1. music + timeline ---------------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = broke === "music" ? "cracoucass.sndh" : "hmd_cracoucass.sndh";
    ok(pending === 1 && name === want && demo.songTune() === 1,
        pending === 1 ? `music: asked for ${name} #${demo.songTune()} (want ${want} #1)` : "music: no song requested at start");
    const ends = [0, 1, 2, 3, 4, 5, 6].map((i) => demo.hmPhaseEnd(i)).join();
    const model = [H.OPEN_END, H.FLASH_END, H.HOLD_END, H.CUBE1_END, H.CUBE2_END, H.CUBE_END, H.P4_START].join();
    ok(ends === model, `timeline: phase ends ${ends} (193 bob, 12 flash, 4 grey, 120+250+128 cube, 17 precalc)`);
    const fm = (await readFile("apps/zig/assets/screens/hmdfac/font_machine.bin")).length;
    ok(fm === 50 * 64, `provenance rip: font_machine.bin ${fm} B (50 glyphs x 64)`);
}

// ---------------- 2. state every frame, pixels, the original's pages ------------
const PINS = JSON.parse(await readFile("apps/hmdfac_original.json", "utf8")).cube;
if (broke === "original") PINS[1].fnv = "0x00000000";
const EVERY = 1300;
const CHECK = [2000, 5000, 10000, 15000, 21000, 21800];
const LAST = CHECK[CHECK.length - 1];
let compared = 0, failure = null, camLow = 1e9, pinned = 0;
for (let frame = 1; frame <= LAST && !failure; frame++) {
    machine.hwClear();
    step();
    demo.frame(TICK_MS);
    failure = checkState(frame);
    camLow = Math.min(camLow, M.camera);
    const f = frame - 1, inCube = f >= H.HOLD_END && f < H.CUBE_END;
    if (failure || !(frame <= EVERY || CHECK.includes(frame) || inCube)) continue;
    const pg = page();
    const pin = PINS.find((p) => p.cube_frame === f - H.HOLD_END);
    if (pin) {
        const w = [M.ca, M.cb, M.cc, M.camera, M.qx, M.qy].join(), h = H.fnv(pg);
        if (w !== pin.wheel.join() || h !== pin.fnv) failure = `original: cube frame ${pin.cube_frame} wheel ${w} page ${h}, the original drew ${pin.wheel.join()} page ${pin.fnv}`;
        else pinned++;
    }
    if (failure || !(frame <= EVERY || CHECK.includes(frame))) continue;
    machine.hwRenderPlane(0);
    failure = compare(frame, pg);
    compared++;
    if ([20, 100, 200, 215, 400, 600, 708, 724, 1000].includes(frame)) await writeFile(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, ppm(pfb));
}
if (failure) errors.push(failure);
else {
    ok(pinned === PINS.length, `original: ${pinned} of ${PINS.length} cube pages the original drew are the model's (wheel words + page hash)`);
    ok(compared === EVERY + CHECK.length, `${compared} frames equal the model pixel for pixel (every frame to ${EVERY}: bob, flash, all 498 cube frames, phase 4; then ${CHECK.join("/")})`);
    ok(camLow === 0x79e && M.camera === 0x1b9e, `camera: $1356 walks down to $${camLow.toString(16)}, holds, and phase 3 climbs to $${M.camera.toString(16)} (the dis: $79e, $1b9e)`);
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");

    // ---------------- 3. keys -----------------------------------------------
    demo.key(32);
    step(); M.popped = true;
    demo.frame(TICK_MS);
    machine.hwRenderPlane(0);
    const popped = demo.hmState(8) === 1 && pfb[0] === H.st(0x711) && pfb[20 * 800] === H.st(0x011);
    demo.key(32);
    step(); M.popped = false;
    demo.frame(TICK_MS);
    machine.hwRenderPlane(0);
    ok(popped && demo.hmState(8) === 0 && pfb[0] === H.st(0x011), "keys: Space pops colour 0 to $711 over the top lines (line 20 stays $011) and back");
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
