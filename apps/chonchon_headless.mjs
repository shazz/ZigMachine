// Headless CHONCHON driver (cart 96). The production is
// github.com/olivierh59500/go-chonchon, a Go/Ebitengine re-creation of an ST
// Chon-Chon / DMA intro. This harness holds the Zig cart to it, end to end,
// WITHOUT a Go toolchain: it re-implements the port's exact algorithm here (the
// native motion clock, the two slide-stream ring scrollers, the Huffman font
// banks, the 100 authored star paths, the YM register stream, the three plane-3
// music meters and the 63-row chrome logo), reads the SAME ripped assets the
// cart embeds, and compares the machine's rendered 320x200 window to the
// model's, pixel for pixel.
//
//   model    every frame to 24 s the composited window is the model's RGB --
//            which validates the background, the stars, the scroller, the
//            meters AND the per-line raster TOGETHER, since a wrong colour on
//            any line is a mismatch
//   go       at 14 checkpoints the window is the Go re-creation's OWN captured
//            PNG, byte for byte (no Go toolchain needed here)
//   clock    chTick()/chField() equal the model's words every frame and, after
//            100 steps, chRing() equals the Go tree's own native scroll-bank
//            checkpoints (testdata/scroll-bank-{0,1}-100.bin.gz)
//   ymusic   the (register, value) writes the cart hands the sfx queue equal
//            the Go's music.ym frame for frame, and the cart's own mirror equals
//            the model's; the three meters track registers 8/9/10; the error
//            counter stays 0 and no write is refused
//   raster   the window carries more than the 16 static palette colours
//   leave    Space and Escape both hand the screen back to the menu
//   soak     no zg.mem allocation refused; ms/frame reported, not budgeted
//   node apps/chonchon_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { inflateSync, gunzipSync } from "node:zlib";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200;
const OUT = process.argv[2] || "/tmp/chonchon";
const TICK_MS = 20.0; // the cart's 50 Hz step; the harness gives exactly one tick a frame

// ---------------- boot (the larcociel5/grodan shape) -------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-chonchon.wasm");
const env = {
    ...romEnv,
    hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
    hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
    hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
    hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
    hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
    hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
    hwRomRamFree: machine.hwRomRamFree, ...rom,
};
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

await mkdir(OUT, { recursive: true });
console.log("boot ok");

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };

// ---------------- the machine's composited window ---------------------------
const pw = machine.hwPhysWidth(); // 800: low res is x-doubled
const ph = machine.hwPhysHeight(); // 280
const bx = machine.hwBorderX(), by = machine.hwBorderY();
const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), pw * ph * 4);

function windowRGB() {
    machine.hwRenderPlane(0);
    const out = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const i = ((by + y) * pw + (bx + x * 2)) * 4;
            out[(y * W + x) * 3] = pfb[i];
            out[(y * W + x) * 3 + 1] = pfb[i + 1];
            out[(y * W + x) * 3 + 2] = pfb[i + 2];
        }
    return out;
}
function borderRGB() {
    const out = new Uint8Array(ph * 3);
    for (let line = 0; line < ph; line++) {
        const i = (line * pw) * 4;
        out[line * 3] = pfb[i]; out[line * 3 + 1] = pfb[i + 1]; out[line * 3 + 2] = pfb[i + 2];
    }
    return out;
}
async function shot(path, win) {
    await writeFile(path, Buffer.concat([Buffer.from(`P6\n${W} ${H}\n255\n`), win]));
}
const firstPixelDiff = (got, want) => {
    for (let i = 0; i < want.length; i++) if (got[i] !== want[i]) return i;
    return -1;
};
const pixelErr = (msg, got, want, i) =>
    `${msg}: pixel (${((i / 3) | 0) % W},${(((i / 3) | 0) / W) | 0}) channel ${i % 3} is ${got[i]} but expected ${want[i]}`;

