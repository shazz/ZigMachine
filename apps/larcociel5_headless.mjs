// Headless DMA INTRO 5 driver (cart 95). The production is
// github.com/olivierh59500/go-larcociel5, a Go/Ebitengine re-creation of DMA's
// "LARCOCIEL" intro. This harness holds the Zig cart to it, end to end, WITHOUT
// a Go toolchain: it re-implements the port's exact algorithm here (the ribbon
// clock, the DCK perspective glyph window, the YM register stream), reads the
// SAME ripped assets the cart embeds, and compares the machine's rendered
// 320x200 window to the model's, pixel for pixel.
//
//   model    every frame to 24 s, the composited window is the model's RGB --
//            which validates the background, the ribbon body, the three Batman
//            masks and the two rasters (entry 4 on lines 0..63, entries 1..15
//            on lines 100..199) TOGETHER, since a wrong colour on any line is
//            a mismatch
//   go       at 14 checkpoints the window is the Go re-creation's OWN captured
//            PNG, byte for byte (no Go toolchain needed here)
//   clock    lcTick()/lcField()/lcHistory() equal the model's words every
//            frame and, at step 149, the Go tree's native-ribbon-149.json
//   music    the cart asks for cybernoid2.sndh subtune 1 once (the SNDH of
//            the tune the Go's music.ym recorded; the sound CPU plays it) and
//            writes no YM register itself; the harness plays the host, pushing
//            the Go's music.ym frame into the machine's YM mirror, and the
//            three meters track registers 8/10/9
//   raster   the window carries more than the 16 static palette colours
//   leave    Space and Escape both hand the screen back to the menu
//   soak     no zg.mem allocation refused; ms/frame reported, not budgeted
//   node apps/larcociel5_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200;
const OUT = process.argv[2] || "/tmp/larcociel5";
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
const cartBytes = await readFile("docs/demo-larcociel5.wasm");
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
const A = "apps/zig/assets/screens/larcociel5/";
const bg = await readFile(A + "bg.idx");
const ribbon = await readFile(A + "ribbon.bin");
const bats = await readFile(A + "bats.bin");
const palRaw = await readFile(A + "palette.bin");
const rastRaw = await readFile(A + "raster.bin");
const fc = await readFile(A + "font-colors.bin");
const msg = await readFile(A + "message.txt");
const motion = await readFile(A + "initial-motion.bin");
const hist0 = await readFile(A + "initial-history.bin");
const seq = await readFile(A + "music.seq");

const BE16 = (b, o) => (b[o] << 8) | b[o + 1];
const rgbw = (w) => [((w >> 8) & 7) * 34, ((w >> 4) & 7) * 34, (w & 7) * 34];
const pack = ([r, g, b]) => (r << 16) | (g << 8) | b;
const PAL = Array.from({ length: 16 }, (_, i) => pack(rgbw(BE16(palRaw, i * 2))));
const RAST = Array.from({ length: 64 }, (_, i) => pack(rgbw(i < 33 ? BE16(rastRaw, i * 2) : 0x700)));
const fontword = (g, r, c) => BE16(fc, (g * 255 + r * 15 + c) * 2);

function glyphIndex(ch) {
    if (ch === 32) return 0;
    if (ch === 46) return 27;
    if (ch === 44) return 28;
    if (ch === 39) return 29;
    return Math.max(0, Math.min(26, ch - 64));
}

