// Headless Union Demo TCB2 WOW!-SCROLLER check (apps/zig/scenes/union_superscroller.zig).
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    every depack frame shows only the panel's ink #C0A000 on black, the panel
//    really shows, and the depack takes the ceil(140601 / (5 * 280)) = 101 frames
//    its pacing gives. The screen starts on the frame it ends (its song request).
// 2. Screen. Frame for frame against apps/union_superscroller_replay.mjs, which
//    replays screen.js + codef_scrolltext.js with Chrome's fractional-y filtering
//    and matches the remake running in Chrome at 0 px on 29 frames (1..20, 60,
//    61, 119..121, 200, 500, 1234, 3000). Every pixel must be equal; one plane.
// 3. Music. The request is union/wow_scroller.sndh, its default tune 1, and the
//    real machine-audio + demo-audio modules play it: SNDH mode, no stuck PC,
//    every second audible.
// 4. Escape asks for the hub (tag union_demo); a warm frame fits 60 fps.
//   node apps/union_superscroller_headless.mjs [outdir] [cart.wasm] [--break speed|snap|music]
// --break must make it FAIL: the replay scrolls the letters at 8 (speed), snaps
// the back and overlay to whole rows instead of Chrome's filtering (snap), or the
// check wants another tune (music).
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeReplay } from "./union_superscroller_replay.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // the 320x200 window in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_superscroller";
const DEPACK_FRAMES = Math.ceil(140601 / (5 * 280)); // DEPACK_BYTES_PER_LINE = 5
const SHOTS = [1, 2, 3, 20, 60, 61, 119, 120, 121, 200, 500, 1234, 3000];
const TEX_INK = [0xc0, 0xa0, 0x00];
const K_ESC = 0xe012;
const MODE_SNDH = 4, SR = 44100, BLOCK = 882, SECONDS = 10;

const argv = process.argv.slice(2);
const at = argv.indexOf("--break");
const brk = at >= 0 ? argv.splice(at, 2)[1] : null;
if (brk !== null && !["speed", "snap", "music"].includes(brk)) throw new Error(`--break takes speed, snap or music, not ${brk}`);
const outDir = argv[0] || "/tmp/union_superscroller";
const cartPath = argv[1] || "docs/demo-union_superscroller.wasm";
const MUSIC = brk === "music" ? "union/thundercats.sndh" : "union/wow_scroller.sndh";

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

/// The 320x200 window as the host composites it, over black. The line palette
/// is replayed by the plane's HBL, so this renders every enabled plane.
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
    const t = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = t[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) Buffer.from(rgb.buffer, rgb.byteOffset + y * w * 3, w * 3).copy(raw, y * (w * 3 + 1) + 1);
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

/// The requested tune on the real audio modules, fed the way the worklet feeds a .sndh.
async function sndhPlay(name, tune) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { loaded: false, why: "over song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { loaded: false, why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(tune);
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < SECONDS * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { const a = Math.abs(v); peak = Math.max(peak, a); secPeak = Math.max(secPeak, a); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { loaded: true, peak, silent, mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc() };
}

const errors = [];
await mkdir(outDir, { recursive: true });
const { memory, machine, demo } = await boot(cartPath);
const dec = new TextDecoder();
let song = null;
const step = () => {
    const t0 = performance.now();
    demo.frame(1000 / 60);
    const ms = performance.now() - t0;
    if (demo.pollSongRequest()) song = { name: dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())), tune: demo.songTune() };
    return ms;
};

