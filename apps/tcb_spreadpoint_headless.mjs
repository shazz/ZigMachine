// Headless TCB SPREADPOINT driver -- boots the sealed machine + demo-tcb_spreadpoint
// the way docs/sealed-loader.js does, and checks it against screen.js REPLAYED.
//
// Why this exists: the screen is four fading pictures, then a logo on a 2272-frame
// angle table, 20 Lissajous balls, a 33-speed scroller and a DNA scroller that
// switch on at iterations 804, 1284 and 1952 -- all driven by the remake's own
// numbers, and three gradients that are colour-register RASTERS here where the
// remake paints them as pixels. So:
//
//   1. screen.js is replayed below (class Remake): intro(), anim(), draw_logo's
//      angle table built by its six loops, draw_balls, draw_scroll on a literal
//      scroll_canvas (text + its first 320 px repeated), scrolltext_horizontal's
//      twelve letters and draw_scroller_dna_part, in the remake's own f64 maths.
//      Canvas scaling is sampled nearest (pixel centres), as the port does. At
//      every shot the plane's INDICES must equal the replay's, pixel for pixel.
//   2. The rasters must be REGISTER writes: the plane's HBL is watched line by
//      line and palette entries 2..6 must hold gradient.png / tcb-raster.png /
//      the DNA shade on THAT line, at most 4 changes a line; and the composited
//      colour of every pixel must be its index's colour on its own line.
//   3. The SNDH: nothing is requested during the intro, then exactly
//      tcb_spreadpoint.sndh when the main part starts (the remake's master.mp3),
//      and that file plays through the sealed YM.
//
//   node apps/tcb_spreadpoint_headless.mjs [outdir]
//   node apps/tcb_spreadpoint_headless.mjs --break hbl   the HBL is not run:
//        the rasters must be caught missing
//   node apps/tcb_spreadpoint_headless.mjs --break step  one extra frame before
//        every main-part shot: the replay must catch it
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const OFF_PAL = 0x100, REG_FB_BASE = 0x44;
const W = 320, H = 200;
const ASSETS = "apps/zig/assets/screens/tcb_spreadpoint/";
const MUSIC = "tcb_spreadpoint.sndh";

const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/tcb_spreadpoint";
const errors = [];
const fail = (m) => { errors.push(m); console.log(`  FAIL ${m}`); };

// ---------------------------------------------------------------- assets
const A = {
    font: await readFile(ASSETS + "font.raw"),          // 80x36, 0 / 2
    fontDna: await readFile(ASSETS + "font_dna.raw"),   // 320x150, 0 / 4..6
    ball: await readFile(ASSETS + "ball.raw"),          // 17x16
    logo: await readFile(ASSETS + "logo.raw"),          // 128x40
    intro: await readFile(ASSETS + "intro.1bpp"),       // 4 x 320x108
    pal: new Uint32Array((await readFile(ASSETS + "palette.dat")).buffer.slice(0)),
};
const zigArray = (src, name) => [...src.match(new RegExp(`${name} = \\[\\d+\\]u\\d+\\{([^}]*)\\}`))[1].matchAll(/0x[0-9A-F]+|\d+/g)].map((m) => Number(m[0]));
const rastersSrc = await readFile("apps/zig/scenes/tcb_spreadpoint/rasters.zig", "utf8");
const T = {
    logoInk: zigArray(rastersSrc, "logo_ink"),
    scrollInk: zigArray(rastersSrc, "scroll_ink"),
    dnaAlpha: zigArray(rastersSrc, "dna_shade_alpha"),
};
const textsSrc = await readFile("apps/zig/scenes/tcb_spreadpoint/texts.zig", "utf8");
const zigString = (name) => [...textsSrc.split(`pub const ${name} =`)[1].split(";")[0].matchAll(/"((?:[^"\\]|\\.)*)"/g)]
    .map((m) => m[1].replace(/\\(.)/g, "$1")).join("");
const TEXT = zigString("scroll"), TEXT_DNA = zigString("dna");
if (TEXT.length !== 639 || TEXT_DNA.length < 1000) fail(`texts.zig parse: ${TEXT.length} / ${TEXT_DNA.length}`);

