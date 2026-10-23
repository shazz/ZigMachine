// Headless PHENOMENA driver (cart 102): the Amiga intro coded by Photon, as
// remade in CODEF at wab.com/?screen=560 (prototypes/codef/560/screen.js).
// The model below is written from screen.js, not from the Zig, and holds the
// cart to it end to end:
//
//   seq     every frame, the phase chain (showTextPage1 .. dropPhoton ..
//           photonFadeToRed .. go) and every word it keeps -- percent,
//           direction, rasterbarY, the drop, color, t, the reveal quad -- and
//           what the frame shows, equal the model's
//   dna     every frame, the scroller queue (240..247 slices: glyph, frame,
//           slice), head, length, msgIndex, sliceCount, pause, pauseTime and
//           the speeds equal the model's scrollMessage / renderNextFrames
//   wave    every main frame, the 160 strip tops equal 67 + (t2 > 250 -
//           0.0033i ? 80cos(52.5 + t2/6) : 80) in doubles to 1/256 of a row
//   pixels  at checkpoints the composited 800x280 raster equals the model's
//           picture pixel for pixel: page 1's punched text over the sliding
//           grey bar, page 2's fade, the logo's grey and white silhouettes,
//           the bars fading in, the drop, the red fade, the scroller and its
//           reveal, the wave
//   raster  the bars are registers: their lines are one colour edge to edge
//           (borders included) and each line has its own colour from the
//           BAR entry, which no static palette could give
//   music   nothing is asked for until the lower bar is in; then
//           rasta_man.mod, once; and that MOD loads and plays on the audio
//           modules (4 channels triggered, not silent)
//   keys    Escape and Back hand the screen back; Fire changes nothing
//
//   node apps/phenomena_headless.mjs [outdir]
//   node apps/phenomena_headless.mjs --break seq|dna|pixels|raster|music  (each must FAIL)
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";
import { Model, Assets, LINE } from "./phenomena_model.mjs";
import { picture } from "./phenomena_picture.mjs";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/phenomena";
const BREAKS = ["seq", "dna", "pixels", "raster", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const MUSIC = broke === "music" ? "rasta man.mod" : "rasta_man.mod";

// ---------------- boot ------------------------------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const cartBytes = await readFile("docs/demo-phenomena.wasm");
const env = { ...romEnv, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
async function startCart() {
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
}
await startCart();
await mkdir(OUT, { recursive: true });

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };
const song = () => demo.pollSongRequest() === 1
    ? new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())) : null;

// ---------------- the run ---------------------------------------------------
const assets = await Assets.load("apps/zig/assets/screens/phenomena/");
const M = new Model(assets);
const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), 800 * 280);
const CHECK = [1, 120, 254, 255, 330, 420, 520, 545, 560, 600, 640, 660, 674, 676, 700, 760, 813, 820, 826,
    900, 1100, 1400, 1520, 1560, 1700, 2000, 2400, 2700];
const LAST = 2700;
const SEQ_NAMES = ["phase", "percent", "direction", "rb2", "dropN", "color3", "t", "rectW", "rectShow",
    "view.phase", "view.level", "view.rb2", "view.photon", "view.hue", "view.rectW", "view.t"];
const DNA_NAMES = ["head", "len", "msgIndex", "sliceCount", "pause", "pauseTime", "scrollSpeed", "rotSpeed"];

function checkWords(frame) {
    const s = M.seqWords(), d = M.dnaWords();
    for (let k = 0; k < s.length; k++) {
        const got = demo.phSeq(k) + (broke === "seq" && frame === 300 && k === 1 ? 1 : 0);
        if (got !== s[k]) return `frame ${frame}: ${SEQ_NAMES[k]} ${got} != ${s[k]}`;
    }
    for (let k = 0; k < d.length; k++) if (demo.phDna(k) !== d[k]) return `frame ${frame}: ${DNA_NAMES[k]} ${demo.phDna(k)} != ${d[k]}`;
    for (let i = 0; i < M.dna.len; i++) {
        const c = M.dna.at(i);
        const g = demo.phCell(i, 0) ^ (broke === "dna" && frame === 900 && i === 5 ? 1 : 0);
        if (g !== c.chr || demo.phCell(i, 1) !== c.frm || demo.phCell(i, 2) !== c.slc)
            return `frame ${frame}: slice ${i} is ${g},${demo.phCell(i, 1)},${demo.phCell(i, 2)}, model ${c.chr},${c.frm},${c.slc}`;
    }
    return null;
}

let failure = null, compared = 0, songs = [], waveFrames = 0, worstTop = 0, drift = 0, driftN = 0;
const tops = new Int32Array(160);
const t0 = performance.now();
for (let frame = 1; frame <= LAST && !failure; frame++) {
    machine.hwClear();
    M.step();
    demo.frame(20);
    const s = song();
    if (s !== null) songs.push([frame, s]);
    failure = checkWords(frame);
    if (failure) break;
    if (M.seq.view.phase === 7) {
        for (let i = 0; i < 160; i++) {
            tops[i] = demo.phStripTop(i);
            const err = Math.abs(tops[i] / 65536 - M.stripTopDouble(i));
            if (err > worstTop) worstTop = err;
        }
        waveFrames++;
        const f = M.frameAgreement();
        drift += f.differ; driftN += f.total;
    }
    if (CHECK.includes(frame)) {
        machine.hwRenderPlane(0); // the copper's HBL runs here
        const want = picture(M, tops);
        if (broke === "pixels" && frame === 1100) want[800 * 100 + 300] ^= 0xFF;
        for (let i = 0; i < want.length; i++) {
            if (pfb[i] !== want[i]) {
                failure = `frame ${frame} (${M.phaseName()}): physical (${i % 800},${(i / 800) | 0}) is ` +
                    `${pfb[i].toString(16)} not ${want[i].toString(16)}`;
                break;
            }
        }
        if (failure) break;
        compared++;
        if (frame === 900 || frame === 2000) await writeFile(`${OUT}/frame_${frame}.ppm`, ppm(pfb));
        if (frame === 2000) failure = checkRaster();
    }
}
const ms = (performance.now() - t0) / LAST;

