// Headless ULM 3615 GEN4 driver — boots the sealed machine + demo-gen4_3615.wasm
// the way docs/sealed-loader.js does and checks it against screen.js REPLAYED
// (apps/gen4_3615_replay.mjs, written from the source and matched to the page
// run in Chrome: 3 pixels of ten 384x270 reference frames differ).
//
//   1. frames: at ten go() counts, from the first frame through the FATE
//      logo's appearance (2480) and all six of its waveforms, every pixel of the
//      whole 400x280 plane is the replay's (borders black where it draws nothing).
//      The YM volume registers are driven with a known sequence, so the VU
//      meters are replayed too.
//   2. rasters: the sky, the VU colours and the floor shading are colour
//      registers changed per line, not pixels: the index framebuffer holds one
//      index for each, and the HBL installs that index's colour line by line.
//   3. borders: the art reaches the side borders and the bottom border.
//   4. music: the cart asks for 3615_gen4_demo.sndh, which is in docs/music/
//      and plays through the sealed YM (FLAG ~y).
//
//   node apps/gen4_3615_headless.mjs [outdir] [--break sky|floor|fate|ulm|vu|raster]
// --break sabotages the replay (or, for raster, the expected table) and passes
// only if a check notices.
import { readFile, writeFile, mkdir, access } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { Replay, loadAssets, W, H, ulmDistTable, mocheDistTable } from "./gen4_3615_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // SHARED_PAGES / AUDIO_PAGES in machine/sdk
const OFF_PAL = 0x0100, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44; // memmap.zig
const MAGIC_X = 40, HBL_PLANE_ID = 0; // OVERSCAN_MAGIC_X, plane 0's handler
const CANVAS_X = 8, CANVAS_Y = 10; // the scene's placement of the 384x270 canvas
const VU_INK = 64, SKY_INK = 65, CHECK_DARK = 66, CHECK_LIGHT = 67; // gen4_3615/assets.zig
const WANT_MUSIC = "3615_gen4_demo.sndh";
const FRAMES = [1, 2, 60, 700, 2600, 7000, 10500, 15000, 22000, 30000];
const VOL = (k, n) => ((n * (k + 3)) >> 3) % 16; // a register sequence for the meters