// ---- the ribbon clock (integer/source/clock.go; int16 wraps) ----------------
const s16 = (v) => (v > 32767 ? v - 65536 : v);
const w16 = (x) => ((x + 32768) & 0xFFFF) - 32768;
function newClock() {
    const w = (a) => s16((motion[a] << 8) | motion[a + 1]);
    return {
        tick: 0, counter: 0, hold: 62,
        x: w(4), y: w(10), vx: w(0), vy: w(6), ax: w(2), ay: w(8),
        history: Array.from({ length: 50 }, (_, i) => s16((hist0[i * 2] << 8) | hist0[i * 2 + 1])),
    };
}
function stepClock(c) {
    c.tick++;
    if (c.tick % 320 === 0) c.hold = 61;
    c.history = c.history.slice(1, 50).concat([0]);
    if (c.hold > 0) c.hold--;
    else {
        c.x = w16(c.x + c.vx); c.y = w16(c.y + c.vy); c.counter++;
        if (c.counter === 5) {
            c.counter = 0;
            c.vx = w16(c.vx + c.ax); c.vy = w16(c.vy + c.ay);
            if (c.vx === 6 || c.vx === -6) c.ax = w16(-c.ax);
            if (c.vy === 3 || c.vy === -3) c.ay = w16(-c.ay);
        }
    }
    c.history[49] = c.x;
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

// ---- the perspective colour bank (scrolling.GlyphWindow) --------------------
const stencil = new Uint32Array(272 * 15);
const colors = new Uint32Array(100 * 16);
function buildColors(tick) {
    const position = tick > 0 ? tick - 1 : 0;
    const current = Math.floor(position / 17) % msg.length;
    const off = position % 17;
    stencil.fill(0);
    for (let slot = 0; slot < 16; slot++) {
        const ch = current + slot < msg.length ? msg[current + slot] : 32;
        const g = glyphIndex(ch);
        const top = slot * 17 - off;
        for (let row = 0; row < 17; row++) {
            const y = top + row;
            if (y < 0 || y >= 272) continue;
            for (let col = 0; col < 15; col++) {
                const w = fontword(g, row, col);
                stencil[y * 15 + col] = (((w >> 8) & 7) * 34 << 16) | (((w >> 4) & 7) * 34 << 8) | ((w & 7) * 34);
            }
        }
    }
    colors.fill(0);
    let out = 0, phase = 0, stepv = 20, row = 0;
    while (out < 100 && row < 272) {
        phase += stepv;
        if (phase < 80) { row++; continue; }
        phase -= 80; stepv++;
        for (let col = 0; col < 15; col++) colors[out * 16 + col + 1] = stencil[row * 15 + col];
        out++; row++;
    }
    return colors;
}

const body = new Uint8Array(W * H);
function renderFrame(tick, clock, ymRegs, withBats) {
    const col = buildColors(tick);
    body.fill(0);
    for (let r = 0; r < 50; r++) {
        const Y = clock.y + r;
        if (Y < 0 || Y >= H) continue;
        for (let x = 0; x < 112; x++) {
            const v = ribbon[r * 112 + x];
            if (!v) continue;
            const dx = x + clock.history[r];
            if (dx < 0 || dx >= W) continue;
            body[Y * W + dx] = v & 3;
        }
    }
    let batK = null;
    if (withBats)
        batK = [
            15 - Math.max(1, ymRegs[8] & 15),
            15 - Math.max(1, ymRegs[10] & 15),
            15 - Math.max(1, ymRegs[9] & 15),
        ];
    const out = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) {
            let i = bg[y * W + x];
            const b = body[y * W + x];
            if (b) i = (i & ~3) | b;
            if (y < 32) {
                let hit = false;
                if (batK) {
                    const rx = x & 127;
                    if (rx < 64) {
                        const o = y * 64 + rx;
                        hit = (bats[batK[x >> 7] * 256 + (o >> 3)] >> (7 - (o & 7))) & 1;
                    }
                }
                i = (i & 3) | (hit ? 4 : 0);
            }
            let c;
            if (y >= 100 && i > 0) c = col[(y - 100) * 16 + i];
            else if (i === 4 && y < 64) c = RAST[y];
            else c = PAL[i];
            const o = (y * W + x) * 3;
            out[o] = (c >> 16) & 255; out[o + 1] = (c >> 8) & 255; out[o + 2] = c & 255;
        }
    }
    return out;
}
function render0() {
    const out = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            let i = bg[y * W + x];
            if (y < 32) i %= 4;
            let c;
            if (y >= 100 && i > 0) c = 0;
            else if (i === 4 && y < 64) c = RAST[y];
            else c = PAL[i];
            const o = (y * W + x) * 3;
            out[o] = (c >> 16) & 255; out[o + 1] = (c >> 8) & 255; out[o + 2] = c & 255;
        }
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
    const png = decodePNG(await readFile(`tools/larcociel5/go_ref/${String(n).padStart(6, "0")}.png`));
    if (png.w !== W || png.h !== H) throw new Error(`go_ref frame ${n}: ${png.w}x${png.h}`);
    goRef.set(n, png.rgb);
}

// ---------------- run ---------------------------------------------------------
const EVERY = 1200; // compare every single frame up to here (24 s at 50 Hz)
const LAST = 19740; // the song is 19737 frames at 50 Hz; run past its loop point
const CHECK = new Set([1500, 2000, 3000, 5000, 8000, 12000, 19736, 19737, 19738, LAST]);

const clock = newClock();
const ym = new YM();
const t0 = performance.now();
let compared = 0, goCompared = 0, distinctMax = 0;
const songRequests = [];
const ymMirror = new Uint8Array(memory.buffer, demo.getYmRegsPointer(), 14);
let at149 = null; // the cart's own clock words at step 149 (the native checkpoint)

// The boot frame: init() draws the Go's 0-update frame (no ribbon, no bats, an
// empty colour bank). Pin it explicitly -- the loop only sees frame 1 onward.
{
    machine.hwClear();
    const want = render0(), got = windowRGB();
    const d = firstPixelDiff(got, want);
    if (d >= 0) throw new Error(pixelErr("boot frame (Go frame 0)", got, want, d));
    const g0 = goRef.get(0);
    const gd0 = firstPixelDiff(got, g0);
    if (gd0 >= 0) throw new Error(pixelErr("boot frame (Go frame 0) vs the Go capture", got, g0, gd0));
    goCompared++;
    compared++;
    await shot(`${OUT}/frame_000000.ppm`, got);
}

