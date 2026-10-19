// Headless DMA INTRO 2 driver (cart 94). The production is
// github.com/olivierh59500/go-larcociel2, a Go/Ebitengine re-creation of DMA's
// "LARCOCIEL" intro. This harness holds the Zig cart to it, end to end, WITHOUT
// a Go toolchain: it re-implements the port's exact algorithm here (the trail
// clock, the projection, the scrolling slice stream, the YM register stream),
// reads the SAME ripped assets the cart embeds, and compares the machine's
// rendered 320x200 window to the model's, pixel for pixel.
//
//   model    every frame to 24 s, the composited window is the model's RGB --
//            which validates the background band, the six projected balls, the
//            scrolltext and the two rasters (entry 8 on lines 0..15, entry 4 on
//            lines 49..92) TOGETHER, since a wrong colour on any line is a
//            mismatch
//   go       at 14 checkpoints the window is the Go re-creation's OWN captured
//            PNG, byte for byte (no Go toolchain needed here)
//   clock    lcTick()/lcField()/lcHistory() equal the model's words every frame
//            and, at step 49, the Go tree's native-motion-49.json checkpoint
//   slots    the six projected ball poses equal the model's every frame
//   text     the scrolling slice window (head, glyph, column) equals the model's
//            every frame
//   ymusic   the (register, value) writes the cart hands the sfx queue equal
//            the Go's music.ym frame for frame, and the cart's own mirror equals
//            the model's; the error counter stays 0 and no write is refused
//   raster   the window carries more than the 16 static palette colours
//   leave    Space and Escape both hand the screen back to the menu
//   soak     no zg.mem allocation refused; ms/frame reported, not budgeted
//   node apps/larcociel2_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200;
const OUT = process.argv[2] || "/tmp/larcociel2";
const TICK_MS = 20.0; // the cart's 50 Hz step; the harness gives exactly one tick a frame

// ---------------- boot (the grodan/kickoff2 shape: machine + ROM + cart) -----
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-larcociel2.wasm");
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

// A whole fresh machine + cart, isolated from the run above: the leave test needs
// an un-quit cart per key, and startCart() never re-boots (demo_main's contract).
async function bootIsolated() {
    const mem = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const mach = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory: mem, hblDispatch: () => {} }, // no rendering here, so no HBL needed
    })).instance.exports;
    const renv = { memory: mem, hwVideoBase: mach.hwVideoBase, hwBlit: mach.hwBlit };
    const r = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: renv })).instance.exports;
    const en = {
        ...renv,
        hwRamBase: mach.hwRamBase, hwRamTop: mach.hwRamTop, hwRamSize: mach.hwRamSize,
        hwRamUsed: mach.hwRamUsed, hwRamFree: mach.hwRamFree,
        hwRamAlloc: mach.hwRamAlloc, hwRamMark: mach.hwRamMark,
        hwRamRelease: mach.hwRamRelease, hwRamAllocFailures: mach.hwRamAllocFailures,
        hwRomRamBase: mach.hwRomRamBase, hwRomRamTop: mach.hwRomRamTop,
        hwRomRamSize: mach.hwRomRamSize, hwRomRamUsed: mach.hwRomRamUsed,
        hwRomRamFree: mach.hwRomRamFree, ...r,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in en)) en[imp.name] = noop;
    const d = (await WebAssembly.instantiate(cartBytes, { env: en })).instance.exports;
    mach.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    mach.hwInit();
    d.boot();
    d.skipBoot();
    return d;
}

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
const A = "apps/zig/assets/screens/larcociel2/";
const BAND_TOP = 143, BAND_ROWS = 57, BAND_FRAMES = 36;
const bgStatic = await readFile(A + "bg-static.bin");
const bgBand = await readFile(A + "bg-band.bin");
const ballsBin = await readFile(A + "balls.bin");
const fontBin = await readFile(A + "font.bin");
const palRaw = await readFile(A + "palette.bin");
const rastRaw = await readFile(A + "raster.bin");
const msg = await readFile(A + "message.txt");
const order = await readFile(A + "font-order.txt");
const motion = await readFile(A + "initial-motion.bin");
const hist0 = await readFile(A + "initial-history.bin");
const seq = await readFile(A + "music.seq");

