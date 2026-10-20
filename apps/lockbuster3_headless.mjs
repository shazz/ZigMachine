// Headless LOCKBUSTER 3 driver (cart 101). The production is
// github.com/olivierh59500/go-lockbuster3, a Go/Ebitengine re-creation of the
// 1989 ST intro "Lockbuster DMA". This harness holds the Zig cart to it without
// a Go toolchain: it re-implements the Go's algorithm from the SAME ripped
// assets, and compares the machine to that model, not to itself.
//
//   model    every tick the cart's FRONT 320x240 index buffer equals the model's
//            (background, panels, letters, text LSB, meters), and every clock
//            word (panel step/offset/cursor/pose, scroll remaining/glyph/column,
//            all 24 signed letter words, both restore rectangles) matches
//   go       at every native 68000 checkpoint (internal/source/testdata/
//            native-clock.csv, 43 rows to tick 4800) the model's panel and
//            scroll clocks and all letter words equal the ORIGINAL's RAM
//   pixels   the machine's composited 320x200 window equals the model's colour
//            rule every frame to 1200 (then every 10th): Palette[index], text
//            bit 0 replaced on rows 160..199, indices 12/14 on rows 159..197
//            taking Rasters[row-159]; the full 400x280 frame (top and sides
//            closed, the Go's rows 200..239 in the OPENED bottom border) is
//            compared pixel for pixel at 25-tick checkpoints and at the end
//   music    the live SNDH subtune 2's YM registers 0..12 equal the Go music.ym
//            dump's lanes for every tick, the cart requests that subtune, and
//            the three meters follow registers 8/9/10
//   leave    Escape and Space both leave; Backspace (which the Go ignores) does
//            not; no zg.mem allocation refused
//   soak     ms/frame is reported, never budgeted
//
//   node apps/lockbuster3_headless.mjs [outdir] [--break MODE]
// --break SABOTAGES one input or expectation; the run passes only if the check
// meant to catch it does: pixels|front|clock|music|raster|keys
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112;
const W = 320, H = 240, VIS = 200;
const PW = 800, PH = 280; // the machine's low-res raster is x-doubled
const TICK_MS = 20;
const LAST = 4800; // the last native-clock.csv checkpoint
const EVERY = 1200; // every frame's window to here, then every 10th
const FULL_EVERY = 25;
const AUDIO_PAGES = 48;

const argv = process.argv.slice(2);
const bi = argv.indexOf("--break");
const brk = bi >= 0 ? argv.splice(bi, 2)[1] : null;
const MODES = ["pixels", "front", "clock", "music", "raster", "keys"];
if (brk && !MODES.includes(brk)) throw new Error(`--break ${brk}: ${MODES.join("|")}`);
const OUT = argv[0] || "/tmp/lockbuster3";

// --------------------------------------------------------------------------
// boot: one machine-video + ROM + cart instance. Key checks boot their own so
// Escape and Space are independent, not one already-quit flag seen twice.
// --------------------------------------------------------------------------
async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
    const noop = () => {};
    const cartBytes = await readFile("docs/demo-lockbuster3.wasm");
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
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// The live SNDH replay the cart asks the host for (not samples: its own 68000
// code driving the sealed YM, the player path the browser uses).
async function bootAudio() {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), {
        env: { memory },
    })).instance.exports;
    const env = { memory };
    for (const name of Object.keys(machine)) if (name.startsWith("machine")) env[name] = machine[name];
    const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    demo.audioInit();
    const tune = new Uint8Array(await readFile("docs/music/lockbuster2_rollout.sndh"));
    new Uint8Array(memory.buffer, demo.audioSongPtr(), tune.length).set(tune);
    if (!demo.audioLoadSndh(tune.length)) throw new Error("the Rollout SNDH was rejected");
    demo.audioSndhPlay(2);
    return { machine, demo, regs: new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16) };
}

// ==========================================================================
// The model: the Go's algorithm, from the same reduced assets.
// ==========================================================================
const A = "apps/zig/assets/screens/lockbuster3/";
const asset = {
    background: await readFile(A + "background.bin"),
    bars: await readFile(A + "bars.bin"),
    letters: await readFile(A + "letters.bin"),
    panels: [0, 1, 2].map(() => null),
    fonts: [0, 1].map(() => null),
    palette: await readFile(A + "palette.bin"),
    raster: await readFile(A + "raster.bin"),
    message: await readFile(A + "message.bin"),
    order: await readFile(A + "panel-order.bin"),
    motion: await readFile(A + "motion.bin"),
    music: await readFile(A + "music-regs.bin"),
};
for (let i = 0; i < 3; i++) asset.panels[i] = await readFile(A + `panels-${i}.bin`);
for (let i = 0; i < 2; i++) asset.fonts[i] = await readFile(A + `font-${i}.bin`);

