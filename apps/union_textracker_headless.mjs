// Headless Union Demo HIDDEN SCREEN check (apps/zig/scenes/union_textracker.zig).
//
// 1. The depack: the cart must start behind the TEX loader panel (zx0.Fx.tex_loader)
//    with screens/textracker/loader.js's own text. Every frame of it shows only
//    the loader ink #C0A000 on black, and the last one has every letter of the
//    first 18 columns landed where TEXLoader.resetScroller puts them, drawn from
//    the halved loader.png font.
// 2. The screen: frame by frame with the mouse path of apps/union_textracker_replay.mjs,
//    compared pixel for pixel with the JS replay of screen.js, which in turn matches
//    the remake running in Chrome exactly (0 px over the same 13 frames).
// 3. The music: the cart's own .zmd is in the drive (diskReadBlock, as sealed-loader.js)
//    and its stream calls reach the real machine-audio + demo-audio modules the way the
//    worklet wires them (streamStart, the 32 KiB ring at audioSongPtr, audioRender).
//    The cart must open FEEDME.RAW, feed it past its 169.6 s loop with every byte equal
//    to the file (so the wrap goes back to its first block), and the output must not
//    be silent.
// 4. Escape asks for the Union Demo menu's disk (pollCartRequest 1, tag union_demo).
// 5. A warm frame (cart update+render and hwRenderPlane) fits well inside 60 fps.
//
//   node apps/union_textracker_headless.mjs [outdir] [cart.wasm] [--break trail|blend] [--disk image.zmd]
// --break runs the replay with a wrong trail spacing (7) or a float-rounded alpha
// blend, --disk puts another disk in the drive: the check must then FAIL, which is
// how the harness proves it can.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeReplay, mouseAt, SHOTS } from "./union_textracker_replay.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const AUDIO_PAGES = 48; // machine/sdk/audio.zig
const RING = 32768; // STREAM_RING (audio-worklet-sealed.js streamFeed)
const AUDIO_RATE = 44100, FRAME_SAMPLES = AUDIO_RATE / 60;
const TOP = 40, LEFT = 80; // the 320x200 window in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_textracker";
const PANEL = `${ASSETS}/loader_textracker.txt`;
const MUSIC_FILE = "FEEDME.RAW", MUSIC_RATE = 12517;
const INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012;

const argv = process.argv.slice(2);
function flag(name, allowed) {
    const at = argv.indexOf(name);
    if (at < 0) return null;
    const v = argv[at + 1];
    if (!v || (allowed && !allowed.includes(v))) throw new Error(`${name} takes ${allowed ? allowed.join(" or ") : "a value"}, not ${v}`);
    argv.splice(at, 2);
    return v;
}
const brk = flag("--break", ["trail", "blend"]);
const diskPath = flag("--disk") || "docs/demo-union_textracker.zmd";
const outDir = argv[0] || "/tmp/union_textracker";
const cartPath = argv[1] || "docs/demo-union_textracker.wasm";

/// A FAT entry off a ZigMachine disk image (v2 descriptor at $400, else v1 at $000).
function findFile(disk, name) {
    const dv = new DataView(disk.buffer, disk.byteOffset, disk.byteLength);
    const magic = (off) => new TextDecoder().decode(disk.subarray(off, off + 6)) === "ZMDISK";
    const [count, fat] = magic(0x400) ? [dv.getUint16(0x4f4, true), 0x800] : magic(0) ? [dv.getUint16(0x2e4, true), 0x300] : [0, 0];
    for (let i = 0; i < count; i++) {
        const e = fat + i * 32, raw = disk.subarray(e, e + 16);
        const n = new TextDecoder().decode(raw.subarray(0, raw.indexOf(0) < 0 ? 16 : raw.indexOf(0)));
        if (n === name) return { start: dv.getUint32(e + 0x10, true), len: dv.getUint32(e + 0x14, true) };
    }
    return null;
}