const BE16 = (b, o) => (b[o] << 8) | b[o + 1];
const rgbw = (w) => [((w >> 8) & 7) * 34, ((w >> 4) & 7) * 34, (w & 7) * 34];
const PAL = Array.from({ length: 16 }, (_, i) => rgbw(BE16(palRaw, i * 2)));
const RAST = Array.from({ length: 20 }, (_, i) => rgbw(BE16(rastRaw, i * 2)));
const p2 = (buf, p) => (buf[p >> 2] >> (2 * (p & 3))) & 3;
const p1 = (buf, p) => (buf[p >> 3] >> (7 - (p & 7))) & 1;
const bg2 = (frame, y, x) => y < BAND_TOP
    ? p2(bgStatic, y * 320 + x)
    : p2(bgBand, frame * (BAND_ROWS * 320) + (y - BAND_TOP) * 320 + x);
const ballShade = (k, y, x) => p2(ballsBin, k * 1024 + y * 32 + x);
const fontBit = (g, y, x) => p1(fontBin, g * 512 + y * 32 + x);

// ---- the trail clock (internal/source/clock.go; int16 wraps) ----------------
const w16 = (x) => ((x + 32768) & 0xFFFF) - 32768;
function newClock() {
    const w = (a) => w16(BE16(motion, a));
    return {
        tick: 0, counter: w(18),
        velocity: [w(0), w(2), w(4)], acceleration: [w(6), w(8), w(10)], position: [w(12), w(14), w(16)],
        history: Array.from({ length: 66 }, (_, i) => [w16(BE16(hist0, i * 6)), w16(BE16(hist0, i * 6 + 2)), w16(BE16(hist0, i * 6 + 4))]),
    };
}
function stepClock(c) {
    c.history = c.history.slice(1, 66).concat([[0, 0, 0]]);
    for (let j = 0; j < 3; j++) c.position[j] = w16(c.position[j] + c.velocity[j]);
    c.history[65] = c.position.slice();
    c.counter++;
    if (c.counter === 3) {
        c.counter = 0;
        for (let j = 0; j < 3; j++) c.velocity[j] = w16(c.velocity[j] + c.acceleration[j]);
        if (c.velocity[0] === 10 || c.velocity[0] === -10) c.acceleration[0] = w16(-c.acceleration[0]);
        if (c.velocity[1] === 7 || c.velocity[1] === -7) c.acceleration[1] = w16(-c.acceleration[1]);
        if (c.velocity[2] === 12 || c.velocity[2] === -12) c.acceleration[2] = w16(-c.acceleration[2]);
    }
    c.tick++;
}

// ---- the projection (geometry.ProjectWordPoint) -----------------------------
function project(hx, hy, hz) {
    const x = w16(hx - 160), y = w16(hy - 80);
    const px = 205 * x, py = 205 * y;
    const depth = w16(hz + 205);
    if (depth === 0) return { x: 0, y: 0, image: 0, visible: false };
    const div = (n) => {
        const q = Math.trunc(n / depth); // Go int64 division truncates toward zero
        return (q < -32768 || q > 32767) ? w16(n & 0xFFFF) : q; // KeepLow: the numerator's low word
    };
    const a = div(px), b = div(py);
    return { x: w16(a + 160), y: w16(b + 80), image: Math.max(0, Math.min(15, hz >> 5)), visible: true };
}
const slotPose = (clock, k) => {
    const p = clock.history[k * 11];
    return project(p[0], p[1], p[2]);
};

// ---- the scrolling slice stream (scrolling.SliceStream, 36 x 8px) -----------
const TOKENS = Array.from(msg, (c) => { const i = order.indexOf(c); return i < 0 ? 30 : i; });
class SliceStream {
    constructor() { this.head = 0; this.token = 0; this.idx = 0; this.slices = Array.from({ length: 36 }, () => ({ glyph: -1, index: 0 })); }
    step() {
        this.head = (this.head + 1) % 36;
        const tail = (this.head + 35) % 36;
        this.slices[tail] = { glyph: TOKENS[this.token], index: this.idx };
        this.idx++;
        if (this.idx >= 4) { this.idx = 0; this.token = (this.token + 1) % TOKENS.length; }
    }
    slot(i) { return this.slices[(this.head + i) % 36]; }
}