const be16 = (b, o) => (b[o] << 8) | b[o + 1];
const be32 = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
const s16 = (v) => (v & 0x8000 ? v - 0x10000 : v);
const rgbw = (w) => [((w >> 8) & 7) * 34, ((w >> 4) & 7) * 34, (w & 7) * 34];
const pack = ([r, g, b]) => (r << 16) | (g << 8) | b;

const PAL = Array.from({ length: 16 }, (_, i) => rgbw(be16(asset.palette, i * 2)));
const RAST = Array.from({ length: 39 }, (_, i) => rgbw(be16(asset.raster, i * 2)));

const bg = new Uint8Array(W * H);
for (let t = 0; t < 5; t++)
    for (let y = 0; y < 40; y++) bg.set(asset.background.subarray(y * W, y * W + W), (t * 40 + y) * W);

const buffers = [new Uint8Array(W * H), new Uint8Array(W * H)];
const textBits = new Uint8Array(W * 40);

const model = {
    tick: 0, front: 1,
    volumes: [0, 0, 0],
    letters: Array.from({ length: 3 }, (_, i) => Array.from({ length: 8 }, (_, j) => s16(be16(asset.motion, i * 16 + j * 2)))),
    history: [[{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }], [{ x: 0, y: 0 }, { x: 0, y: 0 }, { x: 0, y: 0 }]],
    panel: {
        order: Array.from({ length: 64 }, (_, i) => be32(asset.order, i * 4)),
        cursor: 0, direction: 1, cycle: 5, stepN: 0, offset: 0, base: 0, mode: 0,
        down: false, peak: false, pose: { cell: 0, bank: 0, frame: 0 }, draw: false, commit: false,
    },
    scroll: {
        fonts: new Uint8Array(asset.message.length), columns: [Array(40), Array(40)],
        glyph: 0, column: 0, row: 0, changes: 0, remaining: asset.message.length,
    },
};

function stepLetter(l) {
    l[0] += l[2]; l[1] += l[3]; l[2] += l[4]; l[3] += l[5];
    if (l[2] === l[6] || l[2] === -l[6]) l[4] = -l[4];
    if (l[3] === l[7] || l[3] === -l[7]) l[5] = -l[5];
}

function restore(dst, r) {
    let sy = r.y, dy = 0, n = 35;
    if (sy < 0) { dy = -sy; n -= dy; sy = 0; }
    if (sy + n > H) n = H - sy;
    let sx = r.x, dx = 0, w = 64;
    if (sx < 0) { dx = -sx; w -= dx; sx = 0; }
    if (sx + w > W) w = W - sx;
    if (n <= 0 || w <= 0) return;
    for (let row = 0; row < n; row++)
        dst.set(bg.subarray((sy + row) * W + sx, (sy + row) * W + sx + w), (sy + row) * W + sx);
}

function drawLetter(dst, which, x, y) {
    const src = asset.letters.subarray(which * 48 * 35, (which + 1) * 48 * 35);
    for (let sy = 0; sy < 35; sy++) {
        const ty = y + sy;
        if (ty < 0 || ty >= H) continue;
        for (let sx = 0; sx < 48; sx++) {
            const v = src[sy * 48 + sx];
            if (v === 0) continue;
            const tx = x + sx;
            if (tx < 0 || tx >= W) continue;
            dst[ty * W + tx] = v;
        }
    }
}

function panelPixel(bank, frame, sx, sy) {
    const fx = (frame % 5) * 64 + sx, fy = ((frame / 5) | 0) * 40 + sy;
    const at = fy * 320 + fx, b = asset.panels[bank][at >> 1];
    return (at & 1) === 0 ? b >> 4 : b & 15;
}

function drawPanel(dst, bank, frame, x, y) {
    for (let sy = 0; sy < 40; sy++) {
        const ty = y + sy;
        if (ty < 0 || ty >= H) continue;
        for (let sx = 0; sx < 64; sx++) {
            const tx = x + sx;
            if (tx < 0 || tx >= W) continue;
            dst[ty * W + tx] = panelPixel(bank, frame, sx, sy);
        }
    }
}

