// Headless Union Demo TNT1 (Starballs) check: apps/zig/scenes/union_tnt1.zig.
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    its ink (#C0A000) must show while the data depacks, the depack must take
//    the 72 frames its pacing gives, and the screen must start on the frame it
//    ends (row 0 all #000040).
// 2. Screen. apps/union_tnt1_replay.mjs replays screen.js, codef_bobfield.js
//    and codef_scrolltext.js from the source (not from the scene), with the same
//    xorshift32 Math.random: every sampled frame must match it pixel for pixel,
//    including after key '5' (300 balls) and key '0' (550 balls), which rebuild
//    the field from the continuing random stream. The replay itself was compared
//    with the remake running in Chrome (its header gives the numbers).
// 3. Music. The request names union/pandora.sndh, and that file, handed to the
//    real audio modules the way the worklet does, plays: SNDH mode, no stuck PC,
//    audible every second, all three voices written.
// 4. Escape asks for the hub (request 1, tag union_demo); one plane; frame cost.
// 5. The hub's note (jsApp.mainscrollerPos, screen.js:38,57,74). A note for
//    TNT1's door starts the scroller at its offset (pixel-exact against a replay
//    started there), and Escape rewrites it: door, x and y kept, scroll = the
//    replay's scroffset. A note for another door, none, or an offset past the
//    text starts at 0 and leaves the scratch bytes untouched.
//
//   node apps/union_tnt1_headless.mjs [outdir] [cart.wasm] [--break halve|passes|note]
// --break runs the replay with floor(c/2) snapping, one ballfield pass a frame,
// or ignoring the note's offset; a different cart (e.g.
// docs/demo-union_multifake.wasm) must also FAIL.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeReplay } from "./union_tnt1_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_tnt1";
const BIN_BYTES = 20016;
const DEPACK_FRAMES = Math.ceil(BIN_BYTES / (1 * 280)); // DEPACK_BYTES_PER_LINE = 1
const TEX_INK = [0xc0, 0xa0, 0x00];
const BG = [0x00, 0x00, 0x40];
const MUSIC = "union/pandora.sndh";
const MODE_SNDH = 4, SECONDS = 10, SR = 44100, BLOCK = 882;
const K_ESC = 0xe012;
// screen frame -> key pressed before it; frames compared with the replay
const KEYS = new Map([[300, "5"], [500, "0"]]);
const SHOTS = [0, 1, 2, 3, 60, 61, 200, 299, 300, 301, 420, 500, 501, 700];

const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at >= 0 ? argv.splice(at, 2)[1] : null;
if (brk !== null && !["halve", "passes", "note"].includes(brk)) throw new Error(`--break takes halve, passes or note, not ${brk}`);
const out = argv[0] || "/tmp/union_tnt1";
const cartPath = argv[1] || "docs/demo-union_tnt1.wasm";

/// `plant({ memory, rom })`, when given, runs just before the cart is inserted.
async function boot(cart, plant = null) {
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
    plant?.({ memory, rom });
    demo.skipBoot();
    return { memory, machine, demo, rom };
}

/// The requested SNDH through machine-audio + demo-audio, as the worklet plays it.
async function sndhPlay(name) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const volWrites = [0, 0, 0];
    env.machineYmWrite = (r, v) => { if (r >= 8 && r <= 10) volWrites[r - 8]++; return machine.machineYmWrite(r, v); };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { why: "over the song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(0);
    volWrites.fill(0);
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < SECONDS * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { peak = Math.max(peak, Math.abs(v)); secPeak = Math.max(secPeak, Math.abs(v)); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { peak, silent, volWrites, mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc() };
}

function png(rgb) {
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const raw = Buffer.alloc(200 * 961);
    for (let y = 0; y < 200; y++) Buffer.from(rgb.buffer, rgb.byteOffset + y * 960, 960).copy(raw, y * 961 + 1);
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

const errors = [];
await mkdir(out, { recursive: true });
const pal = new Uint8Array(await readFile(`${ASSETS}/pal.dat`));
// The scene's text is a copy of jsApp.scrolltext; the hub's blob ends with it
// (scenes/union_demo/assets.zig bind order), and the two must not drift.
const text = await readFile(`${ASSETS}/scrolltext.txt`);
const hubBlob = await readFile("apps/zig/assets/screens/union_demo/menu_assets.bin");
if (!hubBlob.subarray(hubBlob.length - text.length).equals(text)) errors.push("scrolltext.txt differs from the hub's (the end of union_demo/menu_assets.bin)");
const bin = new Uint8Array(await readFile(`${ASSETS}/tnt1.bin`));
const breakOpts = brk === "halve" ? { halve: (c) => Math.floor(c / 2) } : brk === "passes" ? { passes: 1 } : {};
/// The replay with its scroller started at `scroll` (--break note: always 0).
const replayOf = (scroll) => makeReplay(bin, text.toString("latin1"), { ...breakOpts, scroll: brk === "note" ? 0 : scroll });
const replay = replayOf(0);
const main = await boot(cartPath);
const { memory, machine, demo } = main;
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const dec = new TextDecoder();
let song = null, planes = 0;

/// The 320x200 window as RGBA, after rendering every enabled plane (one expected).
function capture(m = main) {
    const { memory, machine, demo } = m;
    machine.hwClear();
    planes = 0;
    const img = new Uint8Array(320 * 200 * 4);
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        planes++;
        machine.hwRenderPlane(p);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) img.set(px.subarray(((TOP + y) * W + LEFT + 2 * x) * 4, ((TOP + y) * W + LEFT + 2 * x) * 4 + 4), (y * 320 + x) * 4);
    }
    return img;
}
/// [pixels of `shot` that are not the replay's palette index map, the first one]
function offBy(shot, map) {
    let wrong = 0, firstWrong = null;
    for (let i = 0; i < 64000; i++) {
        const v = map[i], o = i * 4;
        if (shot[o + 3] !== 255 || shot[o] !== pal[v * 4] || shot[o + 1] !== pal[v * 4 + 1] || shot[o + 2] !== pal[v * 4 + 2]) {
            wrong++;
            firstWrong ??= `(${i % 320},${Math.floor(i / 320)}) got ${[...shot.subarray(o, o + 3)]} want index ${v}`;
        }
    }
    return [wrong, firstWrong];
}
const rgb = (img) => { const o = new Uint8Array(320 * 200 * 3); for (let i = 0; i < 64000; i++) o.set(img.subarray(i * 4, i * 4 + 3), i * 3); return o; };
function step() {
    demo.frame(1000 / 60);
    if (demo.pollSongRequest()) song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
}

// ---- 1. the loader --------------------------------------------------------------
let inkFrames = 0, maxInk = 0, first = -1, shot;
for (let f = 1; f <= 400 && first < 0; f++) {
    step();
    shot = capture();
    let ink = 0, bgRow0 = 0;
    for (let i = 0; i < 64000; i++) {
        const [r, g, b, a] = shot.subarray(i * 4, i * 4 + 4);
        if (a && r === TEX_INK[0] && g === TEX_INK[1] && b === TEX_INK[2]) ink++;
        if (i < 320 && a === 255 && r === BG[0] && g === BG[1] && b === BG[2]) bgRow0++;
    }
    if (bgRow0 === 320) first = f;
    else {
        if (ink) inkFrames++;
        if (ink > maxInk) { maxInk = ink; if (f > DEPACK_FRAMES - 8) await writeFile(`${out}/union_tnt1-loader.png`, png(rgb(shot))); }
    }
}
if (first < 0) errors.push("the screen never started");
else if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 1500) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);
if (song !== MUSIC) errors.push(`song request ${JSON.stringify(song)} when the screen started, wanted "${MUSIC}"`);

