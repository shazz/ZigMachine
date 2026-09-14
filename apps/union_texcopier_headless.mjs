// Headless Union Demo COPIER TEX check (apps/zig/scenes/union_texcopier.zig).
//
// 1. The depack: the cart starts behind the TEX loader panel (zx0.Fx.tex_loader)
//    with screens/texcopier/loader.js's text. Every depack frame shows only the
//    loader ink #C0A000 on black, and the last one has the panel's letters landed.
// 2. The screen: frame by frame, Space pressed before update SPACE_AT, compared
//    pixel for pixel with apps/union_texcopier_replay.mjs (screen.js in canvas
//    units with Chrome's bilinear mixes), which matched the remake running in
//    Chrome on every pixel sampled over frames 1..1000.
// 3. The music: the song request is union/scoop.sndh subtune 2, and that tune
//    loads on the real audio modules, plays every second on all three voices, no
//    stuck PC.
// 4. Escape asks for the Union Demo menu's disk.
// 5. A warm frame fits well inside 60 fps.
//
//   node apps/union_texcopier_headless.mjs [outdir] [cart.wasm] [--break mix|period]
// --break runs the replay with round-half-up mixes or a 103-frame raster period:
// the check must then FAIL, which is how the harness proves it can.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeReplay, SHOTS, SPACE_AT } from "./union_texcopier_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // the 320x200 window in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_texcopier";
const PANEL = `${ASSETS}/loader_texcopier.txt`;
const MUSIC = "union/scoop.sndh", MUSIC_TUNE = 2, MODE_SNDH = 4;
const DEPACK_FRAMES = Math.ceil(35584 / 280); // DEPACK_BYTES_PER_LINE = 1
const INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012;

const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at < 0 ? null : argv.splice(at, 2)[1];
if (brk !== null && !["mix", "period"].includes(brk)) throw new Error(`--break takes mix or period, not ${brk}`);
const outDir = argv[0] || "/tmp/union_texcopier";
const cartPath = argv[1] || "docs/demo-union_texcopier.wasm";

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
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
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

/// The 320x200 window as the host composites it, over black.
function capture(memory, machine, demo) {
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), img = new Uint8Array(320 * 200 * 3);
    machine.hwClear();
    let planes = 0;
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        planes++;
        machine.hwRenderPlane(p);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const i = ((TOP + y) * W + LEFT + x * 2) * 4, a = px[i + 3] / 255, o = (y * 320 + x) * 3;
            for (let c = 0; c < 3; c++) img[o + c] = Math.round(img[o + c] * (1 - a) + px[i + c] * a);
        }
    }
    return { img, planes };
}

