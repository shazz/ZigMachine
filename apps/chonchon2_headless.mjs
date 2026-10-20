// Headless CHONCHON 2 driver (cart 100). The production is
// github.com/olivierh59500/go-chonchon2, a Go/Ebitengine re-creation of a
// DMA / Chon-Chon ST intro. This harness holds the Zig cart to it, end to end,
// WITHOUT a Go toolchain: it re-implements the port's exact algorithm here
// (the authored motion clock, the ribbon glyph bank, the sliding panels, both
// sprite paths, the seven YM delta streams, the three meters and the two
// per-line rasters), reads the SAME ripped assets the cart embeds, and compares
// the machine's rendered 320x200 window to the model's, pixel for pixel.
//
//   model    every frame to 24 s and at the loop/late checkpoints, the
//            composited window is the model's RGB -- which validates the
//            background, ribbon, panels, both sprites, meters and the per-line
//            rasters TOGETHER, since a wrong colour on any line is a mismatch
//   clock    c2Tick()/c2Field()/c2Pose() equal the model's words every frame,
//            and the glyph, ribbon and 32000-byte screen hashes match too
//   music    the first request is Jinks.sndh #1; F1..F7 select the production's
//            seven tracks (five SNDHs, two .ymraw dumps with no SNDH), and the
//            cart's embedded YM mirror equals the model's every frame
//   raster   the window carries more than the 16 static palette colours
//   leave    Space and Escape both hand the screen back to the menu
//   soak     no zg.mem allocation refused; ms/frame reported, not budgeted
//   usage    node apps/chonchon2_headless.mjs [outdir] [--break mode]
//            break modes: pixel, clock, music, yms -- each is caught and the
//            break run then exits 0; a real failure exits 1.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200;
const TICK_MS = 20.0; // the cart's 50 Hz step; the harness gives exactly one tick a frame
const BREAKS = new Set(["pixel", "clock", "music", "yms"]);

let OUT = "/tmp/chonchon2";
let BRK = null;
{
    const args = process.argv.slice(2);
    for (let i = 0; i < args.length; i++) {
        if (args[i] === "--break") {
            BRK = args[++i] ?? "";
            if (!BREAKS.has(BRK)) throw new Error(`--break takes one of: ${[...BREAKS].join(", ")}`);
        } else OUT = args[i];
    }
}

// ---------------- boot (the chonchon/larcociel shape) ------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-chonchon2.wasm");
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
const dec = new TextDecoder();