// ------------------------------------------------------- screen.js, replayed
const jsRound = Math.round;
class Remake {
    constructor() {
        this.mode = "intro"; this.iteration = 0; this.intro_pos = 0;
        // init(): the logo's angle table, six loops
        this.angle = [];
        let c = 0, a = Math.PI; const pi2 = 2 * Math.PI, fast = Math.PI / 32, slow = Math.PI / 40;
        for (let i = 0; i < 60 * 5; i++) { a = Math.PI; this.angle[c++] = a % pi2; }
        for (let i = 0; i < 40 * 1; i++) { a -= slow; this.angle[c++] = a % pi2; }
        for (let i = 0; i < 60 * 5; i++) { a = 0; this.angle[c++] = 0; }
        for (let i = 0; i < 80 * 8; i++) { a -= slow; this.angle[c++] = a % pi2; }
        for (let i = 0; i < 64 * 7.5; i++) { a -= fast; this.angle[c++] = a % pi2; }
        for (let i = 0; i < 64 * 8; i++) { a += fast; this.angle[c++] = a % pi2; }
        // scroll_canvas: text printed with the 8x6 font, then its first 320 px again
        this.scrollW = TEXT.length * 8 + 320;
        this.scrollCanvas = new Uint8Array(this.scrollW * 6);
        for (let i = 0; i < TEXT.length; i++) this.tile(this.scrollCanvas, this.scrollW, A.font, 80, 8, 6, TEXT.charCodeAt(i) - 32, i * 8, 0);
        for (let y = 0; y < 6; y++) for (let x = 0; x < 320; x++) this.scrollCanvas[y * this.scrollW + TEXT.length * 8 + x] = this.scrollCanvas[y * this.scrollW + x];
        // scrolltext_horizontal.init(scroll_dna_canvas, font_dna, 3)
        this.wide = Math.ceil(320 / 32) + 1;
        this.letters = []; this.scroffset = 0;
        for (let i = 0; i <= this.wide; i++) {
            this.letters[i] = { posx: Math.ceil(this.wide * 32 + i * 32), ltr: TEXT_DNA.charCodeAt(this.scroffset) };
            this.scroffset++;
        }
    }

    tile(dst, dw, font, fw, tw, th, nb, x, y) { // drawTile, opaque pixels only
        const sx = (nb % (fw / tw)) * tw, sy = Math.floor(nb / (fw / tw)) * th;
        for (let r = 0; r < th; r++) for (let q = 0; q < tw; q++) {
            const X = x + q, Y = y + r;
            if (X < 0 || X >= dw || Y < 0 || Y * dw >= dst.length) continue;
            const p = font[(sy + r) * fw + sx + q];
            if (p) dst[Y * dw + X] = p;
        }
    }

    // One requestAnimFrame: what the frame shows.
    step() {
        if (this.mode === "intro") return this.intro();
        const shot = { kind: "main", it: this.iteration, img: this.anim() };
        this.iteration++;
        return shot;
    }

    intro() {
        let r, g, b;
        const it = this.iteration;
        if (it < 20) { r = g = b = Math.floor(it * 255 / 19); this.iteration++; }
        else if (it < 160) { r = 255; g = b = Math.floor(0x22 + (159 - it) * 221 / 139); this.iteration++; }
        else if (it < 180) { const c = it - 160; r = Math.floor((19 - c) * 255 / 19); g = b = Math.floor((19 - c) * 0x22 / 19); this.iteration++; }
        else { r = g = b = 0; this.iteration = 0; this.intro_pos++; this.songAt = true; }
        const img = new Uint8Array(W * H);
        if (this.intro_pos <= 3) {
            const pic = A.intro.subarray(this.intro_pos * 108 * 40);
            for (let y = 0; y < 108; y++) for (let x = 0; x < 320; x++) if (pic[y * 40 + (x >> 3)] & (0x80 >> (x & 7))) img[(31 + y) * W + x] = 1;
            return { kind: "intro", pic: this.intro_pos, colour: [r, g, b], img, song: false };
        }
        this.mode = "anim";
        return { kind: "black", colour: [r, g, b], img, song: true };
    }

    anim() {
        const img = new Uint8Array(W * H);
        const it = this.iteration;
        if (it >= 1284) this.drawScroll(img, it - 1284);
        if (it >= 804) this.drawBalls(img, it - 804);
        this.drawLogo(img, it);
        if (it >= 1952) this.drawDna(img);
        return img;
    }