function drawBars(dst, volumes) {
    for (let i = 0; i < 3; i++) {
        const v = volumes[i];
        const sx = (v < 10 ? v : v - 10) * 32, sy = v < 10 ? 0 : 25;
        const x = 80 + i * 64;
        for (let dy = 0; dy < 25; dy++)
            dst.set(asset.bars.subarray((sy + dy) * 320 + sx, (sy + dy) * 320 + sx + 32), (210 + dy) * W + x);
    }
}

function drawLetters(target) {
    const dst = buffers[target];
    for (let i = 0; i < 3; i++) {
        const x = model.letters[i][0], y = model.letters[i][1];
        drawLetter(dst, i, x, y);
        model.history[target][i] = { x: x & ~15, y };
    }
}

function initialBit(lane, slot, dx, dy) {
    return asset.background[(lane * 20 + dy) * W + slot * 8 + dx] & 1;
}

function fontBit(bank, glyph, column, dx, dy) {
    const x = (glyph % 16) * 32 + column * 8 + dx, y = ((glyph / 16) | 0) * 20 + dy;
    const b = asset.fonts[bank][y * 64 + (x >> 3)];
    return (b >> (7 - (x & 7))) & 1;
}

function drawText() {
    textBits.fill(0);
    for (let lane = 0; lane < 2; lane++)
        for (let slot = 0; slot < 40; slot++) {
            const c = model.scroll.columns[lane][slot];
            for (let dy = 0; dy < 20; dy++)
                for (let dx = 0; dx < 8; dx++) {
                    const bit = c.initial ? initialBit(lane, slot, dx, dy) : fontBit(c.font, c.glyph, c.column, dx, dy);
                    textBits[(lane * 20 + dy) * W + slot * 8 + dx] = bit;
                }
        }
}

function panelStep(p) {
    p.draw = false; p.commit = false;
    const entry = p.order[p.cursor];
    if (entry === 250) {
        p.direction = 1; p.cursor = 1; p.cycle = 5; p.stepN = 0; p.offset = 0; p.base = 0;
        p.down = false; p.peak = false; return;
    }
    if (entry === 253) {
        p.mode ^= 1; p.direction = -1; p.cursor -= 1; p.offset = 25600; p.base = 25600;
        p.stepN = 0; p.down = false; return;
    }
    if (entry === 254) {
        p.cursor += p.direction; p.offset = 51200; p.base = 51200; p.stepN = 0; p.down = false; return;
    }
    if (entry === 255) {
        p.cursor += p.direction; p.mode ^= 1; p.offset = p.mode * 25600; p.base = p.offset;
        p.stepN = 0; p.down = false; return;
    }
    const x = ((entry % 6400) / 32) | 0, y = (entry / 6400) | 0;
    const local = p.offset % 25600;
    p.pose = {
        cell: y * 5 + x,
        bank: (p.offset / 25600) | 0,
        frame: (((local / 6400) | 0) * 5 + (((local % 6400) / 32) | 0)),
    };
    p.draw = true;
    if (p.peak) { p.peak = false; p.commit = true; p.cursor += p.direction; return; }
    if (p.down) {
        p.stepN -= 1;
        if (p.stepN === 0) { p.cycle = 5; p.down = false; return; }
        p.cycle -= 1;
        if (p.cycle === 0) { p.cycle = 5; p.offset -= 6240; }
        p.offset -= 32;
        return;
    }
    p.stepN += 1;
    if (p.stepN === 20) { p.cycle = 5; p.down = true; p.peak = true; return; }
    p.cycle -= 1;
    if (p.cycle === 0) { p.cycle = 5; p.offset += 6240; }
    p.offset += 32;
}

function scrollStep(s) {
    const wanted = s.fonts[s.glyph];
    if (wanted !== s.row) {
        s.row = wanted;
        if (wanted === 0) s.remaining = asset.message.length - s.glyph;
        s.changes++;
        return;
    }
    const r = asset.message[s.glyph];
    let glyph = (r - 32) & 255;
    if (r === 32) glyph = 3;
    for (let i = 0; i < 39; i++) s.columns[s.row][i] = s.columns[s.row][i + 1];
    s.columns[s.row][39] = { font: wanted, glyph, column: s.column, initial: 0, row: s.row, slot: 39 };
    s.column++;
    if (s.column === 4) {
        s.column = 0; s.glyph++;
        if (s.row === 0) s.remaining--;
        if (s.glyph === asset.message.length) { s.glyph = 0; s.remaining = asset.message.length; }
        else if (s.row === 1 && s.fonts[s.glyph] === 0) s.remaining = asset.message.length - s.glyph;
    }
}