// ==========================================================================
// The model: the port's exact algorithm, integer, in JS.
// ==========================================================================
const A = "apps/zig/assets/screens/chonchon/";
const background = await readFile(A + "background.bin");
const font = await readFile(A + "font-source.bin");
const logoPath = await readFile(A + "logo-path.bin");
const logoY = await readFile(A + "logo-y.bin");
const scrollY = await readFile(A + "scroll-y.bin");
const message = await readFile(A + "message.bin");
const starPaths = await readFile(A + "star-paths.bin");
const starIndex = await readFile(A + "star-index.bin");
const palRaw = await readFile(A + "palette.bin");
const rastRaw = await readFile(A + "raster.bin");
const curve = await readFile(A + "volume-curve.bin");
const meterRaw = await readFile(A + "meter-raw.bin");
const logoIdx = await readFile(A + "logo.idx");
const seq = await readFile(A + "music.seq");

const be16 = (b, o) => (b[o] << 8) | b[o + 1];
const be32 = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
const s16 = (v) => (v & 0x8000 ? v - 0x10000 : v);
const mod = (a, n) => ((a % n) + n) % n;
const rgbw = (w) => [((w >> 8) & 7) * 34, ((w >> 4) & 7) * 34, (w & 7) * 34];
const pack = ([r, g, b]) => (r << 16) | (g << 8) | b;
const PAL = Array.from({ length: 16 }, (_, i) => pack(rgbw(be16(palRaw, i * 2))) );
const RAST = Array.from({ length: 28 }, (_, i) => pack(rgbw(be16(rastRaw, i * 2))));

// ---- the native motion (internal/source/clock.go) ---------------------------
const screen = new Uint8Array(32000);
const clock = {
    tick: 0, logoPhase: 0, logoYPhase: 0, logoY: 0, scrollPhase: 0,
    messageCursor: 0, counter: 0,
    write: [2808, 2808], read: [0, 0],
    ring: [new Uint8Array(3432), new Uint8Array(3432)],
    starBase: Array.from({ length: 100 }, (_, i) => be32(starIndex, i * 6) - 0x1b018 - 0x1cc88),
    starCursor: Array.from({ length: 100 }, (_, i) => be16(starIndex, i * 6 + 4)),
};
function stepClock() {
    clock.tick++;
    screen.set(background);
    clock.logoPhase += 12;
    if (s16(be16(logoPath, clock.logoPhase + 63 * 6)) < 0) clock.logoPhase = 0;
    clock.logoYPhase++;
    if (clock.logoYPhase * 2 >= logoY.length || s16(be16(logoY, clock.logoYPhase * 2)) < 0) clock.logoYPhase = 0;
    clock.logoY = (be16(logoY, clock.logoYPhase * 2) / 160) | 0;
    for (let i = 0; i < 100; i++) {
        let p = clock.starBase[i] + clock.starCursor[i] + 6;
        if (p + 6 > starPaths.length || be16(starPaths, p) === 0) { clock.starCursor[i] = 0; p = clock.starBase[i]; }
        else clock.starCursor[i] += 6;
        const off = be16(starPaths, p);
        if (off + 4 <= screen.length) {
            const v = (be32(screen, off) | be32(starPaths, p + 2)) >>> 0;
            screen[off] = (v >>> 24) & 255; screen[off + 1] = (v >>> 16) & 255;
            screen[off + 2] = (v >>> 8) & 255; screen[off + 3] = v & 255;
        }
    }
    const bank = (clock.tick - 1) % 2;
    if (bank === 0 && clock.counter === 0) {
        if (clock.messageCursor + 2 > message.length || s16(be16(message, clock.messageCursor)) < 0) clock.messageCursor = 0;
        const off = be16(message, clock.messageCursor);
        clock.write[0] = (clock.write[0] + 312) % 3432;
        if (off + 312 <= font.length) clock.ring[0].set(font.subarray(off, off + 312), clock.write[0]);
    }
    if (bank === 1) {
        clock.counter--;
        if (clock.counter < 0) {
            clock.counter = 1;
            if (clock.messageCursor + 2 > message.length || s16(be16(message, clock.messageCursor)) < 0) clock.messageCursor = 0;
            const off = s16(be16(message, clock.messageCursor));
            clock.messageCursor += 2;
            clock.write[1] = (clock.write[1] + 312) % 3432;
            const packed = 0x18369 - 0xce2a + off;
            if (packed >= 0 && packed + 312 <= font.length) {
                for (let row = 0; row < 26; row++) {
                    const src = packed + row * 12;
                    const dst = clock.write[1] + row * 6;
                    for (let plane = 0; plane < 3; plane++) clock.ring[1][mod(dst - 155 + plane * 2, 3432)] = font[src + plane];
                    for (let j = 0; j < 6; j++) clock.ring[1][mod(dst + j, 3432)] = font[src + 3 + j];
                    for (let plane = 0; plane < 3; plane++) clock.ring[1][mod(dst + 156 + plane * 2, 3432)] = font[src + 9 + plane];
                }
            }
        }
    }
    clock.scrollPhase += 2;
    if (clock.scrollPhase * 2 >= scrollY.length || s16(be16(scrollY, clock.scrollPhase * 2)) < 0) clock.scrollPhase = 0;
    clock.read[bank] = (clock.read[bank] + 156) % 3432;
    for (let col = 0; col < 18; col++) {
        let p = clock.scrollPhase + col * 2;
        while (p >= scrollY.length / 2 || s16(be16(scrollY, p * 2)) < 0) p = 0;
        let p2 = p + 1;
        if (p2 >= scrollY.length / 2 || s16(be16(scrollY, p2 * 2)) < 0) p2 = 0;
        const y1 = (be16(scrollY, p * 2) / 160) | 0;
        const y2 = (be16(scrollY, p2 * 2) / 160) | 0;
        for (let row = 0; row < 26; row++) {
            const r = (clock.read[bank] + col * 156 + row * 6) % 3432;
            for (let plane = 0; plane < 3; plane++) {
                const a = (y1 + row) * 160 + (col + 1) * 8 + plane * 2;
                const b = (y2 + row) * 160 + (col + 1) * 8 + plane * 2 + 1;
                if (a >= 0 && a < screen.length) screen[a] = clock.ring[bank][r + plane * 2];
                if (b >= 0 && b < screen.length) screen[b] = clock.ring[bank][r + plane * 2 + 1];
            }
        }
    }
}
stepClock(); stepClock(); clock.tick = 0; // NewClock

