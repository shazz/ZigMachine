// Headless Union Demo LEVEL 16 FULLSCREEN check: the loader really depacks, both
// overscan planes then match screen.js pixel for pixel, the scroller starts where
// the hub's note says, the tune plays, Escape goes home.
//
// 1. Loader. The TEX loader panel's ink (#C0A000) shows while the data depacks,
//    for the frames its pacing gives; the screen starts (song request) as it ends.
// 2. Screen. union_l16_replay.mjs replays screens/L16/screen.js from its own
//    numbers with Chrome's measured canvas resampling, on the port's grid; both
//    planes composited, over the full 800x280 overscan frame.
// 3. jsApp.mainscrollerPos. A valid note for L16's door starts the text at its
//    offset; a note for another door, or past the text, starts it at 0; the
//    note is left untouched for the hub.
// 4. The requested SNDH loads and makes sound; Escape asks for the hub; a frame
//    leaves 60 fps headroom.
//
//   node apps/union_l16_headless.mjs [outdir] [cart.wasm]
import { readFile, mkdir } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { loadAssets, makeOriginal, W, H } from "./union_l16_replay.mjs";
import { boot, songPeak, png } from "./union_l16_machine.mjs";

const ASSETS = "apps/zig/assets/screens/union_l16";
const DEPACK_FRAMES = Math.ceil(147176 / (5 * 280)); // l16.bin at DEPACK_BYTES_PER_LINE = 5
const SCREEN_FRAMES = [0, 1, 2, 3, 5, 60, 84, 85, 200, 1000, 3000];
const TEX_INK = [0xc0, 0xa0, 0x00];
const MUSIC = "union/level_16.sndh";
const L16_DOOR = 7; // TMX object 7 = doors.zig's L16_LOADER (teleport key '8')
const K_ESC = 0xe012;

const A = loadAssets(new Uint8Array(await readFile(`${ASSETS}/l16.bin`)), new Uint8Array(await readFile(`${ASSETS}/pal_picture.dat`)),
    new Uint8Array(await readFile(`${ASSETS}/pal_font.dat`)), await readFile(`${ASSETS}/curve.txt`, "latin1"),
    await readFile(`${ASSETS}/scrolltext.txt`, "latin1"));

// The note's offsets index the hub's text: L16's copy must be the hub's, which is
// the last slice of menu_assets.bin (union_demo/assets.zig bind()).
const errors = [];
{
    const mine = await readFile(`${ASSETS}/scrolltext.txt`), hub = await readFile("apps/zig/assets/screens/union_demo/menu_assets.bin");
    if (!mine.equals(hub.subarray(hub.length - mine.length)))
        errors.push(`scrolltext.txt (${mine.length} B) is not the last ${mine.length} B of union_demo/menu_assets.bin: hub note offsets would be wrong`);
}

const out = process.argv[2];
if (out) await mkdir(out, { recursive: true });
const CART = process.argv[3] || "docs/demo-union_l16.wasm";
const dec = new TextDecoder();
const at = (M) => (px, x, y) => { const o = (y * M.W + 2 * x) * 4; return [px[o], px[o + 1], px[o + 2]]; };

/// Boot and run the loader until the screen asks for its song.
async function start(note) {
    const M = await boot(CART, note);
    M.song = null; M.ms = 0; M.frames = 0; M.warm = [];
    M.step = (warm = false) => {
        const t0 = performance.now();
        M.demo.frame(1000 / 60);
        const ms = performance.now() - t0;
        M.ms += ms; M.frames++;
        if (warm) M.warm.push(ms);
        if (M.demo.pollSongRequest()) M.song = dec.decode(new Uint8Array(M.memory.buffer, M.demo.songNamePtr(), M.demo.songNameLen()));
    };
    M.inkFrames = 0; M.maxInk = 0;
    for (let f = 1; f <= 400 && M.song === null; f++) {
        M.step();
        if (M.song !== null || note !== null) continue;
        M.machine.hwRenderPlane(0);
        const px = new Uint8Array(M.memory.buffer, M.machine.hwPhysicalPtr(), M.W * M.H * 4);
        let ink = 0;
        for (let i = 0; i < px.length; i += 4) if (px[i + 3] && px[i] === TEX_INK[0] && px[i + 1] === TEX_INK[1] && px[i + 2] === TEX_INK[2]) ink++;
        if (ink) M.inkFrames++;
        if (ink > M.maxInk) { M.maxInk = ink; if (out && f > DEPACK_FRAMES - 10) await png(`${out}/union_l16-loader.png`, px.slice(), M.W / 2, M.H, at(M)); }
    }
    M.startFrame = M.song === null ? -1 : M.frames;
    return M;
}

/// Pixels of the cart's composite that differ from the replay's frame.
function wrongPixels(M, want) {
    const px = M.composite(), get = at(M);
    let wrong = 0, first = null;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const [r, g, b] = get(px, x, y), m = (y * W + x) * 3;
        if (r !== want[m] || g !== want[m + 1] || b !== want[m + 2] || px[(y * M.W + 2 * x) * 4 + 3] !== 255) {
            wrong++;
            first ??= `(${x},${y}) ${r},${g},${b} want ${want[m]},${want[m + 1]},${want[m + 2]}`;
        }
    }
    return { wrong, first, px };
}