    drawScroll(img, ite) {
        const len = this.scrollW - 320;
        const speed = [12, 11, 10, 9, 8, 7, 6, 5, 4, 5, 6, 7, 8, 9, 10, 11, 12, 11, 10, 9, 8, 7, 6, 5, 4, 5, 6, 7, 8, 9, 10, 11, 12];
        for (let line = 0; line < speed.length; line++) {
            let dx, px; // drawPart(spread_canvas, dx, line*6, px, 0, 320, 6)
            if (speed[line] * ite < 320) { dx = 320 - speed[line] * ite; px = 0; }
            else { dx = 0; px = (speed[line] * ite - 320) % len; }
            const pw = Math.min(320, this.scrollW - px);
            for (let r = 0; r < 6; r++) for (let q = 0; q < pw; q++) {
                const X = dx + q; if (X >= 320) break;
                const p = this.scrollCanvas[r * this.scrollW + px + q];
                if (p) img[(line * 6 + r) * W + X] = p;
            }
        }
    }

    drawBalls(img, ite) {
        for (let j = 0; j < 20; j++) {
            const x = 151 + jsRound(151 * Math.sin(5 * (ite / 71 + j / 47)));
            const y = 50 + jsRound(50 * Math.sin(8 * (ite / 71 + j / 47)));
            this.tile(img, W, A.ball, 17, 17, 16, 0, x, y);
        }
    }

    drawLogo(img, it) {
        const a = this.angle[it % this.angle.length];
        const y = Math.sin(a), z = Math.cos(a) / 4 + 0.75, x = 64 - 64 * z, Y = 45 + 40 * y;
        for (let dy = 0; dy < 128; dy++) {
            const v = Math.floor((dy + 0.5 - Y) / z);
            if (!(v >= 0 && v < 40)) continue;
            for (let dx = 0; dx < 128; dx++) {
                const u = Math.floor((dx + 0.5 - x) / z);
                if (!(u >= 0 && u < 128)) continue;
                const p = A.logo[v * 128 + u];
                if (p) img[dy * W + 96 + dx] = p;
            }
        }
    }

    drawDna(img) {
        // scroll_dna.draw(0) into the 320x25 scroll_dna_canvas
        const strip = new Uint8Array(320 * 25);
        for (let i = 0; i <= this.wide; i++) {
            const l = this.letters[i];
            l.posx -= 3;
            if (l.posx <= -32) {
                l.posx = this.wide * 32 + (l.posx + 32);
                l.ltr = TEXT_DNA.charCodeAt(this.scroffset);
                this.scroffset++;
                if (this.scroffset > TEXT_DNA.length - 1) this.scroffset = 0;
            }
        }
        for (const l of this.letters) this.tile(strip, 320, A.fontDna, 320, 32, 25, l.ltr - 32, l.posx, 0);
        // draw_scroller_dna_part(0), (1)
        for (const pos of [0, 1]) {
            const decal = pos * Math.PI, amplitude = 25, pi2 = 2 * Math.PI;
            for (let x = 0; x < 320; x += 2) {
                const angle1 = (x * 0.026 + decal) % pi2, angle2 = (angle1 + 1.12) % pi2;
                const y1 = Math.round(amplitude * Math.sin(angle1)), y2 = Math.round(amplitude * Math.sin(angle2));
                if (!((3.6 < angle1) || (angle1 < 1.5))) continue;
                let from = y1, to = y2;
                if ((3.6 < angle1) && (angle1 < 4.6)) from = -amplitude;
                if ((0.5 < angle1) && (angle1 < 1.5)) to = amplitude;
                const height = (to - from) / amplitude + 0.0001;
                const top = 25 + from, bottom = top + 25 * height; // drawPart(dna_canvas, x, 25+from, x, 0, 2, 25, 1, 0, 1, height)
                for (let yy = Math.max(0, top); yy < 50 && yy + 0.5 < bottom; yy++) {
                    const sy = Math.min(24, Math.floor((yy + 0.5 - top) / height));
                    for (let q = 0; q < 2; q++) {
                        const p = strip[sy * 320 + x + q];
                        if (p) img[(121 + yy) * W + x + q] = p;
                    }
                }
            }
        }
    }
}

