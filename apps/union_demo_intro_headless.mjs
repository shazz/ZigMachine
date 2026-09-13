// Headless UNION DEMO INTRO check (melonJS remake, screens/intro/screen.js).
//
// Nothing errors when this screen goes wrong: a wrong increment, a row/column
// swap in the letter sway, a lost half-pixel in the background or the rasters
// shifted by a row all still draw something plausible. So:
//   1. the graphics depack behind the TEX loader panel (fx tex_loader): the
//      panel's ink is on screen mid-way, and the screen starts in ~100 frames;
//   2. screen.js is replayed here in canvas units, update() then draw(), with
//      its own numbers (bgposy += 3 wrapping at 0, logoInc 0.008, logosin1 0.08,
//      sinletters 0.06 with the 0.3 running phases, 70/136 and 32/16), halved
//      by the rules the scene documents, and every one of the 64,000 pixels of
//      the plane must equal it at each sampled frame;
//   3. consecutive frames move (background 1.5 px, letters, logo);
//   4. the screen asks for ikari_union.sndh, Space boots union_demo;
//   5. a frame leaves 60 fps headroom.
//
//   node apps/union_demo_intro_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40, LEFT = 80; // the visible window in the physical frame (x doubled)
const ASSETS = "apps/zig/assets/screens/union_demo_intro/";
const FRAMES = [1, 2, 3, 32, 33, 61, 300, 301, 1000, 1001];
const TEX_INK = [0xc0, 0xa0, 0x00];
const out = process.argv[2];

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

// ---- screen.js, replayed ----------------------------------------------------
const blob = await readFile(`${ASSETS}intro.bin`);
const pal = await readFile(`${ASSETS}intro_pal.dat`);
const BG_EVEN = 0, BG_ODD = 320 * 48, LOGO = 2 * 320 * 48, FONT = LOGO + 64 * 32, INK = FONT + 256 * 112;
if (blob.length !== INK + 128) throw new Error(`intro.bin is ${blob.length} bytes`);

function original() {
    const s = { n: 0, bgposy: -96, logosin1: 0, logoInc: 0, sinlettersx: 0, sinlettersy: 0, oldsinx: 0, oldsiny: 0 };
    s.update = () => { // screen.js:81-97
        s.n++;
        s.logoInc += 0.008;
        if ((s.bgposy += 3) >= 0) s.bgposy = -96;
        s.logosin1 += 0.08;
        s.sinlettersx = s.oldsinx + 0.06;
        s.sinlettersy = s.oldsiny + 0.06;
    };
    s.draw = () => { // screen.js:104-139, into an ST index map
        const map = new Uint8Array(320 * 200);
        for (let r = 0; r < 200; r++) {
            const t = (((2 * r - s.bgposy) % 96) + 96) % 96; // bg2 tile rows t, t+1 under canvas rows 2r, 2r+1
            const src = t % 2 === 0 ? BG_EVEN + (t / 2) * 320 : BG_ODD + ((t - 1) / 2) * 320;
            map.set(blob.subarray(src, src + 320), r * 320);
        }
        const x = 320 + Math.sin(s.logosin1) * (170 * Math.sin(s.logoInc)) - 64; // setmidhandle: 128/2
        const lx = Math.floor(Math.round(x) / 2), ly = (38 - 32) / 2;
        for (let y = 0; y < 32; y++) for (let c = 0; c < 64; c++) {
            const v = blob[LOGO + y * 64 + c], px = lx + c;
            if (v && px >= 0 && px < 320) map[(ly + y) * 320 + px] = v;
        }
        s.oldsinx = s.sinlettersx;
        s.oldsiny = s.sinlettersy;
        let countl = 0;
        for (let y = 0; y < 224; y += 16) {
            for (let xx = 0; xx < 512; xx += 32) {
                const nb = countl++;
                const X = 70 + xx + Math.sin(s.sinlettersx) * 32, Y = 136 + y + Math.sin(s.sinlettersy) * 16;
                const tx = (nb % 16) * 16, ty = Math.floor(nb / 16) * 8, sx = Math.round(X / 2), sy = Math.round(Y / 2);
                for (let gy = 0; gy < 8; gy++) for (let gx = 0; gx < 16; gx++) {
                    if (!blob[FONT + (ty + gy) * 256 + tx + gx]) continue;
                    const inkRow = sy + gy - 60;
                    if (inkRow < 0 || inkRow >= 128) throw new Error(`letter row ${sy + gy} outside the rasters`);
                    map[(sy + gy) * 320 + sx + gx] = blob[INK + inkRow];
                }
                s.sinlettersy += 0.3;
            }
            s.sinlettersy = s.oldsiny;
            s.sinlettersx += 0.3;
        }
        return map;
    };
    return s;
}