/// The bars are registers: on each bar line, x 0 (border), 400 and 799
/// (border) are the same colour, and the six lines are six colours.
function checkRaster() {
    for (const first of [LINE.BAR_TOP, LINE.BAR_BOTTOM]) {
        const seen = new Set();
        for (let j = 0; j < 6; j++) {
            const row = (20 + first + j) * 800;
            const c = pfb[row];
            if (pfb[row + 400] !== c || pfb[row + 799] !== c) return `raster: bar line ${first + j} is not one colour edge to edge`;
            seen.add(broke === "raster" ? 0 : c);
        }
        if (seen.size !== 6) return `raster: the bar at line ${first} shows ${seen.size} colours, not 6 (no per-line register)`;
    }
    return null;
}

function ppm(px) {
    const body = Buffer.alloc(800 * 280 * 3);
    for (let i = 0; i < px.length; i++) {
        body[3 * i] = px[i] & 255; body[3 * i + 1] = (px[i] >> 8) & 255; body[3 * i + 2] = (px[i] >> 16) & 255;
    }
    return Buffer.concat([Buffer.from("P6\n800 280\n255\n"), body]);
}

if (failure) errors.push(failure);
else {
    ok(true, `seq + dna: every word and all ${M.dna.len} queue slices equal the model on all ${LAST} frames`);
    ok(compared === CHECK.length, `${compared} frames equal the model pixel for pixel (pages, logo, bars, drop, fade, scroller, wave)`);
    ok(worstTop <= 1 / 256, `wave: ${waveFrames} main frames, strip tops within ${worstTop.toFixed(5)} rows of screen.js's doubles`);
    ok(true, "raster: both bars are six per-line colours, edge to edge through the borders");
    const want = [[M.musicFrame, MUSIC]];
    ok(JSON.stringify(songs) === JSON.stringify(want),
        `music: requests ${JSON.stringify(songs)} (screen.js: ${JSON.stringify(want)}, when the lower bar is in)`);
    console.log(`  info: frm floor differs from screen.js's accumulated doubles on ${(100 * drift / Math.max(driftN, 1)).toFixed(3)}% of slice-frames`);
    // screen.js sums 0.35 in doubles, so frm sits a hair under an integer now
    // and then (6.999.. shows frame 6 for one frame); the cart keeps the exact
    // value. Bounded, because frm resets to 0 past 29: the harness holds it there.
    ok(drift <= driftN / 20, "dna: the exact twentieths agree with the remake's doubles on >= 95% of slice-frames");
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
    console.log(`  ${ms.toFixed(3)} ms/frame over ${LAST} frames (update + render + model)`);
    await checkKeys();
    await checkMod();
}

async function checkKeys() {
    await startCart();
    for (let f = 0; f < 5; f++) demo.frame(20);
    const before = demo.phSeq(0) + "," + demo.phSeq(3);
    demo.input(5); // Fire
    demo.frame(20);
    ok(demo.pollCartRequest() === 0 && demo.phSeq(3) === -80 + 3 * 6 && before === "0,-65",
        "keys: Fire changes nothing (screen.js no longer acts on its click)");
    demo.key(0xE012);
    demo.frame(20);
    ok(demo.pollCartRequest() === -1, "keys: Escape hands the screen back (pollCartRequest -1)");
    await startCart();
    demo.input(6);
    demo.frame(20);
    ok(demo.pollCartRequest() === -1, "keys: Back hands the screen back (pollCartRequest -1)");
}

/// The tune itself: rasta_man.mod on the real audio modules, 12 s.
async function checkMod() {
    const mem = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
    const fired = new Set();
    const aenv = { memory: mem };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) aenv[n] = m[n];
    aenv.machinePaulaTrigger = (ch, ...a) => { fired.add(ch); m.machinePaulaTrigger(ch, ...a); };
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env: aenv })).instance.exports;
    a.audioInit();
    const mod = new Uint8Array(await readFile(`docs/music/${MUSIC.replace(" ", "_")}`));
    new Uint8Array(mem.buffer, a.audioSongPtr(), mod.length).set(mod);
    const loaded = a.audioLoadMod(mod.length);
    if (loaded) a.audioModPlay();
    let peak = 0;
    for (let n = 0; n < 44100 * 12; n += 128) {
        a.audioRender(128);
        const out = new Float32Array(mem.buffer, m.audioLeftPtr(), 128);
        for (const v of out) peak = Math.max(peak, Math.abs(v));
    }
    ok(loaded && fired.size === 4 && peak > 0.05,
        `music: ${MUSIC} loads (M.K.), triggers ${fired.size}/4 Paula channels and peaks at ${peak.toFixed(3)} in 12 s`);
}

if (broke) {
    console.log(errors.length ? `phenomena: PASS (--break ${broke} caught: ${errors[0]})` : `phenomena: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `phenomena: FAILED -- ${errors.join("; ")}` : "phenomena: all pass");
process.exit(errors.length ? 1 : 0);