for (let f = 0; f <= LAST; f++) {
    const frame = f + 1; // the cart's frame after this one 50 Hz tick
    machine.hwClear();

    // The host's side of the music: the audio thread's YM registers land in
    // the machine's mirror before the frame. Here they are the Go's music.ym
    // frame f, the frame the Go's Update reads on this tick.
    ym.applyOne();
    ymMirror.set(ym.regs);
    stepClock(clock);

    demo.frame(TICK_MS);

    // --- the music: one song request, and no YM write from the cart ---
    const n = demo.pollSfx();
    if (n !== 0) throw new Error(`frame ${frame}: the cart queued ${n} sfx/YM writes (the SNDH drives the chip)`);
    if (demo.pollSongRequest() !== 0) {
        const name = Buffer.from(memory.buffer.slice(demo.songNamePtr(), demo.songNamePtr() + demo.songNameLen())).toString();
        songRequests.push(`${name}#${demo.songTune()}@${frame}`);
    }

    // --- the clock words, every frame ---
    if (demo.lcTick() !== clock.tick) throw new Error(`frame ${frame}: lcTick ${demo.lcTick()} != ${clock.tick}`);
    const cw = [clock.counter, clock.hold, clock.x, clock.y, clock.vx, clock.vy, clock.ax, clock.ay];
    for (let i = 0; i < cw.length; i++)
        if (demo.lcField(i + 1) !== cw[i])
            throw new Error(`frame ${frame}: clock field ${i + 1} is ${demo.lcField(i + 1)} but the model says ${cw[i]}`);
    for (let i = 0; i < 50; i++)
        if (demo.lcHistory(i) !== clock.history[i])
            throw new Error(`frame ${frame}: history ${i} is ${demo.lcHistory(i)} but the model says ${clock.history[i]}`);
    if (frame === 149) at149 = {
        velocity: [demo.lcField(5), demo.lcField(6)],
        acceleration: [demo.lcField(7), demo.lcField(8)],
        position: [demo.lcField(3), demo.lcField(4)],
        counter: demo.lcField(1),
        hold: demo.lcField(2),
        history: Array.from({ length: 50 }, (_, i) => demo.lcHistory(i)),
    };

    // --- the registers the meters read, and the three meters ---
    for (let i = 0; i < 14; i++)
        if (demo.lcYmReg(i) !== ym.regs[i])
            throw new Error(`frame ${frame}: the meters read YM reg ${i} = ${demo.lcYmReg(i)} but the mirror holds ${ym.regs[i]}`);
    const mwant = [Math.max(1, ym.regs[8] & 15), Math.max(1, ym.regs[10] & 15), Math.max(1, ym.regs[9] & 15)];
    for (let i = 0; i < 3; i++)
        if (demo.lcMeters(i) !== mwant[i])
            throw new Error(`frame ${frame}: meter ${i} is ${demo.lcMeters(i)} but the model says ${mwant[i]}`);

    // --- the pixels ---
    if (frame <= EVERY || CHECK.has(frame)) {
        const want = renderFrame(frame, clock, ym.regs, true);
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

ok(songRequests.length === 1 && songRequests[0] === "cybernoid2.sndh#1@1",
    `the cart asks for cybernoid2.sndh #1 once, on its first frame (got ${songRequests.join(", ") || "none"})`);
ok(compared >= EVERY + CHECK.size, `${compared} frames compared pixel for pixel (the boot frame, every frame to ${EVERY}, plus the loop and soak checkpoints)`);
ok(goCompared === GO_FRAMES.length, `${goCompared} frames compared to the Go re-creation's own captured PNGs (0..1199)`);

// The Go tree's native checkpoint, from apps/.../native-ribbon-149.json: the
// LIVE cart's own clock words at step 149.
{
    const want = JSON.parse(await readFile("tools/larcociel5/native-ribbon-149.json", "utf8"));
    const eq = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
    const good = at149 &&
        eq(at149.position, want.position) && eq(at149.velocity, want.velocity) &&
        eq(at149.acceleration, want.acceleration) &&
        at149.counter === want.counter && at149.hold === want.hold &&
        eq(at149.history, want.history);
    ok(!!good, `the live ribbon clock at step ${want.steps} equals the Go tree's native-ribbon-149.json checkpoint`);
}

// A raster, not a static palette: the window carries more colours than the 16
// palette words alone can (entries 4 and 1..15 really are rewritten per line).
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

ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
console.log(`  ${(ms / (LAST + 1)).toFixed(3)} ms/frame over ${LAST + 1} frames (update + render + composite + model)`);

const total = errors.length;
console.log(total === 0 ? "larcociel5: PASS" : `larcociel5: FAILED (${total})`);
process.exit(total ? 1 : 0);