// ---- 2. the screen against the replay; screen frame k = the (k+1)-th draw() -------
let screenFrame = 0, draws = 0, map, cartMs = 0, timed = 0;
for (const target of SHOTS) {
    while (screenFrame < target) {
        screenFrame++;
        if (KEYS.has(screenFrame)) demo.key(KEYS.get(screenFrame).charCodeAt(0));
        const t0 = performance.now();
        step();
        if (screenFrame > 500) { cartMs += performance.now() - t0; timed++; }
    }
    while (draws <= target) { if (KEYS.has(draws)) replay.key(KEYS.get(draws)); map = replay.draw(); draws++; }
    shot = capture();
    if (planes !== 1) errors.push(`screen frame ${target}: ${planes} planes enabled, the screen uses one`);
    const [wrong, firstWrong] = offBy(shot, map);
    if (wrong) errors.push(`screen frame ${target}: ${wrong} px off the screen.js replay, first ${firstWrong}`);
    if ([200, 420, 700].includes(target)) await writeFile(`${out}/union_tnt1-${target}.png`, png(rgb(shot)));
}

// ---- 3. the music -----------------------------------------------------------------
const music = song === MUSIC ? await sndhPlay(song) : { why: "not requested" };
if (music.why) errors.push(`${MUSIC}: ${music.why}`);
else if (music.mode !== MODE_SNDH || music.stuckPc !== 0 || !(music.peak > 0.01) || music.silent || !music.volWrites.every((n) => n > 0))
    errors.push(`${MUSIC} does not play: mode ${music.mode}, stuck PC $${music.stuckPc.toString(16)}, peak ${music.peak.toFixed(4)}, ` +
        `${music.silent} silent s of ${SECONDS}, volume writes ${music.volWrites.join("/")}`);

