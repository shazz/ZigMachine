// Headless Union Demo REPS check (apps/zig/scenes/union_reps.zig).
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    its ink (#C0A000) must be on screen while the data depacks, the depack must
//    take the ~98 frames its pacing gives, and the screen must start when it ends.
// 2. Screen. Compared pixel for pixel with apps/union_reps_replay.mjs (screen.js
//    replayed in canvas units, then halved) at every sampled frame, with the
//    joystick held left, then right (press + inputRelease), through the run. Any
//    drift in a table, increment, order or rounding is wrong pixels.
//    The BORDER too: the bars are colour 0 changed per scanline, so every border
//    pixel of visible line y must be the replay's colour 0 on that line (and the
//    top and bottom borders black). Frames run as the host runs them: hwClear
//    (the global HBL paints the border) BEFORE the cart's frame, so a border
//    table one frame late shows here as wrong border pixels.
// 3. jsApp.mainscrollerPos. The run boots with the hub's ROM-scratch note for the
//    REPS door (return_note.zig layout) saying scroll 500: the scrollers must start
//    at character 500, the note must be untouched while the screen runs (REPS
//    peeks, the hub spends it), and Escape must write it back with the same door
//    and Charly position and scroll = the blue scroller's offset (screen.js:179).
//    A note for another door and one past the text's end must start at 0 and
//    leave the scratch as it was, Escape included.
// 4. Music. The cart asks for union/childrens_song.sndh, and that file plays on the
//    real audio modules: SNDH mode, no stuck PC, every second audible, all voices.
// 5. Escape asks for the hub, and a frame leaves 60 fps headroom.
//
//   node apps/union_reps_headless.mjs [outdir] [cart.wasm] [--break raster|speed|sprites|note]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { ASSETS, loadAssets, makeReplay } from "./union_reps_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const BLACK = 1; // union_reps/assets.zig: maincanvas.fill('#000000')
const SCREEN_FRAMES = [0, 1, 2, 60, 61, 200, 350, 430, 600, 800, 1234, 3000];
const HOLDS = [{ dir: 2, name: "left", from: 300, to: 420 }, { dir: 3, name: "right", from: 520, to: 720 }];
const REPS_DOOR = 5; // doors.zig DOORS (TMX order): REPS_LOADER is object 5
const NOTE_SCROLL = 500;
const TEX_INK = [0xc0, 0xa0, 0x00];
const MUSIC = "union/childrens_song.sndh";
const K_ESC = 0xe012;

const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at < 0 ? null : argv.splice(at, 2)[1];
if (brk !== null && !["raster", "speed", "sprites", "note"].includes(brk)) throw new Error(`--break takes raster, speed, sprites or note, not ${brk}`);
const out = argv[0], CART = argv[1] || "docs/demo-union_reps.wasm";
if (out) await mkdir(out, { recursive: true });
const assets = await loadAssets();
const { pal } = assets;
const MASK_INK = 98; // union_reps/assets.zig: the mask's register, which no image may use
if ((await readFile(`${ASSETS}/reps.bin`)).some((p) => p >= MASK_INK)) throw new Error(`reps.bin uses index ${MASK_INK} or above: the mask's raster register would recolour it`);
const DEPACK_FRAMES = Math.ceil((await readFile(`${ASSETS}/reps.bin`)).length / (6 * 280)); // DEPACK_BYTES_PER_LINE = 6
const dec = new TextDecoder();

/// The hub's note (apps/zig/scenes/union_demo/return_note.zig): "UNI1", len 14, XOR, payload.
function writeNote(bytes, { door, scroll }) {
    const p = new DataView(bytes.buffer, bytes.byteOffset + 6, 14);
    p.setUint8(0, door); p.setUint8(1, 0);
    p.setFloat32(2, 3008, true); p.setFloat32(6, 127, true); p.setUint32(10, scroll, true);
    bytes[4] = 14;
    bytes[5] = bytes.subarray(6, 20).reduce((c, b) => c ^ b, 0);
    bytes.set([..."UNI1"].map((c) => c.charCodeAt(0)), 0);
}

async function boot(note) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(CART);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    const scratch = new Uint8Array(memory.buffer, rom.romScratchPtr(), rom.romScratchLen());
    if (note) writeNote(scratch, note); // left by the hub before it swapped this cart in
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, scratch };
}