function modelStep(volumes) {
    model.tick++;
    model.volumes = volumes.slice();
    const target = 1 - model.front;
    for (let i = 0; i < 3; i++) restore(buffers[target], model.history[target][i]);
    panelStep(model.panel);
    if (model.panel.draw) {
        const p = model.panel.pose, x = (p.cell % 5) * 64, y = ((p.cell / 5) | 0) * 40;
        drawPanel(buffers[target], p.bank, p.frame, x, y);
        if (model.panel.commit) drawPanel(bg, (model.panel.base / 25600) | 0, 19, x, y);
    }
    for (let i = 0; i < 3; i++) stepLetter(model.letters[i]);
    drawLetters(target);
    scrollStep(model.scroll);
    drawText();
    drawBars(buffers[target], model.volumes);
    model.front = target;
}

// --- the model's first frame: NewGame's two pre-stepped buffers ------------
for (let i = 0; i < 2; i++) {
    buffers[i].set(bg);
    for (let j = 0; j < 3; j++) stepLetter(model.letters[j]);
    drawLetters(i);
}
{
    let bank = 0;
    for (let i = 0; i < asset.message.length; i++) {
        const r = asset.message[i];
        if (r === 5) bank = 1; else if (r === 6) bank = 0;
        model.scroll.fonts[i] = bank;
    }
    for (let lane = 0; lane < 2; lane++)
        for (let slot = 0; slot < 40; slot++)
            model.scroll.columns[lane][slot] = { font: 0, glyph: 0, column: 0, initial: 1, row: lane, slot };
    drawText();
}

// --- the shader: text bit first, then the raster on 12/14 -----------------
function colourAt(row, x) {
    let idx = buffers[model.front][row * W + x];
    if (row >= 160 && row < 200) idx = (idx & ~1) | textBits[(row - 160) * W + x];
    if ((idx === 12 || idx === 14) && row >= 159 && row < 198) {
        let r = RAST[row - 159];
        if (brk === "raster") r = RAST[(row - 159 + 1) % 39];
        return r;
    }
    return PAL[idx];
}

function modelWindow() {
    const out = new Uint8Array(320 * 200 * 3);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++) {
            const c = colourAt(y, x);
            const o = (y * 320 + x) * 3;
            out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2];
        }
    if (brk === "pixels") out[(100 * 320 + 200) * 3] ^= 1;
    return out;
}

function modelFull() {
    const out = new Uint8Array(400 * 280 * 3);
    for (let py = 0; py < 280; py++)
        for (let lx = 0; lx < 400; lx++) {
            let c = [0, 0, 0];
            if (py >= 40 && py < 280 && lx >= 40 && lx < 360) c = colourAt(py - 40, lx - 40);
            const o = (py * 400 + lx) * 3;
            out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2];
        }
    if (brk === "pixels") out[(100 * 400 + 200) * 3] ^= 1;
    return out;
}

// ==========================================================================
// run
// ==========================================================================
await mkdir(OUT, { recursive: true });
const { memory, machine, demo } = await boot();
const BX = machine.hwBorderX();
const BY = machine.hwBorderY();
const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), PW * PH * 4);
const ymPtr = demo.getYmRegsPointer();
const cartRegs = new Uint8Array(memory.buffer, ymPtr, 16);

const errors = [];
const fail = (msg) => { errors.push(msg); };
const check = (cond, msg) => { if (!cond) fail(msg); };

// The Go's music.ym register lanes (14 bytes/frame), and the matching SNDH.
const musicFrames = asset.music.length / 14;
check(Number.isInteger(musicFrames) && musicFrames === 10650, `music-regs.bin has ${musicFrames} frames, want 10650`);
const audio = await bootAudio();
check(audio.demo.audioMode() === 4, "the requested SNDH is not playing on the sealed YM");
check(audio.demo.audioSndhSubtunes() >= 2, `the Rollout SNDH has ${audio.demo.audioSndhSubtunes()} subtunes, want >= 2`);