// ---- the three plane-3 music meters (internal/demo/game.go Update) ----------
function applyMeter(regs) {
    for (let ch = 0; ch < 3; ch++) {
        const height = curve[regs[8 + ch] & 15];
        if (height === 0) continue;
        const x = ch === 0 ? 96 : ch === 1 ? 144 : 176;
        const width = ch === 1 ? 32 : 48;
        const sourceX = x - 96;
        for (let row = 0; row <= height && row < 52; row++) {
            for (let dx = 0; dx < width; dx++) {
                const p = (147 + row) * 160 + ((x + dx) / 16 | 0) * 8 + 6;
                const mask = 1 << (15 - (x + dx) % 16);
                let w = be16(screen, p);
                const q = sourceX + dx;
                const v = be16(meterRaw, row * 160 + (q / 16 | 0) * 8);
                if ((v >> (15 - q % 16)) & 1) w |= mask;
                screen[p] = (w >>> 8) & 255; screen[p + 1] = w & 255;
            }
        }
    }
}

// ---- the YM delta stream ----------------------------------------------------
const ymFrames = seq.readUInt32LE(0);
const ymOff = new Array(ymFrames);
{
    let o = 4;
    const pop = (m) => { let n = 0; while (m) { n += m & 1; m >>= 1; } return n; };
    for (let f = 0; f < ymFrames; f++) {
        const mask = seq[o] | (seq[o + 1] << 8); o += 2;
        ymOff[f] = { voff: o, mask }; o += pop(mask);
    }
}
class YM {
    constructor() { this.regs = new Uint8Array(14); this.applied = 0; this.next = 0; }
    applyOne(sink) {
        const fr = ymOff[this.next];
        let o = fr.voff;
        for (let r = 0; r < 14; r++)
            if (fr.mask & (1 << r)) {
                const v = seq[o++];
                this.regs[r] = v;
                if (sink) sink(r, v);
            }
        this.next = (this.next + 1) % ymFrames;
        this.applied++;
    }
}

