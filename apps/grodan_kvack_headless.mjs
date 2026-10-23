// Headless GRODAN & KVACK KVACK driver (cart 94). The production is
// github.com/olivierh59500/grodan-kvack-kvack-demo, a Go/Ebitengine re-creation
// of The Carebears' 1989 Atari ST demo. This harness holds the Zig cart to it,
// end to end, WITHOUT a Go toolchain: it re-implements the port's exact
// algorithm here -- integer state, u32 fixtrig angles, Q16.16 sprites, the four
// scroll resets, the per-scanline colour tables -- reads the SAME ripped assets
// the cart embeds, and compares the machine's rendered 320x200 window to the
// model's, pixel for pixel.
//
//   model    every frame up to 20 s, and at the scroll resets after it (small2
//            tick 2344, vert tick 4585, small1 tick 7504), the composited
//            window is the model's RGB -- which validates the six layers AND
//            the copper's three raster entries AND the eight palette words
//            together, since a wrong colour on any line is a mismatch
//   state    gkTick()/gkScroll()/gkState() equal the model's own words every
//            frame: a pixel-perfect picture with a drifting counter would not
//            hide here
//   raster   the window carries more than the eight static palette colours
//            (entries 4/5/6 really are rewritten per scanline), and the border
//            bands above/below line 200 stay black
//   leave    Escape hands the screen back to the menu
//   soak     no zg.mem allocation refused; ms/frame reported, not budgeted
//   node apps/grodan_kvack_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const W = 320, H = 200;
const OUT = process.argv[2] || "/tmp/grodan_kvack";
const TICK_MS = Math.fround(1000 / 60); // the cart's 60 Hz step; one tick a frame

// ---------------- boot (the kickoff2 shape: machine + ROM + cart) -----------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-grodan_kvack.wasm");
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
// The cart RAM window starts above the cart's statics, as sealed-loader.js sets
// it: the CHISEL renderer keeps its chunky art in zg.mem (draw.zig/chunky.zig).
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

await mkdir(OUT, { recursive: true });
console.log("boot ok");