// The cart's boot frame: NewGame has composed both buffers but done no Update.
{
    machine.hwClear();
    demo.frame(0);
    check(demo.lb3Ready() === 1, "the cart did not initialise");
    check(demo.lb3Tick() === 0 && demo.lb3FrontIndex() === 1, `boot tick/front ${demo.lb3Tick()}/${demo.lb3FrontIndex()}, want 0/1`);
    const ptr = demo.lb3Front();
    check(ptr !== 0, "lb3Front returned null");
    if (ptr) {
        const got = new Uint8Array(memory.buffer, ptr, W * H);
        const d = firstDiff(got, buffers[1]);
        check(d < 0, d >= 0 ? `boot front buffer differs at byte ${d}: ${got[d]} vs ${buffers[1][d]}` : "");
    }
}

// song request
{
    check(demo.pollSongRequest() !== 0, "the cart requested no song");
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    check(name === "lockbuster2_rollout.sndh", `song is "${name}", want "lockbuster2_rollout.sndh"`);
    check(demo.songTune() === 2, `subtune is ${demo.songTune()}, want 2`);
}

const csv = (await readFile("tools/lockbuster3/native-clock.csv", "utf8")).trim().split("\n");
const native = new Map();
for (const line of csv.slice(1)) {
    const v = line.split(",").map(Number);
    native.set(v[0], v);
}
check(native.size === 43, `native-clock.csv has ${native.size} checkpoints, want 43`);

const bePacked = (x, y) => (((x & 0xffff) << 16) | (y & 0xffff)) >>> 0;
function firstDiff(a, b) {
    const n = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) if (a[i] !== b[i]) return i;
    return a.length === b.length ? -1 : n;
}

let comparedRaw = 0, comparedWin = 0, comparedFull = 0, nativeChecked = 0;
let rasterPixels = 0, rasterAt = 0;
const t0 = performance.now();
let cartMs = 0;

function compareState(tick) {
    check(demo.lb3Tick() === model.tick, `tick ${demo.lb3Tick()} != model ${model.tick}`);
    const wantFront = brk === "front" ? 1 - model.front : model.front;
    check(demo.lb3FrontIndex() === wantFront, `front ${demo.lb3FrontIndex()} != model ${wantFront}`);

    const want = [
        2, model.panel.stepN, 3, model.panel.offset, 4, model.panel.cursor, 5, model.panel.cycle,
        6, model.panel.direction, 7, model.panel.mode, 8, model.panel.base,
        9, model.panel.draw ? 1 : 0, 10, model.panel.commit ? 1 : 0,
        11, model.panel.pose.cell, 12, model.panel.pose.bank, 13, model.panel.pose.frame,
        14, model.scroll.remaining, 15, model.scroll.glyph, 16, model.scroll.column,
        17, model.scroll.row, 18, model.scroll.changes,
    ];
    for (let i = 0; i < want.length; i += 2) {
        const field = want[i];
        let value = want[i + 1];
        if (brk === "clock" && field === 3) value += 1;
        const got = demo.lb3Field(field);
        check(got === value, `field ${field} is ${got}, model says ${value}`);
    }
    for (let i = 0; i < 3; i++) {
        let value = model.volumes[i];
        if (brk === "music") value = (value + 1) & 15;
        check(demo.lb3Field(19 + i) === value, `meter ${i} is ${demo.lb3Field(19 + i)}, model says ${value}`);
    }

    for (let l = 0; l < 3; l++)
        for (let w = 0; w < 8; w++) {
            const got = demo.lb3Letter(l, w);
            const value = model.letters[l][w] & 0xffff;
            check(got === value, `letter ${l} word ${w} is ${got}, model says ${value}`);
        }

    for (let t = 0; t < 2; t++)
        for (let i = 0; i < 3; i++) {
            const got = demo.lb3History(t, i) >>> 0;
            const r = model.history[t][i];
            const value = bePacked(r.x, r.y);
            check(got === value, `history[${t}][${i}] is ${got}, model says ${value}`);
        }

    const ptr = demo.lb3Front();
    if (ptr) {
        const got = new Uint8Array(memory.buffer, ptr, W * H);
        const d = firstDiff(got, buffers[model.front]);
        check(d < 0, d >= 0 ? `tick ${tick}: front buffer byte ${d} is ${got[d]}, model says ${buffers[model.front][d]}` : "");
        comparedRaw++;
    }

    const row = native.get(tick);
    if (row) {
        const got = [
            tick, demo.lb3Field(2), demo.lb3Field(3), demo.lb3Field(4),
            demo.lb3Field(14), demo.lb3Field(15), demo.lb3Field(16),
        ];
        for (let i = 0; i < 7; i++)
            check(got[i] === row[i], `native clock tick ${tick} field ${i} is ${got[i]}, the 68000 says ${row[i]}`);
        for (let l = 0; l < 3; l++)
            for (let w = 0; w < 8; w++) {
                const gotW = demo.lb3Letter(l, w);
                const wantW = row[7 + l * 8 + w];
                check(gotW === wantW, `native clock tick ${tick} letter ${l} word ${w} is ${gotW}, the 68000 says ${wantW}`);
            }
        nativeChecked++;
    }
}