// ---- the shader: index image + logo overlay + the final colour rule ---------
function indexOf(y, x) {
    const sb = y * 160 + (x >> 4) * 8;
    const bit = 15 - (x & 15);
    return ((be16(screen, sb) >> bit) & 1) |
        ((((be16(screen, sb + 2) >> bit) & 1)) << 1) |
        ((((be16(screen, sb + 4) >> bit) & 1)) << 2) |
        ((((be16(screen, sb + 6) >> bit) & 1)) << 3);
}
const colourOf = (i, y) => (y >= 144 && i >= 8) ? RAST[(y - 144) >> 1] : PAL[i];
function renderFrame(withLogo) {
    const out = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const c = colourOf(indexOf(y, x), y);
            const o = (y * W + x) * 3;
            out[o] = (c >> 16) & 255; out[o + 1] = (c >> 8) & 255; out[o + 2] = c & 255;
        }
    if (withLogo)
        for (let row = 0; row < 63; row++) {
            const p = clock.logoPhase + row * 6;
            const offset = be16(logoPath, p);
            const phase = (be32(logoPath, p + 2) / 72) | 0;
            const lx = ((offset / 8) | 0) * 16;
            const ly = clock.logoY + row;
            if (ly < 0 || ly >= H) continue;
            const sr = (row * 17 + phase) * 96;
            for (let dx = 0; dx < 96; dx++) {
                const idx = logoIdx[sr + dx];
                if (idx === 0) continue;
                const px = lx + dx;
                if (px < 0 || px >= W) continue;
                const c = colourOf(idx, ly);
                const o = (ly * W + px) * 3;
                out[o] = (c >> 16) & 255; out[o + 1] = (c >> 8) & 255; out[o + 2] = c & 255;
            }
        }
    return out;
}
function render0() {
    const out = new Uint8Array(W * H * 3);
    const c = PAL[0];
    for (let i = 0; i < W * H; i++) { out[i * 3] = (c >> 16) & 255; out[i * 3 + 1] = (c >> 8) & 255; out[i * 3 + 2] = c & 255; }
    return out;
}

// ---- the Go re-creation's own captured PNGs, decoded here -------------------
function decodePNG(buf) {
    if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
    let o = 8, w = 0, h = 0, ct = 0;
    const idat = [];
    while (o < buf.length) {
        const len = buf.readUInt32BE(o);
        const type = buf.toString("latin1", o + 4, o + 8);
        const data = buf.subarray(o + 8, o + 8 + len);
        if (type === "IHDR") {
            w = data.readUInt32BE(0); h = data.readUInt32BE(4);
            if (data[8] !== 8) throw new Error(`PNG bit depth ${data[8]}`);
            ct = data[9];
            if (data[12] !== 0) throw new Error("interlaced PNG");
        } else if (type === "IDAT") idat.push(data);
        else if (type === "IEND") break;
        o += 12 + len;
    }
    const ch = ct === 2 ? 3 : ct === 6 ? 4 : ct === 0 ? 1 : ct === 4 ? 2 : (() => { throw new Error(`PNG colour type ${ct}`); })();
    const raw = inflateSync(Buffer.concat(idat));
    const stride = w * ch;
    const img = Buffer.alloc(h * stride);
    let p = 0;
    for (let y = 0; y < h; y++) {
        const filt = raw[p++];
        const row = raw.subarray(p, p + stride); p += stride;
        const cur = img.subarray(y * stride, (y + 1) * stride);
        const prev = y > 0 ? img.subarray((y - 1) * stride, y * stride) : null;
        for (let x = 0; x < stride; x++) {
            const a = x >= ch ? cur[x - ch] : 0;
            const b = prev ? prev[x] : 0;
            const c = prev && x >= ch ? prev[x - ch] : 0;
            let v = row[x];
            if (filt === 1) v = (v + a) & 255;
            else if (filt === 2) v = (v + b) & 255;
            else if (filt === 3) v = (v + ((a + b) >> 1)) & 255;
            else if (filt === 4) {
                const pp = a + b - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c);
                v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 255;
            } else if (filt !== 0) throw new Error(`PNG filter ${filt}`);
            cur[x] = v;
        }
    }
    const rgb = new Uint8Array(w * h * 3);
    for (let i = 0; i < w * h; i++)
        for (let k = 0; k < 3; k++) rgb[i * 3 + k] = ch === 3 ? img[i * 3 + k] : img[i * ch + k];
    return { w, h, rgb };
}
const GO_FRAMES = [0, 1, 2, 10, 50, 100, 149, 200, 320, 500, 800, 1000, 1100, 1199];
const goRef = new Map();
for (const n of GO_FRAMES) {
    const png = decodePNG(await readFile(`tools/chonchon/go_ref/${String(n).padStart(6, "0")}.png`));
    if (png.w !== W || png.h !== H) throw new Error(`go_ref frame ${n}: ${png.w}x${png.h}`);
    goRef.set(n, png.rgb);
}