function takeSong() {
    if (!demo.pollSongRequest()) return null;
    const name = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    return { name, tune: demo.songTune() };
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
const A = "apps/zig/assets/screens/chonchon2/";
const background = await readFile(A + "background.bin");
const font = await readFile(A + "font.bin");
const message = await readFile(A + "message.bin");
const profile = await readFile(A + "scroll-profile.bin");
const panel = await readFile(A + "panel-script.bin");
const panelPattern = await readFile(A + "panel-pattern.bin");
const pathA = await readFile(A + "sprite-a-path.bin");
const pathB = await readFile(A + "sprite-b-path.bin");
const palRaw = await readFile(A + "palette.bin");
const rasterBgRaw = await readFile(A + "raster-background.bin");
const rasterProgram = await readFile(A + "raster-program.bin");
const rasterBaseRaw = await readFile(A + "raster-base.bin");
const rasterScroll = await readFile(A + "raster-scroll.bin");
const spriteA = await readFile(A + "sprite-a.idx");
const spriteB = await readFile(A + "sprite-b.idx");
const seqs = [];
for (let n = 1; n <= 7; n++) seqs.push(await readFile(A + `music-${n}.seq`));

const be16 = (b, o) => (b[o] << 8) | b[o + 1];
const be32 = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
const s16 = (v) => (v & 0x8000 ? v - 0x10000 : v);
const rgbw = (w) => [((w >> 8) & 7) * 34, ((w >> 4) & 7) * 34, (w & 7) * 34];
// Color.toRGBA order, exactly as zigos/assets.rgbw packs the HBL entries:
// a<<24 | b<<16 | g<<8 | r.
const pack = ([r, g, b]) => ((255 << 24) | (b << 16) | (g << 8) | r) >>> 0;
const PAL = Array.from({ length: 16 }, (_, i) => pack(rgbw(be16(palRaw, i * 2))));
const BG = new Int32Array(200);
const FG = new Int32Array(200);

function updateRaster(tick, oldY) {
    const bgw = new Uint16Array(200), fgw = new Uint16Array(200);
    for (let y = 0; y < 200; y++) {
        bgw[y] = be16(rasterBgRaw, y * 2);
        fgw[y] = be16(rasterBaseRaw, y * 2);
    }
    const count = rasterProgram.length / 180;
    let frame = tick;
    if (frame >= count) frame = 25 + (frame - count) % Math.max(1, count - 25);
    for (let i = 0; i < 90; i++) bgw[68 + i] = be16(rasterProgram, frame * 180 + i * 2);
    const at = oldY * 2;
    if (at >= 0 && at + rasterScroll.length <= 400)
        for (let i = 0; i < rasterScroll.length / 2; i++) fgw[oldY + i] = be16(rasterScroll, i * 2);
    for (let y = 0; y < 200; y++) {
        BG[y] = pack(rgbw(bgw[y]));
        FG[y] = pack(rgbw(fgw[y]));
    }
}

// ---- the native motion (internal/source/clock.go) ---------------------------
const screen = new Uint8Array(32000);
const glyph = new Uint8Array(184);
const ribbon = Array.from({ length: 23 }, () => new Uint8Array(320));
const clock = {
    tick: 0, profileCursor: 0, messageCursor: 0, glyphColumn: 0, glyphCounter: 4,
    scrollY: 70, oldY: 0, spriteCursor: [0, 0],
    captionCursor: 0, captionHold: 1, captionWait: 100, captionShift: 0,
    poses: [{ x: 0, y: 0, half: false }, { x: 0, y: 0, half: false }],
};
function pixel(x, y, v) {
    const at = y * 160 + ((x / 16) | 0) * 8;
    const mask = 1 << (15 - x % 16);
    for (let p = 0; p < 4; p++) {
        let w = be16(screen, at + p * 2);
        w &= ~mask;
        if ((v >> p) & 1) w |= mask;
        screen[at + p * 2] = (w >>> 8) & 255;
        screen[at + p * 2 + 1] = w & 255;
    }
}
function stepClock() {
    clock.tick++;
    screen.set(background);
    if (clock.profileCursor + 6 > profile.length || s16(be16(profile, clock.profileCursor)) < 0)
        clock.profileCursor = 0;
    clock.oldY = clock.scrollY;
    clock.scrollY = (be16(profile, clock.profileCursor) / 160) | 0;
    clock.profileCursor += 6;

    if (clock.glyphCounter === 4) {
        clock.glyphCounter = 0;
        if (clock.messageCursor + 4 > message.length) clock.messageCursor = 0;
        if (s16(be16(message, clock.messageCursor)) < 0) {
            clock.glyphCounter = 2;
            clock.messageCursor += 4;
        }
        const off = be32(message, clock.messageCursor);
        clock.messageCursor += 4;
        glyph.fill(0);
        if (off + 184 <= font.length) glyph.set(font.subarray(off, off + 184));
    }

    for (let row = 0; row < 23; row++) {
        ribbon[row].copyWithin(0, 8);
        for (let x = 0; x < 8; x++) {
            let index = 0;
            for (let plane = 0; plane < 2; plane++) {
                const at = row * 8 + ((clock.glyphColumn / 2) | 0) * 4 + plane * 2 + clock.glyphColumn % 2;
                index |= ((glyph[at] >> (7 - x)) & 1) << plane;
            }
            ribbon[row][312 + x] = index;
        }
        const y = clock.scrollY + row;
        if (y >= 0 && y < 200)
            for (let x = 0; x < 320; x++) pixel(x, y, ribbon[row][x]);
    }
    clock.glyphColumn = (clock.glyphColumn + 1) % 4;
    clock.glyphCounter++;

    for (let i = 0; i < 2; i++) {
        const path = i === 0 ? pathA : pathB;
        let p = clock.spriteCursor[i];
        if (p + 4 > path.length || s16(be16(path, p)) < 0) p = 0;
        const off = be16(path, p);
        clock.poses[i] = {
            x: ((off % 160) / 8 | 0) * 16 + ((off % 8) / 4 | 0) * 8,
            y: (off / 160) | 0,
            half: s16(be16(path, p + 2)) < 0,
        };
        clock.spriteCursor[i] = p + 4;
    }

    if (panelPattern.length >= 69 * 160 && clock.captionCursor + 4 < panel.length) {
        const y = be16(panel, clock.captionCursor);
        const rows = be16(panel, clock.captionCursor + 2);
        for (let row = 0; row <= rows; row++) {
            const yy = y + row;
            if (yy < 0 || yy >= 69) continue;
            const src = yy * 160 + clock.captionShift * 16;
            const dst = yy * 160 + 0x200;
            for (let k = 0; k < 16; k++) {
                screen[dst + k] = panelPattern[src + k];
                screen[dst + 80 + k] = panelPattern[src + k];
            }
        }
    }

    clock.captionWait--;
    if (clock.captionWait <= 0) {
        clock.captionShift = (clock.captionShift + 1) % 10;
        if (clock.captionShift === 0) {
            clock.captionHold--;
            if (clock.captionHold < 0) {
                clock.captionCursor += 6;
                if (clock.captionCursor + 6 > panel.length || s16(be16(panel, clock.captionCursor)) < 0)
                    clock.captionCursor = 0;
                clock.captionHold = be16(panel, clock.captionCursor + 4);
            }
        }
        clock.captionWait = 2;
    }
}
stepClock();
clock.tick = 0; // NewClock
updateRaster(0, clock.oldY); // init()'s first tables

// ---- the three music meters (internal/demo/game.go Update) ------------------
function applyMeter(regs) {
    for (let ch = 0; ch < 3; ch++) {
        const volume = regs[8 + ch] & 15;
        for (let row = 0; row < 7; row++)
            for (let cell = 0; cell <= volume; cell++) {
                const off = 0x6868 + ch * 0x5a0 + row * 160 + cell * 8;
                if (off + 4 > screen.length) continue;
                screen[off] = 0; screen[off + 1] = 0;
                screen[off + 2] = 255; screen[off + 3] = 255;
            }
    }
}

// ---- the seven YM delta streams --------------------------------------------
const streams = seqs.map((seq) => {
    const frames = seq.readUInt32LE(0);
    const offs = new Array(frames);
    let o = 4;
    for (let f = 0; f < frames; f++) {
        const mask = seq[o] | (seq[o + 1] << 8); o += 2;
        let n = 0;
        for (let m = mask; m; m >>= 1) n += m & 1;
        offs[f] = { voff: o, mask }; o += n;
    }
    return { seq, frames, offs };
});
class YM {
    constructor() { this.track = 0; this.next = 0; this.applied = 0; this.regs = new Uint8Array(14); }
    get frames() { return streams[this.track].frames; }
    select(track) {
        this.track = track;
        this.next = 0;
        this.applied = 0;
        this.regs.fill(0);
    }
    step() {
        const s = streams[this.track], fr = s.offs[this.next];
        let o = fr.voff;
        for (let r = 0; r < 14; r++)
            if (fr.mask & (1 << r)) this.regs[r] = s.seq[o++];
        this.next = (this.next + 1) % s.frames;
        this.applied++;
    }
}
const ym = new YM();
ym.select(0);

// ---- the index image + both opaque sprite rectangles ------------------------
function decodeScreen() {
    const idx = new Uint8Array(W * H);
    for (let group = 0; group < 4000; group++) {
        const at = group * 8;
        const p0 = be16(screen, at), p1 = be16(screen, at + 2);
        const p2 = be16(screen, at + 4), p3 = be16(screen, at + 6);
        for (let x = 0; x < 16; x++) {
            const sh = 15 - x;
            idx[group * 16 + x] = ((p0 >> sh) & 1) | (((p1 >> sh) & 1) << 1) |
                (((p2 >> sh) & 1) << 2) | (((p3 >> sh) & 1) << 3);
        }
    }
    return idx;
}
function drawSprite(idx, image, w, h, pose, tick, wrap) {
    for (let row = 0; row < h; row++) {
        const sourceY = wrap && row >= 2 && row < 32 ? 2 + (tick + row - 2) % 192 : row;
        const y = pose.y + row;
        if (y < 0 || y >= H) continue;
        for (let dx = 0; dx < w; dx++) {
            const x = pose.x + dx;
            if (x < 0 || x >= W) continue;
            idx[y * W + x] = image[sourceY * w + dx];
        }
    }
}
function renderIdx(idx, live) {
    if (live) {
        drawSprite(idx, spriteA, 80, 34, clock.poses[0], clock.tick, false);
        drawSprite(idx, spriteB, 80, 194, clock.poses[1], clock.tick, true);
    }
    const out = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const i = idx[y * W + x];
            const c = i === 0 ? BG[y] : i === 2 ? FG[y] : PAL[i];
            const o = (y * W + x) * 3;
            out[o] = c & 255; out[o + 1] = (c >> 8) & 255; out[o + 2] = (c >> 16) & 255;
        }
    return out;
}
function renderFrame() { return renderIdx(decodeScreen(), true); }
function renderBoot() { return renderIdx(new Uint8Array(W * H), false); }