async function sndhPlay(name, tune, seconds = 5, SR = 44100, BLOCK = 882) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const volWrites = [0, 0, 0];
    env.machineYmWrite = (r, v) => { if (r >= 8 && r <= 10) volWrites[r - 8]++; return machine.machineYmWrite(r, v); };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return `${name} is over the song capacity`;
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return `audioLoadSndh refused ${name}`;
    audio.audioSndhPlay(tune);
    volWrites.fill(0);
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < seconds * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { peak = Math.max(peak, Math.abs(v)); secPeak = Math.max(secPeak, Math.abs(v)); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    const r = { mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc(), peak, silent, volWrites };
    const ok = r.mode === 4 && r.stuckPc === 0 && peak > 0.01 && silent === 0 && volWrites.every((n) => n > 0);
    return ok ? r : `${name} does not play: ${JSON.stringify(r)}`;
}

async function png(name, px, W) {
    const rgbAt = (x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2]]; };
    const raw = Buffer.alloc(200 * 961);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) raw.set(rgbAt(x, y), y * 961 + 1 + x * 3);
    const table = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = table[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => { const b = Buffer.alloc(12 + data.length); b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8); b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length); return b; };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    await writeFile(`${out}/${name}.png`, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

/// Boot with `note`, run the loader, then compare `frames` against the replay started at `offset`.
async function run({ note, offset, frames, holds = [], main = false }) {
    const m = await boot(note);
    const W = m.machine.hwPhysWidth(), H = m.machine.hwPhysHeight();
    const noteBefore = m.scratch.slice(0, 20);
    const errors = [], warm = [], seen = new Map();
    let song = null, tune = 0, cartMs = 0, steps = 0, screenFrame = -1;
    const step = () => {
        m.machine.hwClear(); // the host's order: the border, then the cart's frame
        const t0 = performance.now();
        m.demo.frame(1000 / 60);
        const ms = performance.now() - t0;
        cartMs += ms; steps++;
        if (screenFrame > 1234) warm.push(ms);
        if (m.demo.pollSongRequest()) { song = dec.decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())); tune = m.demo.songTune(); }
    };
    const screen = () => { m.machine.hwRenderPlane(0); return new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), W * H * 4); };
    const px4 = (px, x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; };

    // the loader: run until row 0 shows the screen (the panel's top rows are blank)
    let inkFrames = 0, maxInk = 0, first = -1;
    for (let f = 1; f <= 400 && first < 0; f++) {
        step();
        const px = screen();
        let ink = 0, row0 = 0;
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const [r, g, b, a] = px4(px, x, y);
            if (a && r === TEX_INK[0] && g === TEX_INK[1] && b === TEX_INK[2]) ink++;
            if (y === 0 && a) row0++;
        }
        if (row0 === 320) first = f;
        else { if (ink) inkFrames++; if (ink > maxInk) { maxInk = ink; if (out && main && f > DEPACK_FRAMES - 10) await png("union_reps-loader", px, W); } }
    }
    if (first < 0) return { errors: ["the screen never started"] };
    if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
    if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);

    // screen frame k = the (k+1)-th update. A hold is what a browser host sends: a
    // press before frame `from`, auto-repeats every 2 frames (~33 ms) while down,
    // and the key-up before frame `to`. Without the repeats, controls.zig rightly
    // treats a lone press on a host that has not yet sent a key-up as a tap.
    const rep = makeReplay(assets, brk === "note" ? null : brk, offset);
    let replayed = 0;
    screenFrame = 0;
    for (const target of frames) {
        while (screenFrame < target) {
            screenFrame++;
            for (const h of holds) {
                if (screenFrame >= h.from && screenFrame < h.to && (screenFrame - h.from) % 2 === 0) m.demo.input(h.dir);
                if (screenFrame === h.to) m.demo.inputRelease(h.dir);
            }
            step();
        }
        for (; replayed <= target; replayed++) rep.step(holds.find((h) => replayed >= h.from && replayed < h.to)?.name ?? null);
        const map = rep.render(), px = screen();
        let wrong = 0;
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const v = map[y * 320 + x], [r, g, b, a] = px4(px, x, y);
            if (a !== 255 || r !== pal[v * 4] || g !== pal[v * 4 + 1] || b !== pal[v * 4 + 2]) wrong++;
        }
        if (wrong) errors.push(`screen frame ${target}: ${wrong} px off the screen.js replay (scroll from ${offset}, speed ${rep.state.speed})`);
        // Screen frame 0 is the frame the depack ends on: its border was painted (hwClear)
        // while the loader still ran, so the rasters own the border from frame 1.
        const bg = rep.border(), black = pal.subarray(BLACK * 4, BLACK * 4 + 3);
        let wrongBorder = 0;
        for (let y = 0; y < H; y++) {
            const want = y >= TOP && y < TOP + 200 ? pal.subarray(bg[y - TOP] * 4, bg[y - TOP] * 4 + 3) : black;
            for (let x = 0; x < W; x++) {
                if (y >= TOP && y < TOP + 200 && x >= LEFT && x < LEFT + 640) continue;
                const o = (y * W + x) * 4;
                if (px[o] !== want[0] || px[o + 1] !== want[1] || px[o + 2] !== want[2] || px[o + 3] !== 255) wrongBorder++;
            }
        }
        if (wrongBorder && target > 0) errors.push(`screen frame ${target}: ${wrongBorder} border px are not that line's colour 0`);
        seen.set(target, { map, speed: rep.state.speed });
        if (out && main && [0, 600, 1234].includes(target)) await png(`union_reps-${target}`, px, W);
    }
    const untouched = () => m.scratch.slice(0, 20).every((b, i) => b === noteBefore[i]);
    if (!untouched()) errors.push("the hub's note changed while the screen ran: REPS must only peek at it");
    // Escape: me.state.change(MENU_LOADER) with jsApp.mainscrollerPos = scrolltextBlue.scroffset
    m.demo.key(K_ESC);
    const req = m.demo.pollCartRequest();
    const tag = dec.decode(new Uint8Array(m.memory.buffer, m.demo.getCartTagPtr(), m.demo.getCartTagLen()));
    if (req !== 1 || tag !== "union_demo") errors.push(`Escape asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
    if (main) {
        const v = new DataView(m.scratch.buffer, m.scratch.byteOffset, 20);
        const back = { tag: dec.decode(m.scratch.subarray(0, 4)), door: v.getUint8(6), x: v.getFloat32(8, true), y: v.getFloat32(12, true), scroll: v.getUint32(16, true) };
        const xor = m.scratch.subarray(6, 20).reduce((c, b) => c ^ b, 0);
        const want = { tag: "UNI1", door: note.door, x: 3008, y: 127, scroll: rep.blueOffset() };
        if (JSON.stringify(back) !== JSON.stringify(want) || v.getUint8(4) !== 14 || v.getUint8(5) !== xor)
            errors.push(`after Escape the note is ${JSON.stringify(back)}, wanted ${JSON.stringify(want)} with a valid header`);
    } else if (!untouched()) errors.push("a rejected note was written back on Escape");
    return { errors, seen, song, tune, first, inkFrames, maxInk, perFrame: cartMs / steps, warm: warm.sort((a, b) => a - b), blue: rep.blueOffset() };
}

const main = await run({ note: { door: REPS_DOOR, scroll: NOTE_SCROLL }, offset: brk === "note" ? 0 : NOTE_SCROLL, frames: SCREEN_FRAMES, holds: HOLDS, main: true });
const errors = [...main.errors];
if (main.seen) {
    const moved = (a, b, y0, y1) => main.seen.get(a).map.subarray(y0 * 320, y1 * 320).some((v, i) => v !== main.seen.get(b).map[y0 * 320 + i]);
    if (!moved(60, 61, 7, 39)) errors.push("frames 60/61: the scrollers do not move");
    if (!moved(60, 61, 73, 127)) errors.push("frames 60/61: the rasters or sprites do not move");
    if (main.seen.get(430).speed !== 32 || main.seen.get(800).speed !== 2) errors.push(`joystick: speed ${main.seen.get(430).speed} after left, ${main.seen.get(800).speed} after right (want 32, 2)`);
}
// a stale note (another door) and an out-of-range scroll both start the text at 0
for (const [why, note] of [["door 8's note", { door: 8, scroll: NOTE_SCROLL }], ["scroll past the text", { door: REPS_DOOR, scroll: assets.text.length }]]) {
    const r = await run({ note, offset: 0, frames: [200] });
    errors.push(...r.errors.map((e) => `${why}: ${e}`));
}

let song = main.song;
if (song !== MUSIC) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}"`);
else { const r = await sndhPlay(song, main.tune); if (typeof r === "string") errors.push(r); else song += ` (tune ${main.tune}, peak ${r.peak.toFixed(3)})`; }
if (main.perFrame > 4) errors.push(`cart takes ${main.perFrame.toFixed(3)} ms/frame`);

if (errors.length) {
    console.error(`union_reps: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_reps: loader depacked in ${main.first} frames (ink on ${main.inkFrames}, up to ${main.maxInk} px); ` +
    `screen = screen.js replay at frames ${SCREEN_FRAMES.join(",")} (scroll from the hub's note, ${NOTE_SCROLL}; joystick left then right); ` +
    `note peeked, written back on Esc with scroll ${main.blue}; other door / out-of-range note -> 0, no write; song ${song}; Esc -> union_demo; ` +
    `${main.perFrame.toFixed(3)} ms/frame mean, ${(main.warm[main.warm.length >> 1] ?? NaN).toFixed(3)} ms warm median`);