// ---------------- run ---------------------------------------------------------
const EVERY = 1200; // compare every single frame up to here (24 s at 50 Hz)
const LAST = 10720; // the song is 10650 frames at 50 Hz; run past its loop point
const CHECK = new Set([1400, 2000, 3000, 5000, 8000, 10500, 10649, 10650, 10651, LAST]);

const ym = new YM();
const t0 = performance.now();
let compared = 0, goCompared = 0, distinctMax = 0, ymWrites = 0;
const ringWant = [
    gunzipSync(await readFile("tools/chonchon/scroll-bank-0-100.bin.gz")),
    gunzipSync(await readFile("tools/chonchon/scroll-bank-1-100.bin.gz")),
];
let ringOK = null;

// The boot frame: init() draws the Go's 0-update frame (the empty index image ->
// palette[0]). Pin it explicitly -- the loop only sees frame 1 onward.
{
    machine.hwClear();
    const want = render0(), got = windowRGB();
    const d = firstPixelDiff(got, want);
    if (d >= 0) throw new Error(pixelErr("boot frame (Go frame 0)", got, want, d));
    const g0 = goRef.get(0);
    const gd0 = firstPixelDiff(got, g0);
    if (gd0 >= 0) throw new Error(pixelErr("boot frame (Go frame 0) vs the Go capture", got, g0, gd0));
    goCompared++; compared++;
    await shot(`${OUT}/frame_000000.ppm`, got);
}

