// Headless Union Demo TNT3 check: the loader really depacks, then the screen
// matches the remake's own screen.js, pixel for pixel, through every object.
//
// 1. Loader. The cart starts on the TEX loader panel (depack fx = tex_loader):
//    its ink (#C0A000) must show while the data depacks, the depack must take
//    the ~82 frames its pacing gives, and the screen must start when it ends.
// 2. Screen. apps/union_tnt3_replay.mjs runs screens/tnt3/screen.js itself, on
//    the remake's codef_core.js, codef_3d_v2.js (three.js r49) and
//    codef_scrolltext_updown.js, over a mock canvas that halves the way the
//    scene documents. Both get the same keys on the same frames (every object,
//    then ESC), and every sampled frame must be identical: any drift in a
//    vertex, a matrix, the culling, the sort, the overdraw, the timing of a
//    change or the scroller shows up as wrong pixels.
// 3. The hub is asked for on the very frame screen.js calls
//    me.state.change(MENU_LOADER), and not before; the song request names the
//    SNDH, which plays (non-silent, no stuck PC); a frame leaves 60 fps headroom.
//
// The remake is not in git (prototypes/): without it, step 2 is SKIPPED, said
// so on the FITS line, and the hub is only required after ESC.
//
//   node apps/union_tnt3_headless.mjs [outdir] [cart.wasm] [--remake DIR] [--break overdraw|ball]
// --break replays a deliberately wrong screen.js / three.js (union_tnt3_replay.mjs
// BREAKS): the check must then FAIL, which proves it can tell a wrong port.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { performance } from "node:perf_hooks";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeRemake, findRemake } from "./union_tnt3_replay.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const AUDIO_PAGES = 48; // AUDIO_PAGES in machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // ST (0,0) in the physical frame (x doubled)
const DEPACK_FRAMES = Math.ceil(68608 / (3 * 280)); // DEPACK_BYTES_PER_LINE = 3
const TEX_INK = [0xc0, 0xa0, 0x00];
// the tune is the scene's one constant pair: read it rather than repeat it
const SCENE = readFileSync("apps/zig/scenes/union_tnt3.zig", "utf8");
const MUSIC = /^const MUSIC = "([^"]+)";/m.exec(SCENE)?.[1];
const MUSIC_TUNE = +(/^const MUSIC_TUNE = (\d+);/m.exec(SCENE)?.[1] ?? NaN);
if (!MUSIC || !Number.isInteger(MUSIC_TUNE)) throw new Error("union_tnt3.zig: MUSIC / MUSIC_TUNE not found");
const K_ESC = 0xe012;
const ESC_FRAME = 1480;

const argv = process.argv.slice(2);
const flag = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv.splice(i, 2)[1] : null; };
const remakeArg = flag("--remake");
const brk = flag("--break");
const REMAKE_DIR = findRemake(remakeArg);
if (remakeArg && !REMAKE_DIR) throw new Error(`--remake ${remakeArg}: no screens/tnt3/screen.js there`);
if (brk && !REMAKE_DIR) throw new Error("--break needs the remake (prototypes/ or --remake DIR)");
// screen frame -> [cart key, the melonJS action screen.js tests]
const KEYS = new Map([[300, ["3", "3"]], [520, ["4", "4"]], [760, ["5", "5"]], [1000, ["1", "1"]], [1240, ["2", "2"]], [ESC_FRAME, [K_ESC, "exit"]]]);
// frames 25-300 TNT, 425-500 ball, 625-750 glider, 875-1000 carrier, 1125-1225
// Union logo, 1350-1475 TNT again; the others catch changes and the scroller
const SHOTS = [0, 1, 69, 70, 71, 185, 190, 200, 330, 425, 480, 625, 700, 900, 950, 1125, 1200, 1350, 1450, 1520, 1570];
const PNG_SHOTS = [200, 480, 700, 950, 1200, 1450];
const LAST = 1700;

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

/// 10 s of the tune on the sealed audio machine: peak, silent seconds, stuck PC.
async function sndhPlay(name, tune) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { why: "over song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(tune);
    let peak = 0, secPeak = 0, silent = 0;
    for (let block = 1; block <= 500; block++) {
        audio.audioRender(882);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), 882)) secPeak = Math.max(secPeak, Math.abs(v));
        if (block % 50 === 0) { peak = Math.max(peak, secPeak); if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { peak, silent, stuckPc: audio.audioSndhStuckPc() };
}