// ---- 4. leaving, cost -----------------------------------------------------------------
if (demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
const perFrame = cartMs / timed;
if (!(perFrame < 2)) errors.push(`cart update+render takes ${perFrame.toFixed(3)} ms a frame with 550 balls`);

// ---- 5. the hub's note: jsApp.mainscrollerPos in and back out -----------------------
// TNT1 is doors.DOORS[4], teleport key '5': union_demo_doors_check.mjs sees it launch union_tnt1.
const TNT1_DOOR = 4, NOTE_FRAMES = 60, NOTE_SCROLL = 1000, NOTE_BYTES = 20;
function scratchOf(m) {
    if (!m.rom.romScratchPtr) throw new Error("docs/rom.wasm has no scratch bytes (romScratchPtr)");
    return new Uint8Array(m.memory.buffer, m.rom.romScratchPtr(), m.rom.romScratchLen());
}
const xorOf = (b) => b.subarray(6, NOTE_BYTES).reduce((c, e) => c ^ e, 0);
/// union_demo/return_note.zig's record: "UNI1", length 14, XOR, door, flags, x, y, scroll.
function plantNote(m, [door, x, y, scroll]) {
    const b = scratchOf(m), v = new DataView(b.buffer, b.byteOffset, NOTE_BYTES);
    b[6] = door; b[7] = 0; v.setFloat32(8, x, true); v.setFloat32(12, y, true); v.setUint32(16, scroll, true);
    b[4] = 14; b[5] = xorOf(b); b.set([0x55, 0x4e, 0x49, 0x31]); // tag last, as write() does
}
function readNote(b) {
    if (dec.decode(b.subarray(0, 4)) !== "UNI1" || b[4] !== 14 || b[5] !== xorOf(b)) return null;
    const v = new DataView(b.buffer, b.byteOffset, NOTE_BYTES);
    return { door: b[6], x: v.getFloat32(8, true), y: v.getFloat32(12, true), scroll: v.getUint32(16, true) };
}
const isBg = (shot) => { for (let x = 0; x < 320; x++) if (shot[x * 4 + 3] !== 255 || shot[x * 4] !== BG[0] || shot[x * 4 + 1] !== BG[1] || shot[x * 4 + 2] !== BG[2]) return false; return true; };
/// A fresh machine with `note` planted (null: none), screen frame NOTE_FRAMES
/// against a replay whose scroller starts at `start`, then Escape.
async function noteCase(label, note, start) {
    const m = await boot(cartPath, note && ((b) => plantNote(b, note)));
    const before = scratchOf(m).slice();
    let f = 0;
    do { m.demo.frame(1000 / 60); f++; } while (!isBg(capture(m)) && f < 400);
    for (let k = 0; k < NOTE_FRAMES; k++) m.demo.frame(1000 / 60);
    const r = replayOf(start);
    let map;
    for (let d = 0; d <= NOTE_FRAMES; d++) map = r.draw();
    const [wrong, firstWrong] = offBy(capture(m), map);
    if (wrong) errors.push(`${label}: screen frame ${NOTE_FRAMES} is ${wrong} px off the replay started at ${start}, first ${firstWrong}`);
    m.demo.key(K_ESC);
    if (m.demo.pollCartRequest() !== 1) errors.push(`${label}: Escape did not ask for the hub`);
    return { before, after: scratchOf(m).slice(), offset: r.scroffset() };
}
{ // the offset must show on screen, or the pixel checks below prove nothing
    const a = makeReplay(bin, text.toString("latin1"), { scroll: NOTE_SCROLL }), z = makeReplay(bin, text.toString("latin1"));
    let ma, mz;
    for (let d = 0; d <= NOTE_FRAMES; d++) { ma = a.draw(); mz = z.draw(); }
    if (ma.every((v, i) => v === mz[i])) errors.push(`scroll ${NOTE_SCROLL} and 0 look the same at screen frame ${NOTE_FRAMES}`);
}
const own = await noteCase("note for door 4", [TNT1_DOOR, 2650.5, 127, NOTE_SCROLL], NOTE_SCROLL);
const back = readNote(own.after);
if (!back || back.door !== TNT1_DOOR || back.x !== 2650.5 || back.y !== 127 || back.scroll !== own.offset)
    errors.push(`note for door 4: after Escape the note is ${JSON.stringify(back)}, wanted door 4, x 2650.5, y 127, scroll ${own.offset}`);
for (const [label, note] of [["note for door 8", [8, 4236, 127, NOTE_SCROLL]], ["no note", null], ["note for door 4 past the text", [TNT1_DOOR, 2650.5, 127, text.length]]]) {
    const c = await noteCase(label, note, 0);
    if (!Buffer.from(c.before).equals(Buffer.from(c.after))) errors.push(`${label}: the scratch bytes were written`);
}

if (errors.length) {
    console.error(`union_tnt1: WRONG${brk ? ` (--break ${brk})` : ""}${argv[1] ? ` (cart ${cartPath})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_tnt1: TEX loader panel over ${first} frames (ink on ${inkFrames}, up to ${maxInk} px); screen = screen.js replay at frames ${SHOTS.join(",")} ` +
    `(key 5 at 300, key 0 at 500); ${MUSIC} mode ${music.mode}, peak ${music.peak.toFixed(4)}, 0 silent s, voices ${music.volWrites.join("/")}; ` +
    `Esc -> union_demo; ${perFrame.toFixed(3)} ms/frame at 550 balls; hub note: door 4 starts at ${NOTE_SCROLL} and hands back ${own.offset}, ` +
    `door 8 / none / past the text start at 0 unwritten; shots in ${out}`);