// ---- the composited window --------------------------------------------------
function compose(frame, body, text) {
    const out = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            let i = bg2(frame, y, x) * 4;
            const sh = body.get(y * W + x);
            if (sh) i = (i & ~3) | sh;
            if (text.has(y * W + x)) i = (i % 8) + 8;
            let c;
            if (i === 8 && y < 16) c = RAST[y >> 1];
            else if (i === 4 && y >= 49 && y < 93) c = RAST[9 + ((y - 49) >> 2)];
            else c = PAL[i];
            const o = (y * W + x) * 3;
            out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2];
        }
    }
    return out;
}
function renderFrame(tick, clock, stream) {
    const frame = (tick + 35) % BAND_FRAMES;
    const body = new Map();
    for (let k = 0; k < 6; k++) {
        const pr = slotPose(clock, k);
        if (!pr.visible) continue;
        for (let yy = 0; yy < 32; yy++) {
            const Y = pr.y + yy;
            if (Y < 0 || Y >= H) continue;
            for (let xx = 0; xx < 32; xx++) {
                const sh = ballShade(pr.image, yy, xx);
                if (!sh) continue;
                const X = pr.x + xx;
                if (X < 0 || X >= W) continue;
                body.set(Y * W + X, sh);
            }
        }
    }
    const text = new Set();
    for (let i = 0; i < 36; i++) {
        const s = stream.slot(i);
        if (s.glyph < 0) continue;
        const x0 = 16 + 8 * i;
        for (let yy = 0; yy < 16; yy++)
            for (let k = 0; k < 8; k++)
                if (fontBit(s.glyph, yy, s.index * 8 + k)) text.add(yy * W + x0 + k);
    }
    return compose(frame, body, text);
}
const render0 = () => compose(BAND_FRAMES - 1, new Map(), new Set());

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
    const png = decodePNG(await readFile(`tools/larcociel2/go_ref/${String(n).padStart(6, "0")}.png`));
    if (png.w !== W || png.h !== H) throw new Error(`go_ref frame ${n}: ${png.w}x${png.h}`);
    goRef.set(n, png.rgb);
}

// ---------------- run ---------------------------------------------------------
const EVERY = 1200; // compare every single frame up to here (24 s at 50 Hz)
const LAST = 18700; // the song is 18695 frames at 50 Hz; run past its loop point
const CHECK = new Set([1500, 2000, 3000, 5000, 8000, 12000, 18693, 18694, 18695, 18696, LAST]);

const clock = newClock();
const stream = new SliceStream();
const ym = new YM();
const t0 = performance.now();
let compared = 0, goCompared = 0, distinctMax = 0, ymWrites = 0;
let at49 = null; // the cart's own clock words at step 49 (the native checkpoint)

// The boot frame: init() draws the Go's 0-update frame (band frame 35, no balls,
// no text). Pin it explicitly -- the loop only sees frame 1 onward.
{
    machine.hwClear();
    const want = render0(), got = windowRGB();
    const d = firstPixelDiff(got, want);
    if (d >= 0) throw new Error(pixelErr("boot frame (Go frame 0)", got, want, d));
    const g0 = goRef.get(0);
    const gd0 = firstPixelDiff(got, g0);
    if (gd0 >= 0) throw new Error(pixelErr("boot frame (Go frame 0) vs the Go capture", got, g0, gd0));
    if (demo.lcShownLive() !== 0) throw new Error("boot frame: the balls/text are already composited");
    goCompared++;
    compared++;
    await shot(`${OUT}/frame_000000.ppm`, got);
}