const args = process.argv.slice(2);
const broke = args.includes("--break") ? args[args.indexOf("--break") + 1] : "";
const out = args.find((a, i) => !a.startsWith("--") && args[i - 1] !== "--break") || "/tmp/gen4_3615";
let failures = 0;
function check(name, got, want) {
    const ok = got === want;
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}: got ${got}, want ${want}`);
}

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

/// ~5 s of the tune on the sealed audio machine (as replicants_emlyn_headless).
async function sndhPlay(name) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { peak: 0, unhandled: ["audioLoadSndh refused it"] };
    audio.audioSndhPlay(0);
    let peak = 0;
    for (let b = 0; b < 250; b++) {
        audio.audioRender(882);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 882)) peak = Math.max(peak, Math.abs(v));
    }
    const unhandled = [];
    for (let i = 0; i < Math.min(8, audio.audioUnhandledCount()); i++) unhandled.push("$" + audio.audioUnhandled(i).toString(16).toUpperCase());
    return { peak, unhandled };
}

const { memory, machine, demo } = await boot("docs/demo-gen4_3615.wasm");
const PW = machine.hwPhysWidth(), PH = machine.hwPhysHeight(); // 800 (x doubled), 280
const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), PW * PH * 4);
const VB = machine.hwVideoBase();
const regs = new DataView(memory.buffer, VB, OFF_PAL);
const palette = () => new Uint32Array(memory.buffer, VB + OFF_PAL, 256);
const indices = () => new Uint8Array(memory.buffer, VB + regs.getUint32(REG_FB_BASE, true), regs.getUint16(REG_FB_STRIDE, true) * PH);
const ym = new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 16);
let frames = 0;

function run(n) {
    for (let i = 0; i < n; i++) {
        frames++;
        for (let k = 1; k <= 3; k++) ym[7 + k] = VOL(k, frames);
        machine.hwClear();
        demo.frame(16.6);
        machine.hwRenderPlane(0);
    }
}

/// The plane as 400x280 RGB over the black background.
function shot() {
    const rgb = new Uint8Array(400 * PH * 3);
    for (let y = 0; y < PH; y++) for (let x = 0; x < 400; x++) {
        const i = (y * PW + 2 * x) * 4, a = pfb[i + 3] / 255;
        for (let k = 0; k < 3; k++) rgb[(y * 400 + x) * 3 + k] = Math.round(pfb[i + k] * a);
    }
    return rgb;
}

const ppm = (w, h, px) => Buffer.concat([Buffer.from(`P6\n${w} ${h}\n255\n`), Buffer.from(px)]);
await mkdir(out, { recursive: true });

// 1. frames against the replay
const assets = await loadAssets();
const replay = new Replay(assets, VOL, ["sky", "floor", "fate", "ulm"].includes(broke) ? broke : "");
if (broke === "vu") replay.vol = (k, n) => VOL(k, n + 1);
for (const f of FRAMES) {
    run(f - frames);
    while (replay.n < f) replay.step();
    const want = replay.render(), got = shot();
    let bad = 0, first = "";
    for (let y = 0; y < PH; y++) for (let x = 0; x < 400; x++) {
        const X = x - CANVAS_X, Y = y - CANVAS_Y, o = (y * 400 + x) * 3;
        const inside = X >= 0 && X < W && Y >= 0 && Y < H;
        for (let k = 0; k < 3; k++) {
            const w = inside ? want[(Y * W + X) * 3 + k] : 0;
            if (got[o + k] !== w) { if (!bad) first = ` (first at plane ${x},${y})`; bad++; break; }
        }
    }
    await writeFile(`${out}/f${String(f).padStart(5, "0")}.ppm`, ppm(400, PH, got));
    check(`frame ${f}: pixels off the replay${first}`, bad, 0);
}

// 2. rasters: per physical line, the colour the HBL installs for each ink
const hex3 = (c) => [...c].map((d) => parseInt(d, 16) * 17);
const rgba = ([r, g, b]) => ((255 << 24) | (b << 16) | (g << 8) | r) >>> 0;
const sky = "00E.02E.04E.06E.08E.0AE.0CE.2EE.4EE.6EE.8EE.AEE.CEE.CCE.ECE.CCC.EEC.ECC.ECA.EEA.CEA.CE8.AE8.CE6.CE0.EE0.EE4.EE6.EEC.EE6.EE2.EE0.CE0.CE2.AE4.CE6.CEA.EEA.EC8.E88.E66.E40.A20.600.600".split(".");
let rasterBad = 0, skyChanges = 0, prevSky = -1;
for (let Y = 135; Y < 180; Y++) {
    demo.hblDispatch(HBL_PLANE_ID, 0, Y + CANVAS_Y, MAGIC_X);
    const got = palette()[SKY_INK];
    const want = rgba(hex3(sky[(broke === "raster" ? Y - 134 : Y - 135) % 45]));
    if (got !== want) rasterBad++;
    if (prevSky >= 0 && got !== prevSky) skyChanges++;
    prevSky = got;
}
check("sky: SKY_INK's colour on each of its 45 lines is skyColors[line]", rasterBad, 0);
check("sky: the register changes from line to line (43 changes: 600.600 is the one repeat)", skyChanges, 43);
const idx = indices(), stride = regs.getUint16(REG_FB_STRIDE, true);
const inkRows = (ink) => { let n = 0; for (let y = 0; y < PH; y++) if (idx.subarray(y * stride, y * stride + 400).includes(ink)) n++; return n; };
check("the sky is one index in the framebuffer (drawn on sky lines only)", inkRows(SKY_INK) > 0 && inkRows(SKY_INK) <= 45, true);
check("the floor is two indices (on floor lines only)", inkRows(CHECK_DARK) > 0 && inkRows(CHECK_LIGHT) <= 42, true);
check("the VU bars are one index (on meter lines only)", inkRows(VU_INK) > 0 && inkRows(VU_INK) <= 90, true);
const darkCols = new Set();
for (let Y = 180; Y < 222; Y++) { demo.hblDispatch(HBL_PLANE_ID, 0, Y + CANVAS_Y, MAGIC_X); darkCols.add(palette()[CHECK_DARK]); }
check("floor: CHECK_DARK takes 10 colours down the floor (9 shadow bands + plain)", darkCols.size, 10);

// 3. borders
const last = shot();
const lit = (x0, x1, y0, y1) => { let n = 0; for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (last.subarray((y * 400 + x) * 3, (y * 400 + x) * 3 + 3).some((v) => v)) n++; return n; };
check("the side bars are in the left border", lit(0, 40, 144, 239) > 500, true);
check("the side bars are in the right border", lit(360, 400, 144, 239) > 500, true);
check("WHO ELSE? reaches the bottom border", lit(40, 360, 240, 280) > 3000, true);
check("the top border stays shut: nothing above row 40", lit(0, 400, 0, 40), 0);

// 4. tables and music
const dec = new TextDecoder();
check("the cart asks for the remake's own SNDH", dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), WANT_MUSIC);
let present = true;
try { await access(`docs/music/${WANT_MUSIC}`); } catch { present = false; }
check(`docs/music/${WANT_MUSIC} is on the shelf`, present, true);
if (present) {
    const s = await sndhPlay(WANT_MUSIC);
    check("it plays through the sealed YM (peak > 0.1)", s.peak > 0.1, true);
    check("no hardware write goes unanswered", s.unhandled.join(" "), "");
}
const ulmBin = new Uint8Array(await readFile("apps/zig/assets/screens/gen4_3615/ulm_dist.bin"));
const ulm = ulmDistTable();
check("ulm_dist.bin is initDistort()'s table", ulm.every((v, i) => ulmBin[2 * i] + 256 * ulmBin[2 * i + 1] === v) && ulmBin.length === 2 * ulm.length, true);
const mocheBin = new Uint8Array(await readFile("apps/zig/assets/screens/gen4_3615/moche_dist.bin"));
check("moche_dist.bin is mocheDist, rounded", mocheDistTable().every((v, i) => mocheBin[i] === Math.floor(v + 0.5)), true);

const t0 = performance.now();
run(600);
console.log(`  soak: ${frames} frames, ${((performance.now() - t0) / 600).toFixed(3)} ms/frame (update + render + 1 plane composite)`);

if (broke) {
    if (!failures) { console.log(`--break ${broke}: NO check noticed`); process.exit(1); }
    console.log(`--break ${broke}: ${failures} check(s) failed, as they must`);
    process.exit(0);
}
if (failures) { console.log(`${failures} check(s) FAILED`); process.exit(1); }
console.log("gen4_3615: all checks passed");
