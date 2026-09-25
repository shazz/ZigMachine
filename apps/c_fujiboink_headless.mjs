// Headless FUJIBOINK! (C cart) driver: boots the sealed machine +
// docs/demo-c-fujiboink.wasm the way docs/sealed-loader.js does and checks it
// against the REAL THING, FUJIBOIN.PRG run in Hatari (TOS 1.62, 1 MB ST) on the
// FUJIBOIN.D8A its own generators made:
//   frames    nine Hatari screenshots (apps/c/assets/screens/fujiboink/hatari/):
//             the title over the rainbow fuji, the fade to "FujiBoink!", the
//             fall, front and back views across the screen, the commercial a
//             key brings back. Six are the machine's frame pixel for pixel. In
//             three the ST ran the NEXT iteration's C code while the beam was
//             still drawing (a scrollkolors() or a Setcolor() of the same view
//             lands mid-frame), so the part below that line is one VBL ahead:
//             a sliver the per-VBL machine does not show, bounded here.
//             Each must also match better than the frames either side of it.
//   rasters   the rainbow is REAL: the plane's index buffer holds only the 16 ST
//             registers' indices, the face is index 4/5 on the fuji's lines,
//             and palette entry 4 changes from line to line inside one frame
//             (Timer B's 72 lines and its 73rd), written by the plane's HBL.
//   sound     the thud is requested on the frame the fuji hits the floor,
//             and the SNDH it asks for decays like the original's envelope.
//   keys      a function key freezes the fuji until the next key; Space and
//             Escape leave for the menu, and Space stops the sound.
//
// Hatari's screenshot is the last frame it RENDERED, which in fast-forward lags
// run_frames' VBL counter by a few frames: each capture's frame was found once by
// searching (the cart is deterministic) and is pinned below. Offsets 365..371.
//
//   node apps/c_fujiboink_headless.mjs [outdir] [--break rasters|thud]
// --break SABOTAGES one measurement and passes only if its check notices.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { boot, stFrame, hatariFrame, same, OFF_PAL, REG_FB_BASE } from "./c_fujiboink_machine.mjs";

const CART = "docs/demo-c-fujiboink.wasm";
const REFS = "apps/c/assets/screens/fujiboink/hatari/";
const THUD = "fujiboink_thud.sndh";
const K_ESC = 0xe012, K_F1 = 0xe001, KEY_X = 0x78, SPACE = 0x20;
const KEY_FRAME = 979; // Hatari: 'x' pressed at VBL 1347, the capture of cart frame 979
const INTRO = 51, FIRST_THUD = 368; // a title frame; boink's iteration 40 (p hit 40 in 39)
// [screenshot, cart frame, least fraction of identical pixels, what]
const SHOTS = [
    ["vbl0416", 51, 1, "title over the rainbow fuji (intro)"],
    ["vbl0700", 331, 1, "the title fading to red and white"],
    ["vbl0720", 349, 1, "the straight fall; 'FujiBoink!' is what plane 0 kept"],
    ["vbl0721", 355, 0.98, "the straight fall; below line 120 the ST had run the next scrollkolors()"],
    ["vbl0900", 529, 0.999, "back view, far right; a Setcolor(BARSIDE) sliver from the next iteration"],
    ["vbl1037", 667, 1, "back view, top left"],
    ["vbl1287", 919, 0.998, "over 'FujiBoink!'; a Setcolor(BARSIDE) sliver"],
    ["vbl1347", 979, 1, "front view, far right, the face in the back colour (fflag)"],
    ["advert_vbl3190", 2821, 1, "the commercial the key brought back at iteration 2320"],
];