// ---- the cart ------------------------------------------------------------------
function window320(px, W) {
    const rgba = new Uint8Array(320 * 200 * 4);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++)
        rgba.set(px.subarray(((y + TOP) * W + LEFT + x * 2) * 4, ((y + TOP) * W + LEFT + x * 2) * 4 + 4), (y * 320 + x) * 4);
    return rgba;
}
function compare(rgba, map) {
    let wrong = 0, first = null;
    for (let i = 0; i < 64000; i++) {
        const v = map[i], o = i * 4;
        if (rgba[o + 3] !== 255 || rgba[o] !== pal[v * 4] || rgba[o + 1] !== pal[v * 4 + 1] || rgba[o + 2] !== pal[v * 4 + 2]) {
            wrong++;
            first ??= `(${i % 320},${Math.floor(i / 320)})`;
        }
    }
    return { wrong, first };
}
function crc32(buf) {
    let c, crc = 0xffffffff;
    for (const b of buf) { c = (crc ^ b) & 0xff; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1; crc = (crc >>> 8) ^ c; }
    return (crc ^ 0xffffffff) >>> 0;
}
function png(rgba, w, h) {
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "ascii"); data.copy(b, 8);
        b.writeUInt32BE(crc32(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const raw = Buffer.alloc((w * 4 + 1) * h);
    for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-union_intro_screen.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const shot = () => { machine.hwRenderPlane(0); return window320(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4), W); };
const errors = [];
if (out) await mkdir(out, { recursive: true });
const dec = new TextDecoder();
let song = null;
const pollSong = () => { if (demo.pollSongRequest()) song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())); };

// 1. the depack: nothing loads before the remake's introScreen, so no loader
//    panel may show, and the screen starts at once. The first frame after the
//    depack is the first update()+draw() of screen.js.
const inkPixels = (rgba) => { let k = 0; for (let i = 0; i < 64000; i++) if (rgba[i * 4] === TEX_INK[0] && rgba[i * 4 + 1] === TEX_INK[1] && rgba[i * 4 + 2] === TEX_INK[2]) k++; return k; };
let depackFrames = 0, panelInk = 0;
for (;;) {
    demo.frame(1000 / 60);
    pollSong();
    const rgba = shot();
    panelInk += inkPixels(rgba);
    if (song) break; // the screen has started
    depackFrames++;
    if (depackFrames > 10) { errors.push("the screen never started after 10 frames"); break; }
}
const midInk = panelInk;
if (panelInk > 0) errors.push(`a TEX loader panel shows before the intro (${panelInk} ink px); nothing loads before introScreen`);
if (depackFrames > 2) errors.push(`depack took ${depackFrames} frames; the intro opens at once`);
if (song !== "ikari_union.sndh") errors.push(`song request ${song}, not ikari_union.sndh`);

// 2-3. the screen, frame by frame against the replay (screen frame 1 is already on the plane)
const st = original();
const seen = new Map();
let cartMs = 0, rgba = shot();
while (st.n < FRAMES.at(-1)) {
    if (st.n > 0) { const t0 = performance.now(); demo.frame(1000 / 60); cartMs += performance.now() - t0; rgba = shot(); }
    st.update();
    const map = st.draw(); // every frame: the letter phases run on from draw() to draw()
    if (!FRAMES.includes(st.n)) continue;
    const { wrong, first } = compare(rgba, map);
    if (wrong) errors.push(`frame ${st.n}: ${wrong} px off the screen.js replay (first at ${first})`);
    seen.set(st.n, { rgba: rgba.slice(), bg: st.bgposy });
    if (out && [61, 301].includes(st.n)) await writeFile(`${out}/union_intro-${st.n}.png`, png(rgba, 320, 200));
}
const moved = (a, b) => seen.get(a).rgba.some((v, i) => v !== seen.get(b).rgba[i]);
if (!moved(32, 33) || !moved(300, 301)) errors.push("consecutive frames are identical: nothing moves");
if (seen.get(32).bg !== -96 || seen.get(33).bg !== -93) errors.push(`bgposy at 32/33 is ${seen.get(32).bg}/${seen.get(33).bg}, not -96/-93`);