// The colour an index shows on line y: fixed entries, or the raster tables.
const rgbOf = (v) => [(v >> 16) & 255, (v >> 8) & 255, v & 255];
const DNA_FONT = [0x884400, 0xCC8800, 0xEECC00];
function rasterColour(entry, y) {
    if (entry === 2) return rgbOf(T.scrollInk[y]);
    if (entry === 3) return rgbOf(T.logoInk[Math.min(y, 127)]);
    const a = T.dnaAlpha[Math.min(Math.max(y - 121, 0), 49)];
    return rgbOf(DNA_FONT[entry - 4]).map((c, i) => Math.round((c * (255 - a) + [0x44, 0, 0][i] * a) / 255));
}
function colourOf(index, y, introColour) {
    if (index === 0) return [0, 0, 0];
    if (index === 1) return introColour;
    if (index >= 2 && index <= 6) return rasterColour(index, y);
    const v = A.pal[index];
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255];
}

// ------------------------------------------------------------------ machine
async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo, hblRec = null;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: {
            memory, hblDispatch: (id, p, l, x) => {
                if (brk !== "hbl") demo.hblDispatch(id, p, l, x);
                if (hblRec && p === 0) hblRec(l);
            },
        },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile("docs/demo-tcb_spreadpoint.wasm");
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory, jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
            hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop, hwRomRamSize: machine.hwRomRamSize,
            hwRomRamUsed: machine.hwRomRamUsed, hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
            hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const base = machine.hwVideoBase();
    return {
        memory, machine, demo, base,
        setHblRec: (f) => { hblRec = f; },
        palette: () => new Uint32Array(memory.buffer, base + OFF_PAL, 256),
        plane: () => new Uint8Array(memory.buffer, base + new DataView(memory.buffer, base).getUint32(REG_FB_BASE, true), W * H),
    };
}

const m = await boot();
const remake = new Remake();
const dec = new TextDecoder();
let frames = 0, songs = [], last = null;

function frame(replay = true) {
    m.machine.hwClear();
    m.demo.frame(16.6);
    if (!replay) return; // --break step: the cart runs a frame the replay does not
    last = remake.step();
    if (m.demo.pollSongRequest()) {
        songs.push({ frame: frames, name: dec.decode(new Uint8Array(m.memory.buffer, m.demo.songNamePtr(), m.demo.songNameLen())), tune: m.demo.songTune() });
    }
    if (last.song && !songs.some((s) => s.frame === frames)) fail(`frame ${frames}: the main part started and no song was requested`);
    frames++;
}

// Render with the HBL watched: palette entries 2..6 after each line's handler.
function renderWatched() {
    const lines = new Map();
    m.setHblRec((l) => { const p = m.palette(); lines.set(l, [2, 3, 4, 5, 6].map((e) => p[e])); });
    m.machine.hwRenderPlane(0);
    m.setHblRec(null);
    return lines;
}

async function shot(name) {
    const lines = renderWatched();
    const want = last.img, got = m.plane();
    let bad = 0, first = null;
    for (let i = 0; i < W * H; i++) if (got[i] !== want[i]) { bad++; first ??= `(${i % W},${Math.floor(i / W)}) got ${got[i]} want ${want[i]}`; }
    if (bad) fail(`${name}: ${bad} plane pixels differ from screen.js, first ${first}`);

    // The rasters as register writes, line by line.
    if (last.kind === "main") {
        let rasterBad = 0, maxWrites = 0;
        for (let y = 0; y < H; y++) {
            const v = lines.get(y);
            if (!v) { rasterBad++; continue; }
            for (let k = 0; k < 5; k++) {
                const c = rgbOf(((v[k] & 255) << 16) | (((v[k] >> 8) & 255) << 8) | ((v[k] >> 16) & 255));
                if (c.join() !== rasterColour(2 + k, y).join()) rasterBad++;
            }
            if (y > 0 && lines.get(y - 1)) maxWrites = Math.max(maxWrites, v.filter((c, k) => c !== lines.get(y - 1)[k]).length);
        }
        if (rasterBad) fail(`${name}: ${rasterBad} line/entry pairs of the HBL palette are not the raster tables`);
        if (maxWrites > 4) fail(`${name}: a line changes ${maxWrites} colour registers (budget 4)`);
    }

    // The composite: every pixel is its index's colour ON ITS LINE.
    const pw = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), pw * m.machine.hwPhysHeight() * 4);
    const ppm = new Uint8Array(W * H * 3);
    let colourBad = 0, firstC = null;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const o = ((40 + y) * pw + 80 + x * 2) * 4, a = pfb[o + 3] / 255;
        const c = [0, 1, 2].map((k) => Math.round(pfb[o + k] * a));
        ppm.set(c, (y * W + x) * 3);
        const e = colourOf(want[y * W + x], y, last.colour ?? [0, 0, 0]);
        if (c.join() !== e.join()) { colourBad++; firstC ??= `(${x},${y}) got ${c} want ${e}`; }
    }
    if (colourBad) fail(`${name}: ${colourBad} composited pixels are not their line's colour, first ${firstC}`);
    await writeFile(`${outdir}/${name}.ppm`, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), ppm]));
    console.log(`  ${name}: frame ${frames - 1} (${last.kind}${last.kind === "main" ? " it " + last.it : ""})${bad || colourBad ? "" : " matches screen.js"}`);
}