// ---- hash the same three byte ranges the cart's testapi hashes --------------
function fnv(bytes) {
    let h = 0x811c9dc5;
    for (const b of bytes) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h;
}
function ribbonHash() {
    let h = 0x811c9dc5;
    for (const line of ribbon) for (const b of line) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h;
}

// ==========================================================================
// Run. The boot frame is the Go's never-drawn pre-first-Update state: the cart
// clears the plane and the HBL still paints index 0 with Background[y].
// ==========================================================================
const TRACKS = [
    ["Jinks.sndh", 1], ["lockbuster2_rollout.sndh", 1], ["lockbuster2_rollout.sndh", 2],
    ["so_watt_no_crew.sndh", 1], ["chonchon2_music-5.ymraw", 0],
    ["chonchon2_music-6.ymraw", 0], ["union/alloy_run.sndh", 1],
];
const EVERY = 1200; // compare every single frame up to here (24 s at 50 Hz)
const LAST = 2400; // past track 1's 2304-frame loop point
const CHECK = new Set([1400, 1800, 2000, 2299, 2300, 2303, 2304, 2305, 2400]);

let compared = 0, distinctMax = 0, songs = 0, frames = 0;
try {
    // The initial request: Jinks #1, the production's default music-1.
    {
        const got = takeSong();
        const want = BRK === "music" ? ["not-the-right-tune.sndh", 1] : TRACKS[0];
        if (!got || got.name !== want[0] || got.tune !== want[1])
            throw new Error(`first song request is ${JSON.stringify(got)}, expected ${want[0]} #${want[1]}`);
        songs++;
    }

    // Boot frame.
    {
        machine.hwClear();
        const want = renderBoot();
        if (BRK === "pixel") want[0] ^= 0x80;
        const got = windowRGB();
        const d = firstPixelDiff(got, want);
        if (d >= 0) throw new Error(pixelErr("boot frame", got, want, d));
        compared++;
        await shot(`${OUT}/frame_boot.ppm`, got);
    }

    const t0 = performance.now();
    for (let f = 0; f <= LAST; f++) {
        const frame = f + 1;
        machine.hwClear();

        stepClock();
        ym.step();
        applyMeter(ym.regs);
        updateRaster(clock.tick, clock.oldY);

        if (BRK === "clock" && frame === 1) clock.tick++;
        if (BRK === "yms" && frame === 1) ym.regs[0] ^= 1;

        demo.frame(TICK_MS);
        frames++;

        if (takeSong() !== null)
            throw new Error(`frame ${frame}: the cart requested a song mid-track`);
        if (demo.pollSfx() !== 0)
            throw new Error(`frame ${frame}: the cart made a direct sfx write (the host's song owns the YM)`);

        if (demo.c2Tick() !== clock.tick)
            throw new Error(`frame ${frame}: c2Tick ${demo.c2Tick()} != ${clock.tick}`);
        const cw = [clock.profileCursor, clock.messageCursor, clock.glyphColumn, clock.glyphCounter,
            clock.scrollY, clock.oldY, clock.spriteCursor[0], clock.spriteCursor[1],
            clock.captionCursor, clock.captionHold, clock.captionWait, clock.captionShift];
        for (let i = 0; i < cw.length; i++)
            if (demo.c2Field(i + 1) !== cw[i])
                throw new Error(`frame ${frame}: clock field ${i + 1} is ${demo.c2Field(i + 1)} but the model says ${cw[i]}`);
        for (let k = 0; k < 2; k++) {
            const p = clock.poses[k];
            const got = [demo.c2Pose(k, 0), demo.c2Pose(k, 1), demo.c2Pose(k, 2)];
            const want = [p.x, p.y, p.half ? 1 : 0];
            for (let i = 0; i < 3; i++)
                if (got[i] !== want[i])
                    throw new Error(`frame ${frame}: pose ${k} field ${i} is ${got[i]} but the model says ${want[i]}`);
        }
        if ((demo.c2GlyphHash() >>> 0) !== fnv(glyph)) {
            let bad = "";
            for (let i = 0; i < glyph.length; i++)
                if (demo.c2GlyphByte(i) !== glyph[i]) { bad = ` (glyph[${i}] ${demo.c2GlyphByte(i)} != ${glyph[i]})`; break; }
            throw new Error(`frame ${frame}: glyph hash ${demo.c2GlyphHash()} != ${fnv(glyph)}${bad}`);
        }
        if ((demo.c2RibbonHash() >>> 0) !== ribbonHash()) {
            let bad = "";
            outer: for (let row = 0; row < 23; row++)
                for (let col = 0; col < 320; col++)
                    if (demo.c2RibbonByte(row, col) !== ribbon[row][col]) {
                        bad = ` (ribbon[${row}][${col}] ${demo.c2RibbonByte(row, col)} != ${ribbon[row][col]})`;
                        break outer;
                    }
            throw new Error(`frame ${frame}: ribbon hash ${demo.c2RibbonHash()} != ${ribbonHash()}${bad}`);
        }
        if ((demo.c2ScreenHash() >>> 0) !== fnv(screen)) {
            let bad = "";
            for (let i = 0; i < screen.length; i++)
                if (demo.c2ScreenByte(i) !== screen[i]) { bad = ` (screen[${i}] ${demo.c2ScreenByte(i)} != ${screen[i]})`; break; }
            throw new Error(`frame ${frame}: screen hash ${demo.c2ScreenHash()} != ${fnv(screen)}${bad}`);
        }
        for (let i = 0; i < 200; i++) {
            if ((demo.c2Bg(i) >>> 0) !== (BG[i] >>> 0))
                throw new Error(`frame ${frame}: Background[${i}] is ${demo.c2Bg(i)} but the model says ${BG[i]}`);
            if ((demo.c2Fg(i) >>> 0) !== (FG[i] >>> 0))
                throw new Error(`frame ${frame}: Foreground[${i}] is ${demo.c2Fg(i)} but the model says ${FG[i]}`);
        }
        for (let i = 0; i < 14; i++)
            if (demo.c2YmReg(i) !== ym.regs[i])
                throw new Error(`frame ${frame}: YM reg ${i} is ${demo.c2YmReg(i)} but the model says ${ym.regs[i]}`);
        for (let i = 0; i < 3; i++)
            if (demo.c2Meters(i) !== (ym.regs[8 + i] & 15))
                throw new Error(`frame ${frame}: meter ${i} is ${demo.c2Meters(i)} but the model says ${ym.regs[8 + i] & 15}`);
        if (demo.c2YmTrack() !== ym.track || demo.c2YmApplied() !== ym.applied ||
            demo.c2YmFrames() !== ym.frames)
            throw new Error(`frame ${frame}: YM stream state differs (track ${demo.c2YmTrack()}/${ym.track}, ` +
                `applied ${demo.c2YmApplied()}/${ym.applied}, frames ${demo.c2YmFrames()}/${ym.frames})`);
        if (demo.c2Drawn() !== 1) throw new Error(`frame ${frame}: c2Drawn is 0 after an Update`);

        if (frame <= EVERY || CHECK.has(frame)) {
            const want = renderFrame();
            const got = windowRGB();
            const d = firstPixelDiff(got, want);
            if (d >= 0) throw new Error(pixelErr(`frame ${frame}`, got, want, d));
            compared++;
            const seen = new Set();
            for (let i = 0; i < want.length; i += 3) seen.add((want[i] << 16) | (want[i + 1] << 8) | want[i + 2]);
            if (seen.size > distinctMax) distinctMax = seen.size;
            if (frame === 1 || frame === 100 || frame === 800 || frame === 1200 ||
                frame === 2304 || frame === 2305 || frame === LAST)
                await shot(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, got);
        }
    }
    const ms = performance.now() - t0;

    // F1..F7: the production's seven tracks and their first stream frame.
    for (let i = 0; i < 7; i++) {
        demo.key(0xE001 + i);
        const got = takeSong();
        const want = TRACKS[i];
        if (!got || got.name !== want[0] || got.tune !== want[1])
            throw new Error(`F${i + 1} requests ${JSON.stringify(got)}, expected ${want[0]} #${want[1]}`);
        songs++;
        ym.select(i);

        machine.hwClear();
        stepClock();
        ym.step();
        applyMeter(ym.regs);
        updateRaster(clock.tick, clock.oldY);
        demo.frame(TICK_MS);
        frames++;

        if (demo.c2YmTrack() !== i) throw new Error(`F${i + 1}: c2YmTrack ${demo.c2YmTrack()} != ${i}`);
        for (let r = 0; r < 14; r++)
            if (demo.c2YmReg(r) !== ym.regs[r])
                throw new Error(`F${i + 1}: YM reg ${r} is ${demo.c2YmReg(r)} but the model says ${ym.regs[r]}`);
        for (let r = 0; r < 3; r++)
            if (demo.c2Meters(r) !== (ym.regs[8 + r] & 15))
                throw new Error(`F${i + 1}: meter ${r} is ${demo.c2Meters(r)} but the model says ${ym.regs[8 + r] & 15}`);
        if (demo.c2ScreenHash() >>> 0 !== fnv(screen))
            throw new Error(`F${i + 1}: screen hash differs from the model`);
        const wantPx = renderFrame(), gotPx = windowRGB();
        const d = firstPixelDiff(gotPx, wantPx);
        if (d >= 0) throw new Error(pixelErr(`F${i + 1} first frame`, gotPx, wantPx, d));
        compared++;
    }

    // A raster, not a static palette.
    ok(distinctMax > 16, `the per-line rasters put ${distinctMax} distinct colours on the window (a static palette gives <= 16)`);

    // The border bands above/below the visible line are black.
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

    ok((demo.c2Pal(0) & 0xffffff) === 0, "the static palette's colour 0 is the ST black the border asks for");
    ok(songs === 8, `${songs} song requests: the default plus F1..F7, each by name and matching its stream`);
    ok(frames >= LAST + 1, `${frames} 50 Hz frames stepped through the music loop and every F-key`);
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
    console.log(`  ${(ms / (LAST + 1)).toFixed(3)} ms/frame over ${LAST + 1} frames (update + render + composite + model)`);

    if (BRK) {
        console.error(`--break ${BRK} was NOT caught`);
        process.exit(1);
    }
    const total = errors.length;
    console.log(total === 0 ? "chonchon2: PASS" : `chonchon2: FAILED (${total})`);
    process.exit(total ? 1 : 0);
} catch (e) {
    if (BRK) {
        console.log(`  ok   --break ${BRK} caught: ${e.message}`);
        console.log("chonchon2: PASS (break path)");
        process.exit(0);
    }
    console.error(`FAIL: ${e.message}`);
    process.exit(1);
}