function png(w, h, rgb) {
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc32 = (buf) => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) Buffer.from(rgb.buffer, rgb.byteOffset + y * w * 3, w * 3).copy(raw, y * (w * 3 + 1) + 1);
    const chunk = (type, data) => {
        const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
        const td = Buffer.concat([Buffer.from(type), data]);
        const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
        return Buffer.concat([len, td, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

/// The loader panel with every letter landed: row r's top at 8 + 8r, column c at 80 + 8c.
async function landedPanel() {
    const rows = (await readFile(PANEL, "utf8")).split("\n").filter((l) => l.startsWith('"')).map((l) => l.slice(1, -1));
    const font = await readFile("libs/zig/depackers/tex_loader/loader.raw"); // 80x48, 10 glyphs a row
    const ink = new Uint8Array(320 * 200);
    rows.forEach((row, r) => [...row].forEach((ch, c) => {
        const g = ch.charCodeAt(0) - 32;
        for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++)
            if (font[(Math.floor(g / 10) * 8 + y) * 80 + (g % 10) * 8 + x]) ink[(8 + 8 * r + y) * 320 + 80 + 8 * c + x] = 1;
    }));
    return { ink, cols: rows[0].length };
}

/// The requested SNDH on the real audio modules, the way the worklet plays a .sndh.
async function sndhPlay(name, tune, seconds = 10) {
    const SR = 44100, BLOCK = 882;
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const volWrites = [0, 0, 0];
    env.machineYmWrite = (r, v) => { if (r >= 8 && r <= 10) volWrites[r - 8]++; return machine.machineYmWrite(r, v); };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { why: "over song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(tune);
    volWrites.fill(0);
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < seconds * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { const a = Math.abs(v); peak = Math.max(peak, a); secPeak = Math.max(secPeak, a); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { peak, silent, volWrites, mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc() };
}

const errors = [];
await mkdir(outDir, { recursive: true });
const { memory, machine, demo } = await boot(cartPath);
const dec = new TextDecoder();
let song = null;
const step = () => {
    demo.frame(1000 / 60);
    if (demo.pollSongRequest()) song = { name: dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), tune: demo.songTune() };
};
// the display panel: its colours are neither black nor the loader ink
const isScreen = (img) => img.some((v, i) => i % 3 === 0 && v !== 0 && v !== INK[0]);
const same = (a, b) => a.every((v, i) => v === b[i]);

// ---- 1. the depack behind the TEX loader panel -------------------------------
let depackFrames = 0, last = null, shot;
for (;;) {
    step();
    shot = capture(memory, machine, demo);
    if (isScreen(shot.img)) break;
    depackFrames++;
    for (let i = 0; i < shot.img.length; i += 3) {
        const c = [shot.img[i], shot.img[i + 1], shot.img[i + 2]];
        if (!same(c, [0, 0, 0]) && !same(c, INK)) { errors.push(`depack frame ${depackFrames}: colour ${c} is not the loader ink`); break; }
    }
    if (depackFrames === 64) await writeFile(`${outDir}/union_texcopier-depack.png`, png(320, 200, shot.img));
    last = shot.img;
    if (depackFrames > 2000) { errors.push("the screen never appeared"); break; }
}
if (Math.abs(depackFrames + 1 - DEPACK_FRAMES) > 1) errors.push(`the depack took ${depackFrames} frames, its pacing says ${DEPACK_FRAMES}`);
if (last) {
    const { ink, cols } = await landedPanel();
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 80; x < 80 + 8 * (cols - 2); x++)
        if ((last[(y * 320 + x) * 3] === INK[0]) !== (ink[y * 320 + x] === 1)) wrong++;
    if (wrong) errors.push(`last depack frame: ${wrong} px of the first ${cols - 2} panel columns differ from loader.js's text`);
}

// ---- 2. the screen against the screen.js replay ------------------------------
const replay = makeReplay(await readFile(`${ASSETS}/texcopier.bin`), await readFile(`${ASSETS}/pal.dat`),
    brk === "mix" ? { mix: (a, b) => (a + b + 1) >> 1 } : brk === "period" ? { rasterPeriod: 103 } : {});
let cartMs = 0, timed = 0;
const lastShot = SHOTS[SHOTS.length - 1];
for (let f = 1; f <= lastShot; f++) {
    if (f > 1) {
        if (f === SPACE_AT) demo.key(32);
        const t0 = performance.now();
        step();
        if (f > 30) { cartMs += performance.now() - t0; timed++; }
    }
    replay.update(f === SPACE_AT);
    if (!SHOTS.includes(f)) continue;
    shot = capture(memory, machine, demo);
    if (shot.planes !== 1) errors.push(`frame ${f}: ${shot.planes} planes enabled, the screen uses one`);
    const want = replay.st();
    let wrong = 0, first = null;
    for (let i = 0; i < want.length; i += 3) if (want[i] !== shot.img[i] || want[i + 1] !== shot.img[i + 1] || want[i + 2] !== shot.img[i + 2]) {
        wrong++;
        first ??= `(${(i / 3) % 320},${Math.floor(i / 3 / 320)}) got ${[...shot.img.subarray(i, i + 3)]} want ${[...want.subarray(i, i + 3)]}`;
    }
    if (wrong) errors.push(`frame ${f}: ${wrong} px differ from the screen.js replay, first ${first}`);
    if ([1, 105, 461, 761, 1000].includes(f)) await writeFile(`${outDir}/union_texcopier-${String(f).padStart(5, "0")}.png`, png(320, 200, shot.img));
}

// ---- 3. the music ----------------------------------------------------------------
if (!song || song.name !== MUSIC || song.tune !== MUSIC_TUNE) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}" tune ${MUSIC_TUNE}`);
const music = await sndhPlay(MUSIC, MUSIC_TUNE);
if (music.why) errors.push(`${MUSIC}: ${music.why}`);
else if (music.mode !== MODE_SNDH || !(music.peak > 0.01) || music.silent || !music.volWrites.every((n) => n > 0) || music.stuckPc)
    errors.push(`${MUSIC} tune ${MUSIC_TUNE}: mode ${music.mode}, peak ${music.peak.toFixed(4)}, silent s ${music.silent}, volume writes ${music.volWrites}, stuck PC $${music.stuckPc.toString(16)}`);

// ---- 4. leaving ----------------------------------------------------------------
if (demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asks for request ${req} tag "${tag}", not 1 "union_demo"`);

// ---- 5. cost ---------------------------------------------------------------------
const perFrame = cartMs / timed;
if (perFrame > 2) errors.push(`cart update+render takes ${perFrame.toFixed(3)} ms a frame`);

if (errors.length) {
    console.error(`union_texcopier: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_texcopier: TEX loader panel over ${depackFrames} depack frames; screen.js replay (Chrome's mixes) exact at frames ${SHOTS.join(",")} ` +
    `with Space at ${SPACE_AT}; ${MUSIC} tune ${MUSIC_TUNE} requested and plays (peak ${music.peak.toFixed(4)}, 0 silent s, voices ${music.volWrites.join("/")}); ` +
    `Escape -> union_demo; ${perFrame.toFixed(3)} ms cart a frame; shots in ${outDir}`);