// 4. Space: FIRST_LOADER's panel (demoloader.js) assembles, 140 ms of tween
//    clock a frame; Space before every letter lands is ignored; after, it boots
//    union_demo. The landed panel must hold exactly its glyphs' ink.
const PANEL = (await readFile(`${ASSETS}loader_demo.txt`, "utf8")).split("\n").filter((l) => l.startsWith('"')).map((l) => l.slice(1, l.lastIndexOf('"')));
const FONT_RAW = await readFile("libs/zig/depackers/tex_loader/loader.raw"); // 80x48, 10 glyphs a row of 8x8
const glyphInk = (c) => { const g = c.charCodeAt(0) - 0x20; let n = 0; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) n += FONT_RAW[((Math.floor(g / 10) * 8 + y) * 80) + (g % 10) * 8 + x]; return n; };
const expectedInk = PANEL.join("").split("").reduce((n, c) => n + glyphInk(c), 0);
const LANDED_MS = (PANEL.length * PANEL[0].length - 1) * 30 + 50; // tex_loader timelineEnd
const landedTicks = Math.ceil(LANDED_MS / 140);
demo.key(32);
if (demo.pollCartRequest() !== 0) errors.push("Space on the intro left at once; FIRST_LOADER's panel must come first");
let creditsMid = 0, creditsFrames = 0;
for (let f = 1; f <= landedTicks; f++) {
    demo.frame(1000 / 60);
    creditsFrames = f;
    const r = shot();
    if (f === 2 && inkPixels(r) !== 0) errors.push("the credits panel does not start on black");
    if (f === 60) { creditsMid = inkPixels(r); if (out) await writeFile(`${out}/union_intro-credits-60.png`, png(r, 320, 200)); }
    if (f === landedTicks - 1) {
        demo.key(32);
        if (demo.pollCartRequest() !== 0) errors.push(`Space at panel frame ${f} left before every letter landed`);
    }
}
demo.frame(1000 / 60);
const landed = shot();
const landedInk = inkPixels(landed);
if (out) await writeFile(`${out}/union_intro-credits-landed.png`, png(landed, 320, 200));
if (!(creditsMid > 0 && creditsMid < landedInk)) errors.push(`the credits panel does not assemble (${creditsMid} ink px at frame 60, ${landedInk} landed)`);
if (landedInk !== expectedInk) errors.push(`the landed credits panel has ${landedInk} ink px, its glyphs ${expectedInk}`);
demo.key(32);
const req = demo.pollCartRequest();
const tag = dec.decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
if (req !== 1 || tag !== "union_demo") errors.push(`Space on the landed panel asks for cart ${req} "${tag}", not 1 "union_demo"`);

// 5. budget
const perFrame = cartMs / (FRAMES.at(-1) - 1);
if (perFrame > 4) errors.push(`cart takes ${perFrame.toFixed(3)} ms/frame`);

// 6. the requested SNDH plays on the real audio modules (its own 68000 code driving the YM)
async function sndhPeak(name) {
    const mem = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // AUDIO_PAGES
    const chip = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
    const env = { memory: mem };
    for (const k of Object.keys(chip)) if (k.startsWith("machine")) env[k] = chip[k];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const tune = new Uint8Array(await readFile(`docs/music/${name}`));
    new Uint8Array(mem.buffer, audio.audioSongPtr(), tune.length).set(tune);
    if (!audio.audioLoadSndh(tune.length)) return -1;
    audio.audioSndhPlay(1); // the image has one subtune; requestSong asks for its default
    const left = new Float32Array(mem.buffer, chip.audioLeftPtr(), 882);
    let peak = 0;
    for (let f = 0; f < 150; f++) { // 3 s of 50 Hz blocks, as apps/sndh_headless.mjs reads them
        audio.audioRender(882);
        for (const v of left) peak = Math.max(peak, Math.abs(v));
    }
    return peak;
}
const peak = song ? await sndhPeak(song) : -1;
if (!(peak > 0.01)) errors.push(`${song} plays at peak ${peak} (silent or refused)`);

if (errors.length) {
    console.error(`union_demo_intro: WRONG\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`union_demo_intro: depack ${depackFrames} frames, no panel (${midInk} TEX ink px); all 64000 px equal the screen.js replay at frames ${FRAMES.join(",")}; song ${song} (peak ${peak.toFixed(2)}); Space -> demoloader.js panel, landed after ${landedTicks} frames (${landedInk} ink px = its glyphs) -> Space -> union_demo; ${perFrame.toFixed(3)} ms/frame`);