for (let f = 0; f <= LAST; f++) {
    const frame = f + 1; // the cart's frame after this one 50 Hz tick
    machine.hwClear();

    // The model's expected writes for the frame's single YM step (= frame f).
    const expect = [];
    ym.applyOne((r, v) => expect.push([r, v]));
    stepClock();

    demo.frame(TICK_MS);

    // --- the music: the writes the cart handed the sfx queue this frame ---
    const n = demo.pollSfx();
    const dv = new DataView(memory.buffer, demo.sfxEntriesPtr(), 16 * Math.max(n, 1));
    if (n !== expect.length)
        throw new Error(`frame ${frame}: ${n} sfx entries, model says ${expect.length}`);
    for (let i = 0; i < n; i++) {
        if (dv.getUint8(16 * i) !== 3)
            throw new Error(`frame ${frame}: sfx entry ${i} is not a YM write (op ${dv.getUint8(16 * i)})`);
        if (dv.getUint8(16 * i + 1) !== expect[i][0] || dv.getUint8(16 * i + 2) !== expect[i][1])
            throw new Error(`frame ${frame}: ym write ${i} is ${dv.getUint8(16 * i + 1)}=${dv.getUint8(16 * i + 2)}, model says ${expect[i][0]}=${expect[i][1]}`);
    }
    ymWrites += n;
    if (demo.pollSongRequest() !== 0) throw new Error(`frame ${frame}: the cart requested a song (it must not)`);

    // --- the clock words, every frame ---
    if (demo.chTick() !== clock.tick) throw new Error(`frame ${frame}: chTick ${demo.chTick()} != ${clock.tick}`);
    const cw = [clock.logoPhase, clock.logoYPhase, clock.logoY, clock.scrollPhase, clock.messageCursor, clock.counter,
                clock.write[0], clock.write[1], clock.read[0], clock.read[1]];
    for (let i = 0; i < cw.length; i++)
        if (demo.chField(i + 1) !== cw[i])
            throw new Error(`frame ${frame}: clock field ${i + 1} is ${demo.chField(i + 1)} but the model says ${cw[i]}`);
    if (frame === 100) {
        ringOK = [0, 1].every(b => {
            for (let i = 0; i < 3432; i++) if (demo.chRing(b, i) !== ringWant[b][i]) return false;
            return true;
        });
    }

    // --- the cart's own YM mirror and the three meters ---
    for (let i = 0; i < 14; i++)
        if (demo.chYmReg(i) !== ym.regs[i])
            throw new Error(`frame ${frame}: YM reg ${i} is ${demo.chYmReg(i)} but the model says ${ym.regs[i]}`);
    for (let i = 0; i < 3; i++)
        if (demo.chMeters(i) !== (ym.regs[8 + i] & 15))
            throw new Error(`frame ${frame}: meter ${i} is ${demo.chMeters(i)} but the model says ${ym.regs[8 + i] & 15}`);

    // --- the pixels ---
    if (frame <= EVERY || CHECK.has(frame)) {
        applyMeter(ym.regs);
        const want = renderFrame(true);
        const got = windowRGB();
        const d = firstPixelDiff(got, want);
        if (d >= 0) throw new Error(pixelErr(`frame ${frame}`, got, want, d));
        compared++;
        const seen = new Set();
        for (let i = 0; i < want.length; i += 3) seen.add((want[i] << 16) | (want[i + 1] << 8) | want[i + 2]);
        if (seen.size > distinctMax) distinctMax = seen.size;
        if (goRef.has(frame)) {
            const g = goRef.get(frame);
            const gd = firstPixelDiff(got, g);
            if (gd >= 0) throw new Error(pixelErr(`frame ${frame} vs the Go capture`, got, g, gd));
            goCompared++;
        }
        if (frame === 1 || frame === 800 || frame === 1199 || frame === LAST) await shot(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, got);
    }
}
const ms = performance.now() - t0;

ok(demo.chYmRefused() === 0, `the cart's ${ymWrites} YM writes were all accepted (chYmRefused 0)`);
ok(compared >= EVERY + CHECK.size, `${compared} frames compared pixel for pixel (the boot frame, every frame to ${EVERY}, plus the loop and soak checkpoints)`);
ok(goCompared === GO_FRAMES.length, `${goCompared} frames compared to the Go re-creation's own captured PNGs (0..1199)`);
ok(ringOK === true, "after 100 steps both scroll banks equal the Go tree's own native scroll-bank checkpoints");

// A raster, not a static palette: the window carries more colours than the 16
// palette words alone can (entries 8..15 really are rewritten per line).
ok(distinctMax > 16, `the per-line raster puts ${distinctMax} distinct colours on the window (a static palette gives <= 16)`);

// The border bands above/below the visible line are black (the background word).
machine.hwClear(); demo.frame(TICK_MS); machine.hwRenderPlane(0);
{
    const border = borderRGB();
    let flat = true;
    for (let line = 0; line < ph; line++)
        if (line < by || line >= by + H)
            if (border[line * 3] !== 0 || border[line * 3 + 1] !== 0 || border[line * 3 + 2] !== 0) flat = false;
    ok(flat, "the border bands above/below line 200 stay black");
}

// Leave on Space and Escape (the Go terminates on both).
demo.key(32);
demo.frame(TICK_MS);
ok(demo.pollCartRequest() === -1, "Space hands the screen back to the menu (pollCartRequest -1)");
demo.key(0xE012);
demo.frame(TICK_MS);
ok(demo.pollCartRequest() === -1, "Escape hands the screen back to the menu (pollCartRequest -1)");

ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
console.log(`  ${(ms / (LAST + 1)).toFixed(3)} ms/frame over ${LAST + 1} frames (update + render + composite + model)`);

const total = errors.length;
console.log(total === 0 ? "chonchon: PASS" : `chonchon: FAILED (${total})`);
process.exit(total ? 1 : 0);