const out = argv[0];
if (out) await mkdir(out, { recursive: true });
const { memory, machine, demo } = await boot(argv[1] || "docs/demo-union_tnt3.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const errors = [];
const dec = new TextDecoder();
let song = null, tune = 0, cartMs = 0, frames = 0, hubAt = -1;
let screenFrame = -1; // -1 while the loader runs
const warm = [];

function step() {
    const t0 = performance.now();
    demo.frame(1000 / 60);
    const ms = performance.now() - t0;
    cartMs += ms;
    frames++;
    if (screenFrame > 200) warm.push(ms);
    if (demo.pollSongRequest()) {
        song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
        tune = demo.songTune();
    }
    if (screenFrame >= 0 && hubAt < 0 && demo.pollCartRequest() === 1) {
        const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
        if (tag !== "union_demo") errors.push(`asked for cart "${tag}", wanted "union_demo"`);
        hubAt = screenFrame + 1;
    }
}
function screen() {
    machine.hwRenderPlane(0);
    return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
}
const rgbAt = (px, x, y) => { const o = ((y + TOP) * W + LEFT + x * 2) * 4; return [px[o], px[o + 1], px[o + 2], px[o + 3]]; };

async function png(name, rgb) {
    const raw = Buffer.alloc(200 * 961);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) raw.set(rgb(x, y), y * 961 + 1 + x * 3);
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
    else if (ink) {
        inkFrames++;
        if (ink > maxInk) { maxInk = ink; if (out && f > DEPACK_FRAMES - 10) await png("union_tnt3-loader", (x, y) => rgbAt(px, x, y).slice(0, 3)); }
    }
}
if (first < 0) errors.push("the screen never started");
else if (Math.abs(first - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${first}, the depack pacing says ${DEPACK_FRAMES}`);
if (inkFrames < DEPACK_FRAMES / 2 || maxInk < 2000) errors.push(`the TEX loader panel barely showed: ink on ${inkFrames} frames, at most ${maxInk} px`);

// 2. the screen against screen.js; screen frame k = the (k+1)-th update() + draw()
const remake = REMAKE_DIR ? makeRemake(REMAKE_DIR, brk) : null;
let remakeLeft = -1, compared = 0, objectPx = 0;
const OBJECT_BG = new Set([0x000000, 0x606060, 0xa0a0a0, 0xe0e0e0, 0xe00000]); // stars and scroller
remake?.frame(); // screen frame 0 (the cart ran it on the depack's last frame)
screenFrame = 0;
while (screenFrame <= LAST && first >= 0) {
    if (remake && SHOTS.includes(screenFrame)) {
        const want = remake.shot(), px = screen();
        let wrong = 0;
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const v = want[y * 320 + x], [r, g, b, a] = rgbAt(px, x, y);
            if (a !== 255 || r !== v >> 16 || g !== ((v >> 8) & 255) || b !== (v & 255)) wrong++;
            if (y >= 9 && !OBJECT_BG.has(v)) objectPx++;
        }
        compared++;
        if (wrong) errors.push(`screen frame ${screenFrame}: ${wrong} px off the screen.js replay`);
        if (out && PNG_SHOTS.includes(screenFrame)) {
            await png(`union_tnt3-${screenFrame}`, (x, y) => rgbAt(px, x, y).slice(0, 3));
            await png(`union_tnt3-${screenFrame}-remake`, (x, y) => { const v = want[y * 320 + x]; return [v >> 16, (v >> 8) & 255, v & 255]; });
        }
    }
    if (hubAt >= 0 || remakeLeft >= 0) break;
    const k = KEYS.get(screenFrame + 1);
    if (k) demo.key(typeof k[0] === "string" ? k[0].charCodeAt(0) : k[0]);
    step();
    screenFrame++;
    if (!remake) continue;
    remake.frame(k ? [k[1]] : []);
    if (remake.state.left && remakeLeft < 0) remakeLeft = screenFrame;
}
if (remake) {
    if (compared < SHOTS.length) errors.push(`compared ${compared} of ${SHOTS.length} frames: the screen ended early`);
    if (objectPx < 50000) errors.push(`only ${objectPx} object pixels over the compared frames: nothing was really tested`);
}

// 3. the way out, music, frame cost
if (!remake) {
    if (hubAt <= ESC_FRAME) errors.push(`the hub was asked for at screen frame ${hubAt}, not after ESC at ${ESC_FRAME}`);
} else if (remakeLeft < 0) errors.push("screen.js never left: the key schedule is wrong");
else if (hubAt !== remakeLeft) errors.push(`the hub was asked for at screen frame ${hubAt}, screen.js leaves at ${remakeLeft}`);
if (song !== MUSIC || tune !== MUSIC_TUNE) errors.push(`song request ${JSON.stringify(song)} #${tune}, wanted "${MUSIC}" #${MUSIC_TUNE}`);
else {
    const r = await sndhPlay(song, tune);
    if (r.why) errors.push(`${song}: ${r.why}`);
    else if (r.peak <= 0.01 || r.silent > 1 || r.stuckPc) errors.push(`${song} #${tune}: peak ${r.peak.toFixed(4)}, ${r.silent} silent s, stuck PC ${r.stuckPc}`);
    else song += ` #${tune} (peak ${r.peak.toFixed(3)})`;
}
const perFrame = cartMs / frames;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);
warm.sort((a, b) => a - b);

if (errors.length) {
    console.error(`union_tnt3: WRONG${brk ? ` (--break ${brk})` : ""}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
const replayed = remake
    ? `screen = screen.js + three.js r49 replay at ${compared} frames through all five objects; ESC -> union_demo at frame ${hubAt} as screen.js`
    : `screen.js comparison SKIPPED (no ${"prototypes/oldies"} remake); ESC -> union_demo at frame ${hubAt}`;
console.log(`union_tnt3: FITS loader depacked in ${first} frames (ink on ${inkFrames}, up to ${maxInk} px); ${replayed}; ` +
    `song ${song}; ${perFrame.toFixed(3)} ms/frame mean, ${warm[warm.length >> 1].toFixed(3)} ms warm median`);
