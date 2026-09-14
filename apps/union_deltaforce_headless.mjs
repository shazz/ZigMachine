// Headless Union Demo DELTA FORCE check (apps/zig/scenes/union_deltaforce.zig).
//
// 1. Loader. The cart starts behind the TEX loader panel (depack fx = tex_loader):
//    the panel's ink (#C0A000) is on screen while the data depacks, the depack
//    takes the 96 frames its pacing gives, and the screen starts the frame it ends.
// 2. Screen. apps/union_deltaforce_replay.mjs replays screen.js in lockstep with
//    the cart, both fed the same YM volume registers every frame (written where
//    the host mirrors them, getYmRegsPointer). The frames compared pixel for pixel
//    are the fixed ones below plus the screen's own events as the replay reaches
//    them: the logo swap, the credits band handing over to the scroller, every
//    kind of scroller effect (INVERSE, REVERSE, GLOBAL, NONE), and the RESET that
//    restarts the screen, twice: the second pass must scroll again (the port's
//    deliberate loop; the remake as written never scrolls after its first RESET).
// 3. Music. The song request names the SNDH, and that file really plays on the
//    sealed YM through the real audio modules: SNDH mode, no silent second, all
//    three voices writing their volume.
// 4. Escape and Space each ask for the hub; a warm frame leaves 60 fps headroom.
//
//   node apps/union_deltaforce_headless.mjs [outdir] [cart.wasm] [--break gold|twist|wave|voices|reset]
// --break gets one number of the replay wrong: the check must then FAIL, which is
// how it proves it can. A broken cart passed as cart.wasm must fail it too.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { loadAssets, makeReplay, regsAt, FX_NAMES } from "./union_deltaforce_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const DEPACK_FRAMES = Math.ceil(186774 / (7 * 280)); // DEPACK_BYTES_PER_LINE = 7
const TEX_INK = [0xc0, 0xa0, 0x00];
const MUSIC = "union/mega_apocalypse.sndh";
const MODE_SNDH = 4;
const K_ESC = 0xe012;
const FIXED = [0, 1, 2, 45, 46, 60, 100, 300, 777];
const FOLLOW = [0, 1, 10, 40]; // frames after an event that are compared too
const SHOT_EVENTS = new Set(["intro stop", "outro starts +10", "INVERSE +10", "GLOBAL_SINEWAVE +10", "RESET #2 +40"]);

const argv = process.argv.slice(2);
const brkAt = argv.indexOf("--break");
const brk = brkAt >= 0 ? argv.splice(brkAt, 2)[1] : null;
if (brk && !["gold", "twist", "wave", "voices", "reset"].includes(brk)) throw new Error(`--break ${brk}?`);
const out = argv[0];
const cartPath = argv[1] || "docs/demo-union_deltaforce.wasm";
if (out) await mkdir(out, { recursive: true });

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

/// The requested SNDH on the real audio modules, the way the worklet plays one.
async function sndhPlays(name) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const volWrites = [0, 0, 0];
    env.machineYmWrite = (r, v) => {
        if (r >= 8 && r <= 10) volWrites[r - 8]++;
        return machine.machineYmWrite(r, v);
    };
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return `${name} is over the song capacity`;
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return "audioLoadSndh refused it";
    audio.audioSndhPlay(1);
    volWrites.fill(0);
    const SR = 44100, BLOCK = 882, SECONDS = 10;
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < SECONDS * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) {
            peak = Math.max(peak, Math.abs(v));
            secPeak = Math.max(secPeak, Math.abs(v));
        }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    const summary = `mode ${audio.audioMode()}, peak ${peak.toFixed(3)}, ${silent} silent s, volume writes ${volWrites.join("/")}`;
    const ok = audio.audioMode() === MODE_SNDH && peak > 0.01 && silent === 0 && volWrites.every((n) => n > 0);
    return ok ? { summary } : `${name} does not play: ${summary}`;
}

const { memory, machine, demo } = await boot(cartPath);
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const errors = [];
const dec = new TextDecoder();
let song = null, cartMs = 0, frames = 0;
const warm = [];

function writeRegs(frame) {
    const regs = new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 16);
    regs.set(regsAt(frame), 8);
}
function step(screenFrame) {
    const t0 = performance.now();
    demo.frame(1000 / 60);
    const ms = performance.now() - t0;
    cartMs += ms;
    frames++;
    if (screenFrame > 1000) warm.push(ms);
    if (demo.pollSongRequest()) song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
}
function screen() {
    machine.hwRenderPlane(0);
    return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
}
const rgbaAt = (px, x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; };

async function png(name, px) {
    const raw = Buffer.alloc(200 * (1 + 320 * 3));
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) raw.set(rgbaAt(px, x, y).slice(0, 3), y * 961 + 1 + x * 3);
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    await writeFile(`${out}/${name}.png`, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

// 1. the loader: YM registers stay 0 (regsAt(0)) until the screen has started
writeRegs(0);
let inkFrames = 0, maxInk = 0, first = -1;
for (let f = 1; f <= 400 && first < 0; f++) {
    step(-1);
    const px = screen();
    let ink = 0, row0 = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const [r, g, b, a] = rgbaAt(px, x, y);
        if (a && r === TEX_INK[0] && g === TEX_INK[1] && b === TEX_INK[2]) ink++;
        if (y === 0 && a) row0++;
    }
    if (row0 === 320) first = f;
    else {
        if (ink) inkFrames++;
        if (ink > maxInk) { maxInk = ink; if (out && f > DEPACK_FRAMES - 10) await png("union_deltaforce-loader", px); }
    }
}
if (first < 0) errors.push("the screen never started");
else if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);