const errors = [];
const ok = (cond, msg) => { console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`); if (!cond) errors.push(msg); };

// The screen's own tune: So Watt's ronken.mod (a ProTracker module, no SNDH/YM).
ok(new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen())) === "ronken.mod",
   "it asks for the screen's own ProTracker module (ronken.mod)");

// ---------------- the machine's composited window ---------------------------
const pw = machine.hwPhysWidth(); // 800: low res is x-doubled
const ph = machine.hwPhysHeight(); // 280
const bx = machine.hwBorderX(), by = machine.hwBorderY();
const pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), pw * ph * 4);

/// Render plane 0 and lift out the visible 320x200 window as RGB.
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
/// The left border column, physical line 0..ph-1, as RGB.
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

// ==========================================================================
// The model: the port's exact algorithm, in the port's own fixed point.
// ==========================================================================
const A = "apps/zig/assets/screens/grodan_kvack/";
const readBin = (n) => readFile(A + n);
const bit = (m, x, y, w) => (m[(y * w + x) >> 3] >> (7 - ((y * w + x) & 7))) & 1;

const BG_W = 320, BG_H = 199;
const bgG = await readBin("bg_green.raw"), bgP = await readBin("bg_pink.raw");
const spr = await readBin("sprite.raw"), bsf = await readBin("bsfont.raw");
const upf = await readBin("upfont.raw"), lf = await readBin("lfont.raw");
const mainCells = await readBin("main.cells"), vertCells = await readBin("vert.cells");
const small1Cells = await readBin("small1.cells"), small2Cells = await readBin("small2.cells");
const bsPal = await readBin("bigraster.pal"), upPal = await readBin("upraster.pal");
const row = (pal, i) => [pal[i * 4], pal[i * 4 + 1], pal[i * 4 + 2]];

const BLACK = 0, GREEN = 1, PINK = 2, SPRITE = 3, BIG = 4, VERT = 5, SMALL = 6, WHITE = 7;

// ---- fixtrig (identical to libs/zig/effects/fixtrig.zig) -------------------
const BITS = 10, NTAB = 1 << BITS, FRAC = 32 - BITS;
const zround = (x) => Math.sign(x) * Math.floor(Math.abs(x) + 0.5); // Zig @round: half away from zero
const TABLE = new Int32Array(NTAB + 1);
for (let i = 0; i <= NTAB; i++) TABLE[i] = zround(Math.sin(i * (2 * Math.PI / NTAB)) * 65536.0);
TABLE[0] = 0; TABLE[NTAB >> 2] = 65536; TABLE[NTAB >> 1] = 0; TABLE[3 * NTAB >> 2] = -65536; TABLE[NTAB] = 0;
const fsin = (a) => {
    a >>>= 0;
    const i = a >>> FRAC, f = (a >>> (FRAC - 16)) & 0xFFFF, s0 = TABLE[i];
    return s0 + (((TABLE[i + 1] - s0) * f) >> 16);
};
const fcos = (a) => fsin((a + 0x40000000) >>> 0);
const fmul = (a, b) => Math.floor((a * b) / 65536); // i64 product >> 16
const angle = (rad) => zround(rad / (2 * Math.PI) * 4294967296.0) >>> 0;
const roundq16 = (v) => Math.floor((v + 32768) / 65536);

const ANG_002 = angle(0.02), ANG_003 = angle(0.03);
const PC = [], PS = [];
for (let i = 0; i < 12; i++) { const a = angle(i * 0.2); PC.push(fcos(a)); PS.push(fsin(a)); }

// ---- the state machine (the Go's Update()) ---------------------------------
class Scroll {
    constructor(cells, adv, speed, vertical) {
        this.g = cells; this.adv = adv; this.speed = speed; this.vertical = vertical;
        this.n = cells.length; this.content = adv * cells.length; this.scroll = vertical ? -100 : 0;
    }
    update() {
        if (this.vertical) {
            this.scroll += this.speed;
            if (this.scroll > this.content + 400) this.scroll = -100;
        } else {
            this.scroll -= this.speed;
            // The Go resets to screenWidth = 640, its FONT-PX units: our screen is
            // 320 but this constant stays the Go's 640.
            if (this.scroll < -this.content) this.scroll = 640;
        }
    }
}
function makeState() {
    const s = {
        moveY: 0, howmuchY: 1, moveX: 0, howmuchX: 1, bgcount: 0,
        Y: 0, hY: 1, X: 0, gox: 0, ychange10: 0, addy10: 1, swing: 0, swingy: 0,
    };
    s.s1 = new Scroll(mainCells, 24, 2, false);
    s.s2 = new Scroll(vertCells, 29, 3, true);
    s.s3 = new Scroll(small1Cells, 8, 1, false);
    s.s4 = new Scroll(small2Cells, 8, 2, false);
    return s;
}
function update(s) {
    s.bgcount += 1;
    if (s.moveY < -400) s.howmuchY = 1;
    if (s.moveY > 0) s.howmuchY = -1;
    s.moveY += s.howmuchY;
    if (s.bgcount >= 101) {
        if (s.moveX < -640 * 2) s.howmuchX = 16;
        if (s.moveX > 0) s.howmuchX = -16;
        s.moveX += s.howmuchX;
    }
    if (s.bgcount >= 200) s.bgcount = 0;
    if (s.Y < -400) { s.hY = 2; s.gox = 16; }
    if (s.Y > 0) { s.hY = -2; s.gox = -16; }
    s.X += s.gox;
    if (s.X < -710) s.X = -710;
    if (s.X > 0) s.X = 0;
    s.Y += s.hY;
    if (s.ychange10 >= 500) s.addy10 = -1;
    if (s.ychange10 <= -500) s.addy10 = 1;
    s.ychange10 += s.addy10;
    s.swing = (s.swing + ANG_002) >>> 0;
    s.swingy = (s.swingy + ANG_003) >>> 0;
    for (const sc of [s.s1, s.s3, s.s4, s.s2]) sc.update();
}

// ---- compose: six layers into an index plane, then per-line colour ---------
function blitMask(out, m, mw, mh, idx, dx, dy) {
    const x0 = Math.max(dx, 0), y0 = Math.max(dy, 0);
    const x1 = Math.min(dx + mw, W), y1 = Math.min(dy + mh, H);
    for (let y = y0; y < y1; y++) {
        const my = y - dy;
        for (let x = x0; x < x1; x++)
            if (bit(m, x - dx, my, mw)) out[y * W + x] = idx;
    }
}
function tile(out, m, idx, ox, oy) {
    const x_off = Math.floor(ox / 2), y_off = Math.floor(oy / 2);
    for (let yy = 0; yy < 2; yy++) {
        const ty = y_off + 200 * yy;
        if (ty >= H || ty + BG_H <= 0) continue;
        for (let xx = 0; xx < 3; xx++) {
            const tx = x_off + W * xx;
            if (tx >= W || tx + BG_W <= 0) continue;
            blitMask(out, m, BG_W, BG_H, idx, tx, ty);
        }
    }
}
function sprites(out, s) {
    const cosSwing = fcos(s.swing), sinSwing = fsin(s.swing);
    const sinY = fsin(s.swingy), cosY = fcos(s.swingy);
    for (let i = 0; i < 12; i++) {
        const cs = fmul(cosSwing, PC[i]) + fmul(sinSwing, PS[i]);
        const ssy = fmul(sinY, PC[i]) - fmul(cosY, PS[i]);
        const xq = (152 << 16) + 145 * cs;
        const yq = (50 << 16) + Math.floor(s.ychange10 * (ssy + sinY) / 20);
        const x0 = roundq16(xq), y0 = roundq16(yq);
        for (let sy = 0; sy < 10; sy++) {
            const y = y0 + sy; if (y < 0 || y >= H) continue;
            for (let sx = 0; sx < 16; sx++) {
                const x = x0 + sx; if (x < 0 || x >= W) continue;
                if (bit(spr, i * 17 + sx, sy, 204)) out[y * W + x] = SPRITE;
            }
        }
    }
}
function glyphBig(out, cell, x0) {
    const col = cell % 10, row = (cell / 10) | 0;
    for (let dy = 0; dy < 99; dy++) {
        const srcrow = row * 33 + ((dy / 3) | 0), y = 100 + dy;
        for (let dx = 0; dx < 96; dx++) {
            const x = x0 + dx; if (x < 0 || x >= W) continue;
            if (bit(bsf, col * 24 + ((dx / 4) | 0), srcrow, 240)) out[y * W + x] = BIG;
        }
    }
}
function glyphUp(out, cell, x0, y0) {
    const col = cell % 10, row = (cell / 10) | 0;
    for (let dy = 0; dy < 15; dy++) {
        const y = y0 + dy; if (y < 0 || y >= H) continue;
        const srcrow = row * 29 + 2 * dy;
        for (let dx = 0; dx < 16; dx++) {
            const x = x0 + dx; if (x < 0 || x >= W) continue;
            if (bit(upf, col * 33 + 2 * dx, srcrow, 330)) out[y * W + x] = VERT;
        }
    }
}
function glyphSmall(out, cell, x0, y0) {
    const col = cell % 10, row = (cell / 10) | 0;
    for (let dy = 0; dy < 8; dy++) {
        const y = y0 + dy; if (y < 8 || y >= 40) continue;
        for (let dx = 0; dx < 8; dx++) {
            const x = x0 + dx; if (x < 0 || x >= W) continue;
            if (bit(lf, col * 8 + dx, row * 8 + dy, 80)) out[y * W + x] = SMALL;
        }
    }
}
// The three copper tables, one colour a row (the Go's source-atop rasters).
const bigLine = new Uint8Array(H * 3), vertLine = new Uint8Array(H * 3), smallLine = new Uint8Array(H * 3);
for (let y = 0; y < H; y++) {
    vertLine.set(row(upPal, y), y * 3);
    let c;
    if (y >= 100 && y < 196) c = row(bsPal, y - 100);
    else if (y >= 196) c = [255, 255, 255];
    else c = [0, 0, 0];
    bigLine.set(c, y * 3);
    if (y >= 8 && y < 16) smallLine.set(row(upPal, 16 + ((y - 8) >> 1)), y * 3);
    else if (y >= 32 && y < 40) smallLine.set(row(upPal, 64 + ((y - 32) >> 1)), y * 3);
}
const STATIC = [[0, 0, 0], [64, 96, 32], [160, 96, 160], [0, 224, 224], [0, 0, 0], [0, 0, 0], [0, 0, 0], [255, 255, 255]];

function draw(s) {
    const px = new Uint8Array(W * H); // index plane
    tile(px, bgG, GREEN, s.moveX, s.moveY);
    tile(px, bgP, PINK, s.X, s.Y);
    sprites(px, s);
    // big
    for (let k = 0; k < s.s1.n; k++) {
        const xgo = (s.s1.scroll + k * 24) * 4;
        if (xgo + 96 <= 0) continue;
        if (xgo >= W) break;
        if (s.s1.g[k] !== 0xFF) glyphBig(px, s.s1.g[k], xgo);
    }
    // vertical
    {
        const base = 400 - s.s2.scroll;
        for (let k = 0; k < s.s2.n; k++) {
            const ygo = base + k * 29;
            if (ygo + 29 <= 0) continue;
            if (ygo >= 400) break;
            if (s.s2.g[k] === 0xFF) continue;
            const y0 = Math.floor(ygo / 2);
            for (const xc of [0, 32, 64, 240, 272, 304]) glyphUp(px, s.s2.g[k], xc, y0);
        }
    }
    // the two small scrollers
    for (const [sc, y0] of [[s.s3, 8], [s.s4, 32]])
        for (let k = 0; k < sc.n; k++) {
            const x = sc.scroll + k * 8;
            if (x + 8 <= 0) continue;
            if (x >= W) break;
            if (sc.g[k] !== 0xFF) glyphSmall(px, sc.g[k], x, y0);
        }
    // per-line colour -> RGB (the copper)
    const rgb = new Uint8Array(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const v = px[y * W + x];
            const c = v === BIG ? bigLine : v === VERT ? vertLine : v === SMALL ? smallLine : null;
            const o = (y * W + x) * 3;
            if (c) { rgb[o] = c[y * 3]; rgb[o + 1] = c[y * 3 + 1]; rgb[o + 2] = c[y * 3 + 2]; }
            else { rgb[o] = STATIC[v][0]; rgb[o + 1] = STATIC[v][1]; rgb[o + 2] = STATIC[v][2]; }
        }
    return rgb;
}

// ---------------- run ---------------------------------------------------------
const STEP = [0, 2000, 2340, 2344, 2345, 3000, 3600, 4580, 4584, 4585, 4586, 6000, 7200, 7500, 7504, 7505, 7550, 7600];
const CHECK = new Set(STEP);
const EVERY = 1200; // compare every single frame up to here (20 s at 60 Hz)
const LAST = 7600;

const st = makeState();
const t0 = performance.now();
let compared = 0, distinctMax = 0, blitsMin = Infinity, blitsMax = 0;

// The boot frame: init() composes once before any tick, and that picture is the
// Go's frame 0 at half scale (the spec's 0-update draw). Pin it explicitly --
// the loop below only ever sees tick 1 onward.
{
    machine.hwClear();
    const want = draw(st), got = windowRGB();
    for (let i = 0; i < want.length; i++)
        if (got[i] !== want[i])
            throw new Error(
                `boot frame: pixel (${((i / 3) | 0) % W},${(((i / 3) | 0) / W) | 0}) channel ${i % 3} ` +
                `is ${got[i]} but the model says ${want[i]}`,
            );
    compared++;
    await shot(`${OUT}/frame_boot.ppm`, got);
}
for (let f = 0; f <= LAST; f++) {
    machine.hwClear();
    demo.frame(TICK_MS); // exactly one 60 Hz tick (see below)
    update(st);
    blitsMin = Math.min(blitsMin, demo.gkBlits());
    blitsMax = Math.max(blitsMax, demo.gkBlits());

    // The counter words, every frame: a pixel-perfect picture with a drifting
    // clock would not hide here.
    if (demo.gkTick() !== f + 1) throw new Error(`frame ${f}: gkTick ${demo.gkTick()} != ${f + 1}`);
    for (let i = 0; i < 4; i++) {
        const want = [st.s1.scroll, st.s2.scroll, st.s3.scroll, st.s4.scroll][i];
        if (demo.gkScroll(i) !== want)
            throw new Error(`frame ${f}: scroll ${i} is ${demo.gkScroll(i)} but the model says ${want}`);
    }
    for (let i = 0; i < 8; i++) {
        const want = [st.moveY, st.moveX, st.X, st.Y, st.bgcount, st.ychange10, st.swing, st.swingy][i];
        // >>>0: the two angle words are u32 and cross the wasm boundary as i32.
        if ((demo.gkState(i) >>> 0) !== (want >>> 0))
            throw new Error(`frame ${f}: state ${i} is ${demo.gkState(i)} but the model says ${want}`);
    }

    if (f <= EVERY || CHECK.has(f)) {
        const want = draw(st);
        const got = windowRGB();
        for (let i = 0; i < want.length; i++)
            if (got[i] !== want[i])
                throw new Error(
                    `frame ${f}: pixel (${((i / 3) | 0) % W},${(((i / 3) | 0) / W) | 0}) channel ${i % 3} ` +
                    `is ${got[i]} but the model says ${want[i]}`,
                );
        compared++;
        const seen = new Set();
        for (let i = 0; i < want.length; i += 3) seen.add(want[i] + "," + want[i + 1] + "," + want[i + 2]);
        if (seen.size > distinctMax) distinctMax = seen.size;
        if (f === 0 || f === 1200) await shot(`${OUT}/frame_${f}.ppm`, got);
    }
}
const ms = performance.now() - t0;
// Those pixels came from CHISEL (draw.zig), not the CPU fallback, in few blits:
// 1 fill + <= 12 tile + 12 sprite + <= 5 big + 6 vertical + 2 small.
ok(blitsMin > 0 && blitsMax <= 40, `every frame drawn by CHISEL in ${blitsMin}..${blitsMax} blits (ceiling 40)`);
ok(compared >= 1200, `${compared} frames compared pixel for pixel (the boot frame, every frame to ${EVERY}, plus the resets)`);

// A raster, not a static palette: the window carries more colours than the
// eight palette words can, i.e. entries 4/5/6 really do change per scanline.
ok(distinctMax > 16, `the per-line rasters put ${distinctMax} distinct colours on the window (a static palette gives 8)`);

// The border bands above/below the visible line are black (the tables end).
machine.hwClear(); demo.frame(TICK_MS); machine.hwRenderPlane(0);
{
    const border = borderRGB();
    let flat = true;
    for (let line = 0; line < ph; line++)
        if (line < by || line >= by + H)
            if (border[line * 3] !== 0 || border[line * 3 + 1] !== 0 || border[line * 3 + 2] !== 0) flat = false;
    ok(flat, "the border bands above/below line 200 stay black");
}

// Leave on Escape (the cart declares no key(): demo_main.zig owns it).
demo.key(0xE012);
demo.frame(TICK_MS);
ok(demo.pollCartRequest() === -1, "Escape hands the screen back to the menu (pollCartRequest -1)");

ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
console.log(`  ${(ms / (LAST + 1)).toFixed(3)} ms/frame over ${LAST + 1} frames (update + render + composite + model)`);

const total = errors.length;
console.log(total === 0 ? "grodan_kvack: PASS" : `grodan_kvack: FAILED (${total})`);
process.exit(total ? 1 : 0);