for (let f = 0; f <= LAST; f++) {
    const frame = f + 1; // the cart's frame after this one 50 Hz tick
    machine.hwClear();

    // The model's expected writes for the frame's single YM step (= frame f).
    const expect = [];
    ym.applyOne((r, v) => expect.push([r, v]));
    stepClock(clock);
    stream.step();

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
    if (demo.lcTick() !== clock.tick) throw new Error(`frame ${frame}: lcTick ${demo.lcTick()} != ${clock.tick}`);
    const cw = [clock.counter, ...clock.velocity, ...clock.acceleration, ...clock.position];
    for (let i = 0; i < cw.length; i++)
        if (demo.lcField(i) !== cw[i])
            throw new Error(`frame ${frame}: clock field ${i} is ${demo.lcField(i)} but the model says ${cw[i]}`);
    for (let i = 0; i < 66; i++)
        for (let j = 0; j < 3; j++)
            if (demo.lcHistory(i, j) !== clock.history[i][j])
                throw new Error(`frame ${frame}: history ${i}.${j} is ${demo.lcHistory(i, j)} but the model says ${clock.history[i][j]}`);
    if (frame === 49) at49 = {
        velocity: clock.velocity.slice(), acceleration: clock.acceleration.slice(),
        position: clock.position.slice(), counter: clock.counter,
        history: clock.history.map((p) => p.slice()),
    };

    // --- the scrolling slice window ---
    if (demo.lcHead() !== stream.head) throw new Error(`frame ${frame}: lcHead ${demo.lcHead()} != ${stream.head}`);
    for (let i = 0; i < 36; i++) {
        const s = stream.slot(i);
        if (demo.lcSliceGlyph(i) !== s.glyph)
            throw new Error(`frame ${frame}: slice ${i} glyph is ${demo.lcSliceGlyph(i)} but the model says ${s.glyph}`);
        if (demo.lcSliceIndex(i) !== s.index)
            throw new Error(`frame ${frame}: slice ${i} column is ${demo.lcSliceIndex(i)} but the model says ${s.index}`);
    }

    // --- the six projected ball poses ---
    for (let k = 0; k < 6; k++) {
        const pr = slotPose(clock, k);
        const got = [demo.lcSlot(k, 0), demo.lcSlot(k, 1), demo.lcSlot(k, 2), demo.lcSlot(k, 3)];
        const want = [pr.x, pr.y, pr.image, pr.visible ? 1 : 0];
        for (let i = 0; i < 4; i++)
            if (got[i] !== want[i])
                throw new Error(`frame ${frame}: slot ${k} field ${i} is ${got[i]} but the model says ${want[i]}`);
    }

    // --- the cart's own YM mirror ---
    for (let i = 0; i < 14; i++)
        if (demo.lcYmReg(i) !== ym.regs[i])
            throw new Error(`frame ${frame}: YM reg ${i} is ${demo.lcYmReg(i)} but the model says ${ym.regs[i]}`);

    // --- the pixels ---
    if (frame <= EVERY || CHECK.has(frame)) {
        const want = renderFrame(frame, clock, stream);
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

ok(demo.lcYmRefused() === 0, `the cart's ${ymWrites} YM writes were all accepted (lcYmRefused 0)`);
ok(compared >= EVERY + CHECK.size, `${compared} frames compared pixel for pixel (the boot frame, every frame to ${EVERY}, plus the loop and soak checkpoints)`);
ok(goCompared === GO_FRAMES.length, `${goCompared} frames compared to the Go re-creation's own captured PNGs (0..1199)`);

// The Go tree's native checkpoint, from internal/source/testdata/native-motion-49.json:
// the LIVE cart's own clock words at step 49.
{
    const want = JSON.parse(await readFile("tools/larcociel2/native-motion-49.json", "utf8"));
    const eq = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
    const histOk = at49 && at49.history.length === want.history.length &&
        at49.history.every((p, i) => eq(p, want.history[i]));
    const good = at49 &&
        eq(at49.velocity, want.velocity) && eq(at49.acceleration, want.acceleration) &&
        eq(at49.position, want.position) && at49.counter === want.counter && histOk;
    ok(!!good, `the live trail clock at step ${want.steps} equals the Go tree's native-motion-49.json checkpoint (all 66 history points)`);
}

// A raster, not a static palette: the window carries more colours than the 16
// palette words alone can (entries 4 and 8 really are rewritten per line).
ok(distinctMax > 16, `the per-line rasters put ${distinctMax} distinct colours on the window (a static palette gives <= 16)`);

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
demo.key(0xE012);
demo.frame(TICK_MS);
ok(demo.pollCartRequest() === -1, "Escape hands the screen back to the menu (pollCartRequest -1)");
{
    const fresh = await bootIsolated();
    fresh.key(0x20); // Space
    fresh.frame(TICK_MS);
    ok(fresh.pollCartRequest() === -1, "Space hands the screen back to the menu too (pollCartRequest -1)");
}

ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
console.log(`  ${(ms / (LAST + 1)).toFixed(3)} ms/frame over ${LAST + 1} frames (update + render + composite + model)`);

const total = errors.length;
console.log(total === 0 ? "larcociel2: PASS" : `larcociel2: FAILED (${total})`);
process.exit(total ? 1 : 0);