await mkdir(outdir, { recursive: true });
const INTRO = 724; // 4 pictures: 180 + 3 x 181 frames, then one black frame
const shotsIntro = { 10: "intro1-fadein", 100: "intro1-red", 180: "intro2-gap", 400: "intro3", 723: "black" };
const shotsMain = { 0: "main-far", 380: "main-near", 900: "balls", 1400: "scroll-arriving", 2000: "dna", 2300: "angle-wrap", 6000: "scroll-wrapped" };
const t0 = performance.now();
for (let f = 0; f <= INTRO + 6000; f++) {
    const it = f - INTRO;
    const want = f < INTRO ? shotsIntro[f] : shotsMain[it];
    if (want && brk === "step" && f >= INTRO) frame(false);
    frame();
    if (want) await shot(want);
}
const ms = (performance.now() - t0) / frames;

// The music: requested once, when the main part starts, and it plays.
if (songs.length !== 1 || songs[0].name !== MUSIC || songs[0].frame !== INTRO - 1)
    fail(`song requests ${JSON.stringify(songs)}: want one ${MUSIC} at frame ${INTRO - 1}`);
{
    const mem = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const ma = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory: mem } })).instance.exports;
    const env = { memory: mem };
    for (const n of Object.keys(ma)) if (n.startsWith("machine")) env[n] = ma[n];
    const au = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    au.audioInit();
    const tune = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    new Uint8Array(mem.buffer, au.audioSongPtr(), tune.length).set(tune);
    if (!au.audioLoadSndh(tune.length)) fail(`${MUSIC} is not an SNDH image`);
    au.audioSndhPlay(0);
    const left = new Float32Array(mem.buffer, ma.audioLeftPtr(), 1024);
    let peak = 0;
    for (let d = 0; d < 44100; d += 1024) { au.audioRender(1024); for (const v of left) peak = Math.max(peak, Math.abs(v)); }
    if (au.audioMode() !== 4 || peak < 0.05) fail(`${MUSIC} does not play (mode ${au.audioMode()}, peak ${peak.toFixed(3)})`);
    else console.log(`  music: ${MUSIC} requested at frame ${INTRO - 1}, plays (peak ${peak.toFixed(3)})`);
}
// The cart alone, every layer on (it > 1952): update + render + the composite.
{
    const t1 = performance.now();
    for (let i = 0; i < 2000; i++) { m.machine.hwClear(); m.demo.frame(16.6); m.machine.hwRenderPlane(0); }
    console.log(`  ${frames} frames replayed (${ms.toFixed(3)} ms/frame with the replay); ` +
        `the cart alone: ${((performance.now() - t1) / 2000).toFixed(3)} ms/frame (update + render + composite)`);
}

if (brk) {
    console.log(errors.length ? `tcb_spreadpoint: PASS (--break ${brk} caught: ${errors.length} failures)` : `tcb_spreadpoint: FAILED -- --break ${brk} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `tcb_spreadpoint: FAILED (${errors.length})` : "tcb_spreadpoint: all pass");
process.exit(errors.length ? 1 : 0);