function compareWindow(tick) {
    machine.hwRenderPlane(0);
    const want = modelWindow();
    let bad = -1;
    for (let y = 0; y < 200 && bad < 0; y++)
        for (let x = 0; x < 320; x++) {
            const i = ((BY + y) * PW + (BX + x * 2)) * 4;
            if (pfb[i] !== want[(y * 320 + x) * 3] ||
                pfb[i + 1] !== want[(y * 320 + x) * 3 + 1] ||
                pfb[i + 2] !== want[(y * 320 + x) * 3 + 2]) { bad = y * 320 + x; break; }
        }
    check(bad < 0, bad >= 0 ? `tick ${tick}: window (${bad % 320},${(bad / 320) | 0}) is ` +
        `${pfb[((BY + ((bad / 320) | 0)) * PW + BX + (bad % 320) * 2) * 4]},${pfb[((BY + ((bad / 320) | 0)) * PW + BX + (bad % 320) * 2) * 4 + 1]},` +
        `${pfb[((BY + ((bad / 320) | 0)) * PW + BX + (bad % 320) * 2) * 4 + 2]}, model says ${want[bad * 3]},${want[bad * 3 + 1]},${want[bad * 3 + 2]}` : "");
    comparedWin++;
}

function compareFull(tick) {
    machine.hwRenderPlane(0);
    const want = modelFull();
    let bad = -1;
    for (let py = 0; py < PH && bad < 0; py++)
        for (let lx = 0; lx < 400; lx++) {
            const o = (py * 400 + lx) * 3, i = (py * PW + lx * 2) * 4;
            if (pfb[i] !== want[o] || pfb[i + 1] !== want[o + 1] || pfb[i + 2] !== want[o + 2]) { bad = py * 400 + lx; break; }
            // the doubled second pixel must agree too (put2)
            if (pfb[i + 4] !== want[o] || pfb[i + 5] !== want[o + 1] || pfb[i + 6] !== want[o + 2]) { bad = py * 400 + lx; break; }
        }
    check(bad < 0, bad >= 0 ? `tick ${tick}: full frame (${bad % 400},${(bad / 400) | 0}) differs` : "");
    comparedFull++;
}

