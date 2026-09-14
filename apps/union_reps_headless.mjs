// Headless Union Demo REPS check (apps/zig/scenes/union_reps.zig).
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    its ink (#C0A000) must be on screen while the data depacks, the depack must
//    take the ~98 frames its pacing gives, and the screen must start when it ends.
// 2. Screen. Compared pixel for pixel with apps/union_reps_replay.mjs (screen.js
//    replayed in canvas units, then halved) at every sampled frame, with the
//    joystick held left, then right, through the run (the hold window mirrors
//    apps/zig/scenes/union_demo/controls.zig, which turns key events into held
//    keys). Any drift in a table, increment, order or rounding is wrong pixels.
// 3. Music. The cart asks for union/childrens_song.sndh, and that file plays on
//    the real audio modules: SNDH mode, no stuck PC, every second audible, all
//    three voices written.
// 4. Escape asks for the hub, and a frame leaves 60 fps headroom.
//
//   node apps/union_reps_headless.mjs [outdir] [cart.wasm] [--break raster|speed|sprites]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { ASSETS, loadAssets, makeReplay } from "./union_reps_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const SCREEN_FRAMES = [0, 1, 2, 60, 61, 200, 350, 430, 600, 800, 1234, 3000];
const HOLD = { left: [300, 420], right: [520, 720] }; // screen frames sending the direction
const DIR = { left: 2, right: 3 };
const FIRST_HOLD = 30, REPEAT_HOLD = 4; // union_demo/controls.zig
const TEX_INK = [0xc0, 0xa0, 0x00];
const MUSIC = "union/childrens_song.sndh";
const K_ESC = 0xe012;

const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at < 0 ? null : argv.splice(at, 2)[1];
if (brk !== null && !["raster", "speed", "sprites"].includes(brk)) throw new Error(`--break takes raster, speed or sprites, not ${brk}`);
const out = argv[0];
if (out) await mkdir(out, { recursive: true });
const assets = await loadAssets();
const DEPACK_FRAMES = Math.ceil((await readFile(`${ASSETS}/reps.bin`)).length / (6 * 280)); // DEPACK_BYTES_PER_LINE = 6

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
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

const { memory, machine, demo } = await boot(argv[1] || "docs/demo-union_reps.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const errors = [], dec = new TextDecoder(), warm = [];
let song = null, tune = 0, cartMs = 0, frames = 0, screenFrame = -1;

function step() {
    const t0 = performance.now();
    demo.frame(1000 / 60);
    const ms = performance.now() - t0;
    cartMs += ms; frames++;
    if (screenFrame > 1234) warm.push(ms);
    if (demo.pollSongRequest()) { song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())); tune = demo.songTune(); }
}
const screen = () => { machine.hwRenderPlane(0); return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4); };
const rgbAt = (px, x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; };
const heldDir = (f) => Object.keys(HOLD).find((k) => f >= HOLD[k][0] && f < HOLD[k][1]) ?? null;

async function png(name, px) {
    const raw = Buffer.alloc(200 * 961);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) raw.set(rgbAt(px, x, y).slice(0, 3), y * 961 + 1 + x * 3);
    const table = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = table[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => { const b = Buffer.alloc(12 + data.length); b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8); b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length); return b; };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    await writeFile(`${out}/${name}.png`, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

// 1. the loader: run until row 0 shows the screen (the panel's top rows are blank)
let inkFrames = 0, maxInk = 0, first = -1;
for (let f = 1; f <= 400 && first < 0; f++) {
    step();
    const px = screen();
    let ink = 0, row0 = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const [r, g, b, a] = rgbAt(px, x, y);
        if (a && r === TEX_INK[0] && g === TEX_INK[1] && b === TEX_INK[2]) ink++;
        if (y === 0 && a) row0++;
    }
    if (row0 === 320) first = f;
    else { if (ink) inkFrames++; if (ink > maxInk) { maxInk = ink; if (out && f > DEPACK_FRAMES - 10) await png("union_reps-loader", px); } }
}
if (first < 0) errors.push("the screen never started");
else if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);

// 2. the screen against the replay; screen frame k = k+1 updates, input sent before its frame
const rep = makeReplay(assets, brk);
const hold = [0, 0, 0, 0];
let replayed = 0;
function replayStep(f) {
    const d = heldDir(f);
    if (d) { const h = hold[DIR[d]]; hold[DIR[d]] = h === 0 ? FIRST_HOLD : Math.max(h, REPEAT_HOLD); }
    rep.step(hold[DIR.left] > 0 ? "left" : hold[DIR.right] > 0 ? "right" : null);
    for (let i = 0; i < 4; i++) hold[i] = Math.max(hold[i] - 1, 0);
}
const pal = assets.pal, seen = new Map();
screenFrame = 0;
for (const target of SCREEN_FRAMES) {
    while (screenFrame < target) { screenFrame++; const d = heldDir(screenFrame); if (d) demo.input(DIR[d]); step(); }
    while (replayed <= target) replayStep(replayed++);
    const map = rep.render(), px = screen();
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const v = map[y * 320 + x], [r, g, b, a] = rgbAt(px, x, y);
        if (a !== 255 || r !== pal[v * 4] || g !== pal[v * 4 + 1] || b !== pal[v * 4 + 2]) wrong++;
    }
    if (wrong) errors.push(`screen frame ${target}: ${wrong} px off the screen.js replay (speed ${rep.state.speed})`);
    seen.set(target, { map, speed: rep.state.speed });
    if (out && [0, 600, 1234].includes(target)) await png(`union_reps-${target}`, px);
}
const moved = (a, b, y0, y1) => seen.get(a).map.subarray(y0 * 320, y1 * 320).some((v, i) => v !== seen.get(b).map[y0 * 320 + i]);
if (!moved(60, 61, 7, 39)) errors.push("frames 60/61: the scrollers do not move");
if (!moved(60, 61, 73, 127)) errors.push("frames 60/61: the rasters or sprites do not move");
if (seen.get(430).speed !== 32 || seen.get(800).speed !== 2) errors.push(`joystick: speed ${seen.get(430).speed} after left, ${seen.get(800).speed} after right (want 32, 2)`);

// 3. music, 4. the way out and the frame cost
if (song !== MUSIC) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}"`);
else { const r = await sndhPlay(song, tune); if (typeof r === "string") errors.push(r); else song += ` (tune ${tune}, peak ${r.peak.toFixed(3)})`; }
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
const perFrame = cartMs / frames;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);
warm.sort((a, b) => a - b);

if (errors.length) {
    console.error(`union_reps: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_reps: loader depacked in ${first} frames (ink on ${inkFrames}, up to ${maxInk} px); ` +
    `screen = screen.js replay at frames ${SCREEN_FRAMES.join(",")} (joystick left then right); song ${song}; Esc -> union_demo; ` +
    `${perFrame.toFixed(3)} ms/frame mean, ${(warm[warm.length >> 1] ?? NaN).toFixed(3)} ms warm median`);