/// machine-audio + demo-audio over their own memory, fed like the worklet feeds them.
async function makeAudio(file) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const demo = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    demo.audioInit();
    const a = { started: false, rate: 0, ringWrite: 0, fed: 0, mismatch: -1, peak: 0, samples: 0 };
    a.start = (rate) => { demo.audioStreamStart(rate); a.rate = rate; a.ringWrite = 0; a.started = true; };
    a.stop = () => { demo.audioStreamStop(); a.started = false; };
    a.feed = (bytes) => {
        const ring = new Uint8Array(memory.buffer, demo.audioSongPtr(), RING);
        for (const b of bytes) {
            // the stream must be the file, byte for byte, wrapping to its start
            if (file && a.mismatch < 0 && b !== file.bytes[a.fed % file.len]) a.mismatch = a.fed;
            a.fed++;
            ring[a.ringWrite] = b;
            a.ringWrite = (a.ringWrite + 1) % RING;
        }
    };
    a.render = () => {
        if (!a.started) return;
        demo.audioRender(FRAME_SAMPLES);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), FRAME_SAMPLES)) a.peak = Math.max(a.peak, Math.abs(v));
        a.samples += FRAME_SAMPLES;
    };
    return a;
}

async function boot(cart, disk, audio, reads) {
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
    const env = {
        memory, ...rom,
        // the drive, as sealed-loader.js's diskReadBlock: one 512-byte block into shared RAM
        diskReadBlock: (block, dstOff) => {
            const src = disk.subarray(block * 512, block * 512 + 512);
            if (src.length === 0) return 0;
            new Uint8Array(memory.buffer, dstOff, src.length).set(src);
            reads.push(block);
            return src.length;
        },
        hostAudioStreamStart: (rate) => audio.start(rate),
        hostAudioFeed: (ptr, len) => audio.feed(new Uint8Array(memory.buffer, ptr, len)),
        hostAudioStreamStop: () => audio.stop(),
    };
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

/// The loader panel with every letter landed: row r's top at 8 + 8r, column c at 80 + 8c
/// (TEXLoader.resetScroller: x 168 + 16c, y 376 - 16*rows_below, midhandled, halved).
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

const errors = [];
await mkdir(outDir, { recursive: true });
const disk = new Uint8Array(await readFile(diskPath));
const entry = findFile(disk, MUSIC_FILE);
if (!entry) errors.push(`${MUSIC_FILE} is not on ${diskPath}`);
const file = entry && { ...entry, bytes: disk.subarray(entry.start, entry.start + entry.len) };
const audio = await makeAudio(file);
const reads = [];
const { memory, machine, demo } = await boot(cartPath, disk, audio, reads);
const step = () => { demo.frame(1000 / 60); audio.render(); };
const replay = makeReplay(await readFile(`${ASSETS}/screen.raw`), await readFile(`${ASSETS}/pal.dat`),
    brk === "trail" ? { trailStep: 7 } : brk === "blend" ? { mix: (s, d) => Math.round(s * 0.9 + d * 0.1) } : {});
const isMenu = (img) => { let n = 0; for (let i = 0; i < img.length; i += 3) if (img[i] === 224 && img[i + 1] === 224 && img[i + 2] === 224) n++; return n > 1000; };
const same = (a, b) => a.every((v, i) => v === b[i]);

// ---- 1. the depack behind the TEX loader panel -------------------------------
demo.pointer(...mouseAt(1), 0);
let depackFrames = 0, last = null, shot;
for (;;) {
    step();
    shot = capture(memory, machine, demo);
    if (isMenu(shot.img)) break;
    depackFrames++;
    for (let i = 0; i < shot.img.length; i += 3) {
        const c = [shot.img[i], shot.img[i + 1], shot.img[i + 2]];
        if (!same(c, [0, 0, 0]) && !same(c, INK)) { errors.push(`depack frame ${depackFrames}: colour ${c} is not the loader ink`); break; }
    }
    if (depackFrames === 58) await writeFile(`${outDir}/union_textracker-depack.png`, png(320, 200, shot.img));
    last = shot.img;
    if (depackFrames > 2000) { errors.push("the screen never appeared"); break; }
}
if (depackFrames < 30) errors.push(`the depack took ${depackFrames} frames: no TEX loader panel to speak of`);
if (last) {
    const { ink, cols } = await landedPanel();
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 80; x < 80 + 8 * (cols - 2); x++) {
        const lit = last[(y * 320 + x) * 3] === INK[0];
        if (lit !== (ink[y * 320 + x] === 1)) wrong++;
    }
    if (wrong) errors.push(`last depack frame: ${wrong} px of the first ${cols - 2} panel columns differ from loader.js's text`);
}