async function shot(path, frame) {
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n400 280\n255\n`), frame]));
}

// Count the raster-only pixels at the first full checkpoint, so a raster
// sabotage cannot pass merely because no pixel used entry 12/14.
function countRasterPixels() {
    let n = 0;
    for (let y = 159; y < 198; y++)
        for (let x = 0; x < 320; x++) {
            let idx = buffers[model.front][y * W + x];
            if (y >= 160) idx = (idx & ~1) | textBits[(y - 160) * W + x];
            if (idx === 12 || idx === 14) n++;
        }
    return n;
}

// Boot frame pixels.
{
    machine.hwClear();
    machine.hwRenderPlane(0);
    const want = modelFull();
    let bad = -1;
    for (let py = 0; py < PH && bad < 0; py++)
        for (let lx = 0; lx < 400; lx++) {
            const o = (py * 400 + lx) * 3, i = (py * PW + lx * 2) * 4;
            if (pfb[i] !== want[o] || pfb[i + 1] !== want[o + 1] || pfb[i + 2] !== want[o + 2]) { bad = py * 400 + lx; break; }
        }
    check(bad < 0, bad >= 0 ? `boot full frame (${bad % 400},${(bad / 400) | 0}) differs` : "");
    comparedFull++;
    await shot(`${OUT}/frame_000000.ppm`, want);
}

console.log("boot ok");

for (let tick = 1; tick <= LAST; tick++) {
    // The live SNDH: exactly one 20 ms block (882 frames at 44.1 kHz).
    audio.demo.audioRender(882);
    for (let r = 0; r < 13; r++) {
        const want = asset.music[(tick - 1) * 14 + r];
        check(audio.regs[r] === want,
            `tick ${tick}: live SNDH YM reg ${r} is ${audio.regs[r]}, the Go music.ym says ${want}`);
    }
    cartRegs.set(audio.regs.subarray(0, 16));

    const vols = [0, 1, 2].map((i) => audio.regs[8 + i] & 15);
    modelStep(vols);

    machine.hwClear();
    const c0 = performance.now();
    demo.frame(TICK_MS);
    cartMs += performance.now() - c0;

    compareState(tick);

    const doWin = tick <= EVERY || tick % 10 === 0 || tick === LAST;
    const doFull = tick % FULL_EVERY === 0 || tick === LAST || tick === 1 || tick === 1144;
    if (doWin) compareWindow(tick);
    if (doFull) {
        const rp = countRasterPixels();
        if (rp > 0 && rasterAt === 0) rasterAt = tick;
        rasterPixels = Math.max(rasterPixels, rp);
        compareFull(tick);
        if (tick === 1 || tick === 1144 || tick === LAST) {
            machine.hwRenderPlane(0);
            const out = new Uint8Array(400 * 280 * 3);
            for (let py = 0; py < 280; py++)
                for (let lx = 0; lx < 400; lx++) {
                    const i = (py * PW + lx * 2) * 4, o = (py * 400 + lx) * 3;
                    out[o] = pfb[i]; out[o + 1] = pfb[i + 1]; out[o + 2] = pfb[i + 2];
                }
            await shot(`${OUT}/frame_${String(tick).padStart(6, "0")}.ppm`, out);
        }
    }
}
const ms = performance.now() - t0;

// --- leaving: Escape and Space each leave; Backspace does not -------------
for (const [name, cp, want] of [["Escape", 0xE012, -1], ["Space", 32, -1], ["Backspace", 8, 0]]) {
    const fresh = await boot();
    fresh.demo.key(cp);
    const got = fresh.demo.pollCartRequest();
    // --break keys expects Backspace to leave, which the Go does NOT do.
    const expected = brk === "keys" && name === "Backspace" ? -1 : want;
    check(got === expected, `${name} key -> pollCart ${got}, want ${expected}`);
}

// --- allocation and coverage ---------------------------------------------
check(machine.hwRamAllocFailures() === 0, `${machine.hwRamAllocFailures()} zg.mem allocations were refused`);
check(nativeChecked === 43, `compared ${nativeChecked} native 68000 clock checkpoints, want 43`);
check(comparedRaw === LAST, `compared ${comparedRaw} front buffers, want ${LAST}`);
check(comparedWin >= EVERY, `compared ${comparedWin} composited windows, want >= ${EVERY}`);
check(comparedFull >= LAST / FULL_EVERY, `compared ${comparedFull} full 400x280 frames, want >= ${LAST / FULL_EVERY}`);
check(rasterPixels > 0, "no pixel uses raster entry 12/14 at the first checkpoint");
if (!brk) check(errors.length === 0, `${errors.length} mismatches`);

const perFrame = cartMs / LAST;
console.log(`  tick ${demo.lb3Tick()}, ${comparedRaw} front buffers, ${comparedWin} windows, ${comparedFull} full frames, ${nativeChecked} native checkpoints`);
console.log(`  music: lockbuster2_rollout.sndh #2, ${LAST} live YM frames == the Go music.ym (regs 0..12)`);
console.log(`  raster: ${rasterPixels} pixels use entries 12/14 (first seen at tick ${rasterAt})`);
console.log(`  ${perFrame.toFixed(3)} ms/frame cart (reported, not budgeted)`);

if (errors.length) {
    console.error(`lockbuster3: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(brk ? 0 : 1); // a --break run PASSES only because something failed
}
if (brk) {
    console.log(`lockbuster3: FAILED — --break ${brk} was not caught`);
    process.exit(1);
}
console.log(`lockbuster3: PASS (${(ms / 1000).toFixed(2)} s wall)`);