// 2. the screen in lockstep with the replay; the loader's last frame was screen frame 0
const A = loadAssets();
const rp = makeReplay(A, brk);
const planned = new Map(FIXED.map((f) => [f, `frame ${f}`]));
const seen = { fx: new Map(), time: new Map(), flips: 0 };
const shots = {};
let compared = 0, wrongFrames = 0, resets = 0, end = Infinity, renderMs = 0;

function plan(k, reason) {
    for (const d of FOLLOW) if (!planned.has(k + d)) planned.set(k + d, d ? `${reason} +${d}` : reason);
}
async function compare(k, reason, px) {
    const map = rp.draw(true);
    let wrong = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const [r, g, b, a] = rgbaAt(px, x, y), o = (y * 320 + x) * 3;
        if (a !== 255 || r !== map[o] || g !== map[o + 1] || b !== map[o + 2]) wrong++;
    }
    compared++;
    if (wrong) { wrongFrames++; if (errors.length < 12) errors.push(`screen frame ${k} (${reason}): ${wrong} px off the screen.js replay`); }
    if (out && SHOT_EVENTS.has(reason) && !(reason in shots)) { shots[reason] = k; await png(`union_deltaforce-${k}`, px); }
}

let handovers = 0; // credits band gone and the scroller alone: once per pass
for (let k = 0; first >= 0 && k <= end && k < 40000; k++) {
    if (k > 0) { writeRegs(k); step(k); }
    const before = { time: rp.introTime, fx: rp.fx, tile: rp.logoTile, speed: rp.speed };
    rp.update(regsAt(k));
    if (rp.logoTile !== before.tile && seen.flips++ < 2) plan(k, "logo swap");
    if (rp.introTime === 2 && before.time !== 2 && handovers++ === 1) plan(k, "second pass scrolls");
    if (rp.introTime !== before.time && !seen.time.has(rp.introTime)) { seen.time.set(rp.introTime, k); plan(k, rp.introTime === 1 ? "outro starts" : "credits gone"); }
    if (rp.speed !== before.speed && !planned.has(k)) planned.set(k, "intro stop");
    if (rp.fx !== before.fx) {
        const n = (seen.fx.get(rp.fx) ?? 0) + 1;
        seen.fx.set(rp.fx, n);
        if (n <= 2) plan(k, FX_NAMES[rp.fx]);
    }
    const resetting = (rp.introTime === 1 || rp.introTime === 2) && FX_NAMES[rp.fx] === "RESET"; // this draw() resets
    if (resetting) { resets++; plan(k, `RESET #${resets}`); if (resets === 2) end = k + 60; }
    const reason = planned.get(k);
    if (reason === undefined) { rp.draw(false); continue; }
    const t0 = performance.now();
    const px = screen();
    renderMs += performance.now() - t0;
    await compare(k, reason, px);
}
if (resets < 2) errors.push(`the scroller's RESET was reached ${resets} times, wanted 2`);
if (handovers < 2) errors.push(`the scroller ran alone ${handovers} times before the second RESET, wanted 2 (the loop)`);
for (const fx of ["INVERSE", "REVERSE", "GLOBAL_SINEWAVE", "NO_EFFECT", "RESET"])
    if (![...seen.fx.keys()].some((v) => FX_NAMES[v] === fx)) errors.push(`the text never switched to ${fx}`);

// 3. music
if (song !== MUSIC) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}"`);
const music = await sndhPlays(MUSIC);
if (typeof music === "string") errors.push(music);

// 4. the way out, the frame cost
for (const [what, press] of [["Escape", () => demo.key(K_ESC)], ["Space", () => demo.key(0x20)]]) {
    press();
    const req = demo.pollCartRequest();
    const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
    if (req !== 1 || tag !== "union_demo") errors.push(`${what} asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
}
const perFrame = cartMs / frames;
warm.sort((a, b) => a - b);
const warmMedian = warm.length ? warm[warm.length >> 1] : NaN;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);
if (out) await writeFile(`${out}/union_deltaforce-shots.json`, JSON.stringify(shots, null, 1));

if (errors.length) {
    console.error(`union_deltaforce: WRONG${brk ? ` (replay broken on purpose: ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_deltaforce: loader depacked in ${first} frames (ink on ${inkFrames}, up to ${maxInk} px); ` +
    `screen = screen.js replay on ${compared} frames up to ${end} (2 RESETs); song ${song} (${music.summary}); ` +
    `Esc and Space -> union_demo; ${perFrame.toFixed(3)} ms/frame mean, ${warmMedian.toFixed(3)} ms warm median, ` +
    `${(renderMs / Math.max(compared, 1)).toFixed(3)} ms hwRenderPlane`);