// ---- 2. the screen against the screen.js replay ------------------------------
let cartMs = 0, renderMs = 0, timed = 0;
const lastShot = SHOTS[SHOTS.length - 1];
for (let f = 1; f <= lastShot; f++) {
    if (f > 1) {
        demo.pointer(...mouseAt(f), 0);
        const t0 = performance.now();
        demo.frame(1000 / 60);
        const t1 = performance.now();
        audio.render();
        shot = capture(memory, machine, demo);
        if (f > 30) { cartMs += t1 - t0; renderMs += performance.now() - t1; timed++; }
    }
    if (shot.planes !== 1) errors.push(`frame ${f}: ${shot.planes} planes enabled, the screen uses one`);
    if (!SHOTS.includes(f)) continue;
    const want = replay(f);
    let wrong = 0, first = null;
    for (let i = 0; i < want.length; i += 3) if (want[i] !== shot.img[i] || want[i + 1] !== shot.img[i + 1] || want[i + 2] !== shot.img[i + 2]) {
        wrong++;
        first ??= `(${(i / 3) % 320},${Math.floor(i / 3 / 320)}) got ${[...shot.img.subarray(i, i + 3)]} want ${[...want.subarray(i, i + 3)]}`;
    }
    if (wrong) errors.push(`frame ${f}: ${wrong} px differ from the screen.js replay, first ${first}`);
    await writeFile(`${outDir}/union_textracker-${String(f).padStart(4, "0")}.png`, png(320, 200, shot.img));
}

// ---- 3. the music, played past its loop -----------------------------------------
const PAST_LOOP = 10 * MUSIC_RATE; // 10 s beyond the file's end
const fileBlock = (b) => entry && b * 512 >= entry.start && b * 512 < entry.start + entry.len;
let musicFrames = 0;
while (entry && audio.fed < entry.len + PAST_LOOP && musicFrames < 13000) { step(); musicFrames++; }
const firstBlock = entry ? Math.floor(entry.start / 512) : -1;
const fileReads = reads.filter(fileBlock);
const lastBlock = entry ? Math.floor((entry.start + entry.len - 1) / 512) : -1;
const endAt = fileReads.indexOf(lastBlock);
const wrapped = endAt >= 0 && fileReads.indexOf(firstBlock, endAt) > endAt;
if (entry && fileReads.length === 0) errors.push(`the cart never read ${MUSIC_FILE} (blocks ${firstBlock}..${lastBlock})`);
if (audio.rate !== MUSIC_RATE) errors.push(`the stream started at ${audio.rate} Hz, not ${MUSIC_RATE}`);
if (entry && audio.fed <= entry.len) errors.push(`only ${audio.fed} of ${entry.len} bytes fed: the loop was never reached`);
if (entry && !wrapped) errors.push(`after block ${lastBlock} the cart never went back to ${MUSIC_FILE}'s first block ${firstBlock}`);
if (audio.mismatch >= 0) errors.push(`fed byte ${audio.mismatch} differs from ${MUSIC_FILE} at offset ${audio.mismatch % entry.len}`);
if (!(audio.peak > 0.01)) errors.push(`the output is silent (peak ${audio.peak.toFixed(4)})`);

// ---- 4. leaving ----------------------------------------------------------------
if (demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asks for request ${req} tag "${tag}", not 1 "union_demo"`);
if (audio.started) errors.push("Escape left the stream playing");

// ---- 5. cost ---------------------------------------------------------------------
const perFrame = cartMs / timed, perRender = renderMs / timed;
if (perFrame > 2) errors.push(`cart update+render takes ${perFrame.toFixed(3)} ms a frame`);

if (errors.length) {
    console.error(`union_textracker: WRONG${brk ? ` (--break ${brk})` : ""}${diskPath !== "docs/demo-union_textracker.zmd" ? ` (--disk ${diskPath})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_textracker: TEX loader panel over ${depackFrames} depack frames; screen.js replay exact at frames ${SHOTS.join(",")}; ` +
    `${MUSIC_FILE} (${entry.len} B, blocks ${firstBlock}..${lastBlock}) off ${diskPath}: fed ${audio.fed} B = ${(audio.fed / MUSIC_RATE).toFixed(1)} s ` +
    `byte-exact, looped at ${(entry.len / MUSIC_RATE).toFixed(1)} s back to block ${firstBlock}, ${(audio.samples / AUDIO_RATE).toFixed(1)} s rendered, peak ${audio.peak.toFixed(4)}; ` +
    `Escape -> union_demo, stream stopped; warm ${perFrame.toFixed(3)} ms cart + ${perRender.toFixed(3)} ms hwRenderPlane a frame; shots in ${outDir}`);