// 1. the loader
const M = await start(null);
if (M.startFrame < 0) errors.push("the screen never started (no song request)");
else if (Math.abs(M.startFrame - DEPACK_FRAMES) > 1) errors.push(`the screen started at frame ${M.startFrame}, the depack pacing says ${DEPACK_FRAMES}`);
if (M.inkFrames < DEPACK_FRAMES / 2 || M.maxInk < 1000) errors.push(`the TEX loader panel barely showed: ink on ${M.inkFrames} frames, at most ${M.maxInk} px`);

// 2. the screen; screen frame k = the (k+1)-th update+draw, the start frame is frame 0
const st = makeOriginal(A);
const seen = new Map();
let screenFrame = 0;
for (const target of SCREEN_FRAMES) {
    while (screenFrame < target) { M.step(screenFrame > 1000); screenFrame++; }
    while (st.frames <= target) st.step();
    const want = st.draw();
    const { wrong, first, px } = wrongPixels(M, want);
    if (wrong) errors.push(`screen frame ${target}: ${wrong} px off the screen.js replay, first ${first}`);
    seen.set(target, want);
    if (out && [0, 200, 1000].includes(target)) await png(`${out}/union_l16-${target}.png`, px, W, H, at(M));
}
const differs = (a, b, x0, x1) => { for (let y = 0; y < H; y++) for (let x = x0; x < x1; x++) for (let k = 0; k < 3; k++) if (seen.get(a)[(y * W + x) * 3 + k] !== seen.get(b)[(y * W + x) * 3 + k]) return true; return false; };
if (!differs(0, 1, 360, 376)) errors.push("frames 0/1: the scroller column does not move");
if (!differs(0, 1, 162, 242)) errors.push("frames 0/1: the logo raster does not move");
if (!differs(60, 200, 0, W)) errors.push("frames 60/200: the bob does not travel");

// 3. jsApp.mainscrollerPos from the hub's note
//    Leaving rewrites a note for this door with the scroller's offset
//    (screen.js:89), keeping door and Charly's x/y; another door's note is untouched.
for (const { note, begin, rewrite } of [
    { note: { door: L16_DOOR, scroll: 500 }, begin: 500, rewrite: true },
    { note: { door: L16_DOOR + 1, scroll: 500 }, begin: 0, rewrite: false },
    { note: { door: L16_DOOR, scroll: A.text.length }, begin: 0, rewrite: true },
]) {
    const AT = 700, label = `note door ${note.door} scroll ${note.scroll}`; // 700 frames: letters wrap, the offset moves
    const N = await start(note);
    const before = N.scratch().slice(0, 20);
    for (let k = 0; k < AT; k++) N.step();
    const ref = makeOriginal(A, begin);
    while (ref.frames <= AT) ref.step();
    if (N.startFrame < 0) { errors.push(`${label}: the screen never started`); continue; }
    const { wrong } = wrongPixels(N, ref.draw());
    if (wrong) errors.push(`${label}: frame ${AT} is ${wrong} px off the replay starting the text at ${begin}`);
    N.demo.key(K_ESC);
    if (N.demo.pollCartRequest() !== 1) errors.push(`${label}: Escape did not ask for the hub`);
    const after = N.scratch();
    if (!rewrite) {
        if (after.slice(0, 20).some((b, i) => b !== before[i])) errors.push(`${label}: another door's note was changed`);
        continue;
    }
    const v = new DataView(after.buffer, after.byteOffset + 6, 14), xor = after.subarray(6, 20).reduce((a, b) => a ^ b, 0);
    const kept = dec.decode(after.subarray(0, 4)) === "UNI1" && after[4] === 14 && after[5] === xor &&
        v.getUint8(0) === note.door && v.getFloat32(2, true) === 3984 && v.getFloat32(6, true) === 127;
    if (!kept) errors.push(`${label}: the rewritten note lost its tag, checksum, door or Charly's x/y`);
    if (v.getUint32(10, true) !== ref.scroffset()) errors.push(`${label}: note scroll ${v.getUint32(10, true)}, the scroller is at ${ref.scroffset()}`);
}

// 4. music, the way out, the frame cost
let music = null;
if (M.song !== MUSIC) errors.push(`song request ${JSON.stringify(M.song)}, wanted "${MUSIC}"`);
else {
    music = await songPeak(`docs/music/${M.song}`);
    if (music.error || music.mode !== 4 || music.stuck || music.peak < 0.01) errors.push(`${M.song} does not play: ${JSON.stringify(music)}`);
}
M.demo.key(K_ESC);
const req = M.demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(M.memory.buffer, M.demo.getCartTagPtr(), M.demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Escape asked for cart request ${req} "${tag}", wanted 1 "union_demo"`);
const perFrame = M.ms / M.frames;
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);
M.warm.sort((a, b) => a - b);
const warm = M.warm.length ? M.warm[M.warm.length >> 1] : NaN;

if (errors.length) {
    console.error(`union_l16: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_l16: loader depacked in ${M.startFrame} frames (ink on ${M.inkFrames}, up to ${M.maxInk} px); ` +
    `both planes = screen.js replay at frames ${SCREEN_FRAMES.join(",")}; hub note: door ${L16_DOOR} scroll 500 starts at 500 and is rewritten with the scroller's offset, ` +
    `past the text starts at 0, another door's note starts at 0 untouched; ${M.song} plays (${music.subtunes} subtune, peak ${music.peak.toFixed(3)}, ` +
    `${music.voices} voices); Esc -> union_demo; ${perFrame.toFixed(3)} ms/frame mean, ${warm.toFixed(3)} ms warm median`);