const args = process.argv.slice(2);
const bi = args.indexOf("--break");
const broke = bi >= 0 ? args[bi + 1] : "";
if (bi >= 0 && !["rasters", "thud"].includes(broke)) throw new Error(`--break ${broke}: rasters or thud`);
const out = args.filter((a, i) => !a.startsWith("--") && !(bi >= 0 && i === bi + 1))[0] ?? "/tmp/c_fujiboink";
let failures = 0;
function check(name, ok, detail = "") {
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}${detail ? ": " + detail : ""}`);
}

// A running cart, recording per line of the last frame the palette entries 4..7
// the plane's HBL left, and every song request with its frame.
async function run() {
    const s = { frames: 0, songs: [], lines: [], request: 0 };
    const hbl = (demo, id, p, l, x) => {
        if (broke !== "rasters") demo.hblDispatch(id, p, l, x); // --break: the handler never runs
        const pal = new Uint32Array(s.memory.buffer, s.machine.hwVideoBase() + OFF_PAL, 8);
        s.lines[l] = pal[4];
    };
    Object.assign(s, await boot(CART, hbl));
    s.step = (n = 1) => {
        for (let i = 0; i < n; i++) {
            s.machine.hwClear();
            s.demo.frame(1000 / 60);
            s.frames++;
            if (s.demo.pollSongRequest()) {
                const name = new TextDecoder().decode(
                    new Uint8Array(s.memory.buffer, s.demo.songNamePtr(), s.demo.songNameLen()));
                if (!(broke === "thud" && name === THUD)) s.songs.push([s.frames, name]); // --break: lost
            }
            s.request = s.demo.pollCartRequest();
            s.machine.hwRenderPlane(0);
        }
        return stFrame(s.memory, s.machine);
    };
    // The index buffer on screen (the plane's FB_BASE): one ST colour index a pixel.
    s.indices = () => {
        const base = s.machine.hwVideoBase();
        const fb = new Uint32Array(s.memory.buffer, base + REG_FB_BASE, 1)[0];
        return new Uint8Array(s.memory.buffer, base + fb, 64000).slice();
    };
    return s;
}

async function ppm(path, f) {
    const h = Buffer.from("P6\n320 200\n255\n"), b = Buffer.alloc(h.length + 64000 * 3);
    h.copy(b);
    let o = h.length;
    for (const c of f) { b[o++] = ((c >> 8) & 7) * 36; b[o++] = ((c >> 4) & 7) * 36; b[o++] = (c & 7) * 36; }
    await writeFile(path, b);
}

async function checkFrames() {
    const s = await run();
    let prev = null;
    for (const [name, frame, min, what] of SHOTS) {
        const ref = await hatariFrame(`${REFS}${name}.png`);
        while (s.frames < frame - 1) {
            if (s.frames === KEY_FRAME - 1) s.demo.key(KEY_X);
            prev = s.step();
        }
        if (s.frames === KEY_FRAME - 1) s.demo.key(KEY_X);
        const got = s.step(), after = s.step();
        const m = same(got, ref), b = same(prev, ref), a = same(after, ref);
        check(`${name} = frame ${frame}, ${what}`, m >= min && m > b && m > a,
            `${(m * 100).toFixed(3)}% identical (>= ${min * 100}), frame before ${(b * 100).toFixed(2)}%, after ${(a * 100).toFixed(2)}%`);
        await ppm(`${out}/${m >= min ? "" : "MISMATCH-"}${name}.ppm`, got);
        prev = after;
    }
}

// The rainbow is palette writes, not pixels.
async function checkRasters() {
    const s = await run();
    s.step(INTRO); // fujiy = 15, view 25, front: 73 raster lines 15..87
    const idx = s.indices();
    check("every pixel is one of the 16 ST colour registers (no pixel carries a raster colour)",
        idx.every((v) => v < 16));
    let faceRows = 0;
    for (let y = 15; y < 15 + 72; y++) {
        const row = idx.subarray(y * 320, y * 320 + 320);
        if (row.some((v) => v === 4 || v === 5)) faceRows++;
    }
    check("the face is index 4/5 on the fuji's lines", faceRows >= 60, `${faceRows} of 72 lines`);
    const inFuji = new Set(s.lines.slice(15, 15 + 73)), above = new Set(s.lines.slice(0, 15));
    check("palette entry 4 is rewritten line by line inside the frame (Timer B)", inFuji.size >= 60,
        `${inFuji.size} colours over the 73 lines, ${above.size} above the fuji`);
    check("above the fuji entry 4 is the VBL's one colour (kolbak)", above.size === 1);
}

// The thud: requested as the fuji lands, and the SNDH decays.
async function checkSound() {
    const s = await run();
    let lowest = -1, top = [];
    for (let f = 1; f <= FIRST_THUD; f++) {
        s.step();
        const idx = s.indices();
        let t = 200;
        for (let i = 0; i < 64000 && t === 200; i++) if (idx[i] >= 4) t = (i / 320) | 0; // face/sides, not grid or shadow
        top[f] = t;
    }
    const first = s.songs.find(([, n]) => n === THUD);
    // boom is set when p reaches 40; the next iteration draws the fuji at p = 40
    // (y = 15 + 110 = 125, the floor) and only then calls thud().
    check(`the first thud is requested at frame ${FIRST_THUD}, the frame the fuji hits the floor`,
        !!first && first[0] === FIRST_THUD && top[FIRST_THUD] === 125 && top[FIRST_THUD - 1] < 125,
        first ? `frame ${first[0]}, fuji top ${top[FIRST_THUD - 1]} -> ${top[FIRST_THUD]}` : "never");
    check("nothing is requested before it (the original has no music)", s.songs.length === (first ? 1 : 0),
        JSON.stringify(s.songs));

    const r = await sndhRender(THUD);
    check("the thud SNDH loads and plays on the sealed YM", !r.why && r.attack > 0.05, r.why || `peak ${r.attack.toFixed(3)} in the first 0.1 s`);
    check("...and dies away like envelope shape 0 over ~0.5 s", !r.why && r.tail < r.attack * 0.05,
        r.why || `peak ${r.tail.toFixed(4)} from 0.7 s to 1 s`);
}

// One second of an SNDH on the sealed audio machine: the peak in the first
// 0.1 s, and from 0.7 s to 1 s.
async function sndhRender(name) {
    const AUDIO_PAGES = 48; // AUDIO_PAGES in machine/sdk
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(0);
    let attack = 0, tail = 0;
    for (let b = 0; b < 50; b++) { // 50 x 882 samples = 1 s
        audio.audioRender(882);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 882)) {
            if (b < 5) attack = Math.max(attack, Math.abs(v));
            if (b >= 35) tail = Math.max(tail, Math.abs(v));
        }
    }
    if (audio.audioSndhStuckPc()) return { why: `stuck at PC ${audio.audioSndhStuckPc()}` };
    return { attack, tail };
}

async function checkKeys() {
    const s = await run();
    s.step(500);
    s.demo.key(K_F1); // a key with no ASCII: Bconin(2)&255 == 0
    s.step(2);
    const frozen = s.step();
    s.step(30);
    check("a function key freezes the fuji", same(s.step(), frozen) === 1);
    s.demo.key(0x61); // 'a' releases it
    s.step(3);
    check("...until the next key", same(s.step(), frozen) < 1);
    s.demo.key(SPACE);
    s.step();
    check("Space leaves for the menu (pollCartRequest -1)", s.request === -1, `got ${s.request}`);
    check("...and stops the sound (soundoff)", s.songs.at(-1)?.[1] === "none", JSON.stringify(s.songs.at(-1)));

    const e = await run();
    e.step(100);
    e.demo.key(K_ESC);
    e.step();
    check("Escape leaves for the menu too", e.request === -1, `got ${e.request}`);
}

await mkdir(out, { recursive: true });
await checkFrames();
await checkRasters();
await checkSound();
await checkKeys();

if (broke) {
    const ok = failures > 0;
    console.log(ok ? `\nc_fujiboink: PASS (--break ${broke} was caught)` : `\nc_fujiboink: FAILED — --break ${broke} was not caught`);
    process.exit(ok ? 0 : 1);
}
console.log(failures ? `\nc_fujiboink: ${failures} FAILED` : `\nc_fujiboink: PASS (frames in ${out})`);
process.exit(failures ? 1 : 0);