// ---- 1. the depack behind the TEX loader panel -------------------------------
let depackFrames = 0, maxInk = 0, shot = null;
while (!song && depackFrames <= 400) {
    step();
    depackFrames++;
    shot = capture(memory, machine, demo);
    if (song) break;
    let ink = 0;
    for (let i = 0; i < shot.img.length; i += 3) {
        const c = shot.img.subarray(i, i + 3);
        if (c[0] === TEX_INK[0] && c[1] === TEX_INK[1] && c[2] === TEX_INK[2]) ink++;
        else if (c[0] || c[1] || c[2]) { errors.push(`depack frame ${depackFrames}: colour ${[...c]} is not the loader ink`); break; }
    }
    if (ink > maxInk) { maxInk = ink; await writeFile(`${outDir}/union_superscroller-loader.png`, png(320, 200, shot.img)); }
}
if (!song) errors.push("the screen never started (no song request)");
else if (Math.abs(depackFrames - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${depackFrames}, the depack pacing says ${DEPACK_FRAMES}`);
if (maxInk < 2000) errors.push(`the TEX loader panel barely showed: at most ${maxInk} ink px`);

// ---- 2. the screen against the screen.js replay --------------------------------
// The frame the depack ends is the screen's first update+draw: replay frame 1.
const replay = makeReplay(new Uint8Array(await readFile(`${ASSETS}/superscroller.bin`)), await readFile(`${ASSETS}/scrolltext.txt`, "latin1"),
    brk === "speed" ? { speed: 8 } : brk === "snap" ? { snap: true } : {});
const warm = [];
for (let f = 1; f <= SHOTS[SHOTS.length - 1]; f++) {
    if (f > 1) { const ms = step(); if (f > 200) warm.push(ms); shot = capture(memory, machine, demo); }
    replay.step();
    if (shot.planes !== 1) errors.push(`frame ${f}: ${shot.planes} planes enabled, the screen uses one`);
    if (!SHOTS.includes(f)) continue;
    const want = replay.draw();
    let wrong = 0, first = null;
    for (let i = 0; i < want.length; i += 3) if (want[i] !== shot.img[i] || want[i + 1] !== shot.img[i + 1] || want[i + 2] !== shot.img[i + 2]) {
        wrong++;
        first ??= `(${(i / 3) % 320},${Math.floor(i / 3 / 320)}) got ${[...shot.img.subarray(i, i + 3)]} want ${[...want.subarray(i, i + 3)]}`;
    }
    if (wrong) errors.push(`frame ${f}: ${wrong} px differ from the screen.js replay, first ${first}`);
    if ([1, 61, 1234].includes(f)) await writeFile(`${outDir}/union_superscroller-${String(f).padStart(4, "0")}.png`, png(320, 200, shot.img));
}

// ---- 3. the music ----------------------------------------------------------------
if (!song || song.name !== MUSIC || song.tune !== 1) errors.push(`song request ${JSON.stringify(song)}, wanted "${MUSIC}" tune 1`);
else {
    const r = await sndhPlay(song.name, song.tune);
    if (!r.loaded) errors.push(`${song.name} not loaded: ${r.why}`);
    else if (r.mode !== MODE_SNDH || r.stuckPc || r.silent || !(r.peak > 0.01))
        errors.push(`${song.name}: mode ${r.mode}, stuck PC $${r.stuckPc.toString(16)}, ${r.silent}/${SECONDS} silent seconds, peak ${r.peak.toFixed(4)}`);
    else song.proof = `mode ${r.mode}, peak ${r.peak.toFixed(4)}, ${SECONDS} s audible, no stuck PC`;
}

// ---- 4. leaving, cost ----------------------------------------------------------
if (demo.pollCartRequest() !== 0) errors.push("the screen asks for a cart before being told to leave");
demo.key(K_ESC);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asks for request ${req} tag "${tag}", not 1 "union_demo"`);
warm.sort((a, b) => a - b);
const median = warm[warm.length >> 1], p95 = warm[Math.floor(warm.length * 0.95)];
if (!(median < 4)) errors.push(`cart update+render takes ${median?.toFixed(3)} ms a frame (median)`);

if (errors.length) {
    console.error(`union_superscroller: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_superscroller: TEX loader panel over ${depackFrames} depack frames (up to ${maxInk} ink px); ` +
    `screen.js replay exact at frames ${SHOTS.join(",")}; ${song.name} tune ${song.tune}: ${song.proof}; Escape -> union_demo; ` +
    `warm cart ${median.toFixed(3)} ms median, ${p95.toFixed(3)} ms p95 a frame; shots in ${outDir}`);
