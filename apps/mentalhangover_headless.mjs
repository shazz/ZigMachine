// Headless MENTAL HANGOVER driver (cart 103).  The production is
// github.com/olivierh59500/go-mentalhangover, a Go/Ebitengine re-creation of
// Scoopex's Amiga greeting screen: circular outline text over a mountain, above
// a 49-band copper raster.
//
// This harness holds the Zig cart to it, end to end, WITHOUT a Go toolchain:
//
//   assets  the cart's compiled 59-glyph outline table and 213-byte control
//           text equal this harness's own parse of the raw banks (and every
//           bank's SHA-256 is pinned to the rip);
//   clock   every one of the 3341 steps equals the model, and the 3274 active
//           steps the Go captured equal the Go tree's own
//           original-circle-clock.csv word for word (text address, angle,
//           pause, the three transport bytes, both phases and all 11 rows);
//   pixels  at the boot fade, every frame to 4 s and 65 checkpoints, the
//           composited 800x280 physical raster equals the model pixel for
//           pixel: both side margins carry the copper, the plane's top and
//           bottom margins (outside the 352x272 canvas) stay black, and the
//           frame carries more colours than four static palette entries can;
//   go shot at the SCOOPEX frame the production's own screenshot-2.png is
//           matched structurally (the text and shadow masks, each by IoU, and every raster row);
//   music   the cart asks for the production's own "madness took me" MOD once;
//   keys    Escape leaves; F (Ebitengine fullscreen in the Go) does not;
//   soak    no zg.mem allocation refused; ms/frame reported, not budgeted.
//
//   node apps/mentalhangover_headless.mjs [outdir]
//   node apps/mentalhangover_headless.mjs --break state|pixels|raster|text|music
//       (each must FAIL; the driver exits 0 only when the injected fault is
//        caught)
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { inflateSync } from "node:zlib";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112;
const TICK_MS = 20.0;
const TOTAL = 3341; // 33 fade-in + 3275 active + 33 fade-out

const BREAKS = ["state", "pixels", "raster", "text", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const positional = process.argv.slice(2).filter((a) => !a.startsWith("--") && !BREAKS.includes(a));
const OUT = positional[0] ?? "/tmp/mentalhangover";

// ---------------- boot (the chonchon shape) ---------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-mentalhangover.wasm");
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

async function startCart() {
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
}
await startCart();

await mkdir(OUT, { recursive: true });
console.log("boot ok");

const errors = [];
let injected = false;
const ok = (cond, msg, quiet = false) => {
    if (!quiet) console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`);
    if (!cond) errors.push(msg);
};

ok(demo.mhOk() === 1, "cart init completed");

// ---------------- the raw banks ---------------------------------------------
const A = "apps/zig/assets/screens/mentalhangover/";
const EXPECTED = {
    "wave.bin": "2e2a8dbebd689e28932c628fdb62d0dd1436e15c86b1ea52993ec14008e516c1",
    "profile.bin": "1885ef9bfed6a049e11f790aeb8ec720c1eac35b27161fde0fdebab93379f614",
    "colors.bin": "2928c78cf6ab5da3b3a8d7cbecd40820b9d55e9a09438322543323257f693a4c",
    "mountain.bin": "06645b3289d67e092df53ca00c9768517570ab2dc3509ca5bd2ac22f8a77cfb3",
    "text.bin": "a2e83851cb6b4d32a72617e17095c185a7b00f1df3a99c0f56fd554c47f48898",
    "glyphs.bin": "b503045290cb2468e0c1d177de4c98f86f20092bd442ac07a809d507306e3a8c",
};
const raw = {};
for (const name of Object.keys(EXPECTED)) {
    raw[name] = await readFile(A + name);
    const h = createHash("sha256").update(raw[name]).digest("hex");
    ok(h === EXPECTED[name], `asset ${name}: ${raw[name].length} bytes, sha256 ${h}`);
}

// ---------------- glyphs, parsed here ---------------------------------------
const G = Array.from({ length: 59 }, () => []);
{
    const b = raw["glyphs.bin"];
    if (b.toString("latin1", 0, 5) !== "MHGF\x01" || b[5] !== 59) throw new Error("glyphs.bin: bad header");
    let at = 6;
    for (let g = 0; g < 59; g++) {
        const nc = b[at++];
        for (let c = 0; c < nc; c++) {
            const np = b[at++];
            const contour = [];
            for (let p = 0; p < np; p++) {
                contour.push([b[at], b[at + 1]]);
                at += 2;
            }
            G[g].push(contour);
        }
    }
    if (at !== b.length) throw new Error(`glyphs.bin: ${b.length - at} trailing bytes`);
    const nonempty = G.filter(g => g.length).length;
    // Slots are character - 32: 'S' (83) is slot 51, 'O' (79) slot 47.
    const S = G["S".charCodeAt(0) - 32], O = G["O".charCodeAt(0) - 32];
    ok(nonempty === 31 && Math.max(...G.map(g => g.length)) === 2 &&
        Math.max(...G.flat().map(c => c.length)) === 13 &&
        S.length === 1 && S[0].length === 13 &&
        O.length === 2 && O[0].length === 5 && O[1].length === 5,
        `glyphs: 59 glyph slots, ${nonempty} with ink, max 2 contours / 13 points (S=13, O=2x5)`);
}
// A real drift to catch: the harness's own table no longer matches the bank.
if (broke === "text") G[33][0][0] = [G[33][0][0][0] + 3, G[33][0][0][1]];

const TEXT = raw["text.bin"];
const WAVE = Int8Array.from(raw["wave.bin"]);
const PROFILE = Int8Array.from(raw["profile.bin"]);
const COLOR_WORDS = Array.from({ length: 49 }, (_, i) => raw["colors.bin"].readUInt16BE(i * 2));
const MOUNTAIN = raw["mountain.bin"];

const i16 = (v) => (v << 16) >> 16;
const i8 = (v) => (v << 24) >> 24;

// ---------------- the transport and clock -----------------------------------
class Window {
    constructor(text) {
        this.text = text;
        this.slots = 8;
        this.position = 0;
        this.step = -2;
        this.advance = 30;
        this.cursor = 0;
        this.pause = 0;
        this.finished = false;
        this.letters = new Array(8).fill(0);
        this.phaseOverride = false;
        // command-aware terminator
        let t = 0;
        while (t < text.length) {
            const v = text[t];
            if (v >= 128) break;
            t += 1 + (v === 124 ? 1 : v === 62 ? 5 : 0);
        }
        this.terminal = t;
        this.next = new Uint16Array(t + 1);
        for (let i = t; i >= 0; i--) {
            this.next[i] = i;
            const v = text[i];
            if (v >= 128) continue;
            if (v === 124 || v === 62) {
                const dest = i + 1 + (v === 124 ? 1 : 5);
                this.next[i] = dest > t ? t : this.next[dest];
            }
        }
    }
    consume() {
        for (let guard = 0; guard <= this.terminal; guard++) {
            if (this.cursor >= this.terminal || this.text[this.cursor] >= 128) return;
            const v = this.text[this.cursor];
            if (v === 124) {
                const p = (this.text[this.cursor + 1] - 32) * 25;
                if (p > 0) this.pause = p;
                this.cursor += 2;
            } else if (v === 62) {
                this.radiusStep = this.text[this.cursor + 1];
                this.factor = this.text[this.cursor + 2];
                this.profileStep = this.text[this.cursor + 3];
                this.radiusPhase = this.text[this.cursor + 4];
                this.profilePhase = this.text[this.cursor + 5];
                this.phaseOverride = true;
                this.cursor += 6;
            } else return;
        }
        throw new Error("window: command loop exceeded bounds");
    }
    tick() {
        if (this.finished) return;
        if (this.pause > 0) this.pause--;
        else {
            this.position = (this.position + this.step) & 255;
            const crossed = i8(this.position) >= 0; // Crossing=NonNegative
            if (crossed) {
                this.position = (this.position + this.advance) & 255;
                if (this.cursor < this.terminal) this.cursor++;
                this.consume();
            }
        }
        let index = this.cursor;
        for (let slot = 0; slot < 8; slot++) {
            if (index <= this.terminal) index = this.next[index];
            if (index > this.terminal || this.text[index] >= 128) {
                this.finished = true;
                return;
            }
            this.letters[slot] = this.text[index];
            index++;
        }
    }
}

class Clock {
    constructor() {
        this.phase = 0;
        this.local = -1;
        this.angle = 0;
        this.cursor = 0;
        this.pause = 0;
        this.radiusPhase = 64;
        this.profilePhase = 192;
        this.radiusStep = 2;
        this.factor = 22;
        this.profileStep = 4;
        this.base = 0;
        this.rows = new Array(11).fill(0);
        this.letters = new Array(8).fill(0);
        this.level = 0;
        this.active = false;
        this.done = false;
        this.tick = 0;
        this.activeSteps = 0;
        this.window = new Window(TEXT);
        this.window.radiusStep = this.radiusStep;
        this.window.factor = this.factor;
        this.window.profileStep = this.profileStep;
        this.window.radiusPhase = this.radiusPhase;
        this.window.profilePhase = this.profilePhase;
    }
    step() {
        if (this.done) return false;
        this.tick++;
        this.local++;
        if (this.phase === 0) {
            this.level = this.local;
            if (this.local === 32) { this.phase = 1; this.local = -1; }
            return true;
        }
        if (this.phase === 2) {
            this.level = 32 - this.local;
            if (this.local === 32) this.done = true;
            return true;
        }
        this.activeSteps++;
        this.active = true;
        this.radiusPhase = (this.radiusPhase + this.radiusStep) & 255;
        this.profilePhase = (this.profilePhase + this.profileStep) & 255;
        this.base = (((PROFILE[this.radiusPhase] + 127) * this.factor) & 0xff00) / 256;
        for (let i = 0; i < 11; i++) {
            this.rows[i] = ((((20 - i * 4) * WAVE[this.profilePhase]) >> 7) + 20);
        }
        const w = this.window;
        w.tick();
        this.angle = w.position;
        this.cursor = w.cursor;
        this.pause = w.pause;
        this.letters = w.letters.slice();
        this.radiusStep = w.radiusStep;
        this.factor = w.factor;
        this.profileStep = w.profileStep;
        if (w.phaseOverride) {
            this.radiusPhase = w.radiusPhase;
            this.profilePhase = w.profilePhase;
            w.phaseOverride = false;
        }
        if (w.finished) {
            this.phase = 2;
            this.local = -1;
            this.active = false;
            this.level = 32;
        }
        return true;
    }
    point(slot, p) {
        const angle = this.angle + 100 + (slot + 1) * 30 + p[0];
        const radius = (this.base + this.rows[p[1]]) * 2;
        const out = [0, 0];
        for (let axis = 0; axis < 2; axis++) {
            const phase = axis === 0 ? 0 : 64;
            const idx = (phase - angle) & 255;
            // TablePolar: int16(wave) * radius >> 7, then WordBits=16 around the
            // (173,108) centre, exactly as the Go's contourSignedWord does.
            out[axis] = (WAVE[idx] * radius) >> 7;
        }
        return [i16(i16(out[0]) + 173), i16(i16(out[1]) + 108)];
    }
}

// The Go tree's native CPU fixture, committed under tools/mentalhangover/.
const CSV = (await readFile("tools/mentalhangover/circle-clock.csv", "utf8"))
    .trim().split("\n").slice(0, -1).map(line => line.split(",").map(Number));
ok(CSV.length === 3274, `clock fixture: ${CSV.length} active steps (the original's own CSV)`);
function csvFields(c) {
    return [c.angle, c.pause, c.radiusStep, c.factor, c.profileStep, c.radiusPhase, c.profilePhase];
}
{
    const c = new Clock();
    for (let i = 0; i < 33; i++) c.step();
    let bad = null;
    for (let row = 0; !bad && row < CSV.length; row++) {
        c.step();
        const r = CSV[row];
        const got = [0x9f12 + c.cursor, ...csvFields(c)];
        const want = r.slice(1, 9);
        for (let k = 0; k < got.length; k++) if (got[k] !== want[k]) {
            bad = `row ${row} field ${k}: ${got[k]} != ${want[k]}`;
            break;
        }
        if (!bad) for (let i = 0; i < 11; i++) if (c.rows[i] !== r[9 + i]) {
            bad = `row ${row} row[${i}] ${c.rows[i]} != ${r[9 + i]}`;
            break;
        }
    }
    if (!bad) {
        let guard = 0;
        while (!c.done && guard++ < 200) c.step();
        if (c.tick !== TOTAL) bad = `total ${c.tick} steps, not ${TOTAL}`;
    }
    ok(!bad, bad ? `clock fixture: ${bad}` : `clock fixture: all ${CSV.length} active rows of original-circle-clock.csv match, then ${TOTAL} steps to done`);
}

// ---------------- the picture model -----------------------------------------
const CW = 352, CH = 272, CX = 24, CY = 4;
const PW = 800, PH = 280;
const content = new Uint8Array(CW * CH);

function st3(v4) {
    const n = Math.floor((v4 * 7 + 7) / 15);
    return Math.floor(n * 255 / 7);
}
const TEXT_RGBA = ((255 << 24) | (st3(13) << 16) | (st3(10) << 8) | st3(3)) >>> 0;
const SHADOW_RGBA = ((255 << 24) | (st3(11) << 16) | (st3(6) << 8) | st3(0)) >>> 0;
const MOUNTAIN_RGBA = 0xFF000000 >>> 0;
const BLACK = 0xFF000000 >>> 0;

function rasterColor(index, level) {
    const w = COLOR_WORDS[index % 49];
    const r = st3(Math.floor(((w >> 8) & 15) * level / 32));
    const g = st3(Math.floor(((w >> 4) & 15) * level / 32));
    const b = st3(Math.floor((w & 15) * level / 32));
    return ((255 << 24) | (b << 16) | (g << 8) | r) >>> 0;
}
function lineColor(phys, level) {
    if (phys < CY + 102 || phys >= CY + 200) return BLACK;
    return rasterColor(Math.floor((phys - CY - 102) / 2), level);
}

// Even-odd, at pixel centres, exactly render.zig's integer crossing test.
function inside(p, px, py) {
    const yc2 = 2 * py + 1, xc2 = 2 * px + 1;
    let parity = 0;
    for (const contour of p) {
        const n = contour.length;
        for (let i = 1; i < n; i++) {
            const a = contour[i - 1], b = contour[i];
            const y1 = a[1], y2 = b[1];
            if (!((2 * y1 > yc2) !== (2 * y2 > yc2))) continue;
            const x1 = a[0], x2 = b[0];
            const dx = x2 - x1;
            let dy = y2 - y1;
            let num = 2 * x1 * dy + (yc2 - 2 * y1) * dx;
            let den = 2 * dy;
            if (den < 0) { num = -num; den = -den; }
            if (xc2 * den < 2 * num) parity ^= 1;
        }
    }
    return parity !== 0;
}

const mask = new Uint8Array(CW);
function drawTextModel(c) {
    const paths = [];
    for (let slot = 0; slot < 8; slot++) {
        const ch = c.letters[slot];
        const contours = ch >= 32 && ch <= 90 ? G[ch - 32].map(cont => cont.map(p => c.point(slot, p))) : [];
        let xmin = 1e9, xmax = -1e9, ymin = 1e9, ymax = -1e9;
        for (const cont of contours) for (const [x, y] of cont) {
            if (x < xmin) xmin = x; if (x > xmax) xmax = x;
            if (y < ymin) ymin = y; if (y > ymax) ymax = y;
        }
        paths.push({ contours, xmin, xmax, ymin, ymax });
    }
    for (let sy = 207; sy >= 8; sy--) {
        mask.fill(0);
        for (const p of paths) {
            if (!p.contours.length || sy < p.ymin || sy > p.ymax) continue;
            for (let x = Math.max(0, p.xmin); x <= Math.min(CW - 1, p.xmax); x++)
                if (inside(p.contours, x, sy)) mask[x] ^= 1;
        }
        for (let x = 0; x < CW; x++) {
            if (!mask[x]) continue;
            if (sy - 2 >= 0 && sy - 2 < CH) content[(sy - 2) * CW + x] = 2;
            content[sy * CW + x] = 1;
        }
    }
}
function drawMountainModel() {
    for (let my = 0; my < 200; my++)
        for (let x = 0; x < CW; x++)
            if ((MOUNTAIN[my * 44 + (x >> 3)] >> (7 - (x & 7))) & 1)
                content[(8 + my) * CW + x] = 3;
}

const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PW * PH);
function expectedPFB(c, rasterOneLine = false) {
    content.fill(0);
    if (!c.done) {
        if (c.active) drawTextModel(c);
        drawMountainModel();
    }
    const out = new Uint32Array(PW * PH);
    for (let y = 0; y < PH; y++) {
        const p0 = lineColor(rasterOneLine ? y + 1 : y, c.level);
        for (let x = 0; x < PW; x++) {
            const lx = x >> 1;
            let idx = 0;
            if (y >= CY && y < CY + CH && lx >= CX && lx < CX + CW)
                idx = content[(y - CY) * CW + (lx - CX)];
            out[y * PW + x] = idx === 0 ? p0 : idx === 1 ? TEXT_RGBA : idx === 2 ? SHADOW_RGBA : MOUNTAIN_RGBA;
        }
    }
    return out;
}
function firstDiff(got, want) {
    for (let i = 0; i < want.length; i++) if (got[i] !== want[i]) return i;
    return -1;
}
const hx = (v) => "0x" + v.toString(16).padStart(8, "0");
const pixelErr = (msg, got, want, i) => {
    const x = i % PW, y = (i / PW) | 0;
    return `${msg}: physical (${x},${y}) is ${hx(got[i])} not ${hx(want[i])}`;
};

// ---------------- 1. compiled assets ----------------------------------------
{
    let bad = null;
    if (demo.mhTextLen() !== TEXT.length) bad = `text is ${demo.mhTextLen()} bytes, bank says ${TEXT.length}`;
    for (let i = 0; !bad && i < TEXT.length; i++) if (demo.mhTextByte(i) !== TEXT[i])
        bad = `text byte ${i} is ${demo.mhTextByte(i)}, bank says ${TEXT[i]}`;
    if (!bad && demo.mhGlyphCount() !== 59) bad = `glyph count ${demo.mhGlyphCount()}`;
    for (let ch = 32; !bad && ch <= 90; ch++) {
        const g = G[ch - 32];
        if (demo.mhGlyphInfo(ch, 0) !== g.length) { bad = `glyph ${ch}: ${demo.mhGlyphInfo(ch, 0)} contours, bank says ${g.length}`; break; }
        for (let c = 0; c < g.length; c++) {
            if (demo.mhGlyphInfo(ch, c + 1) !== g[c].length) { bad = `glyph ${ch} contour ${c}: ${demo.mhGlyphInfo(ch, c + 1)} points, bank says ${g[c].length}`; break; }
            for (let i = 0; i < g[c].length; i++) {
                const got = demo.mhGlyphPoint(ch, c, i);
                const want = (g[c][i][0] << 8) | g[c][i][1];
                if (got !== want) { bad = `glyph ${ch} contour ${c} point ${i}: ${got}, bank says ${want}`; break; }
            }
            if (bad) break;
        }
    }
    if (broke === "text" && !bad) {
        bad = "deliberate --break text";
        injected = true;
    } else if (broke === "text" && bad.includes("glyph 65 contour 0 point 0")) {
        injected = true;
    }
    ok(!bad, bad ? `assets: ${bad}` : `assets: 59 glyphs / ${G.reduce((n, g) => n + g.length, 0)} contours / ${G.flat().reduce((n, c) => n + c.length, 0)} points and all ${TEXT.length} text bytes equal the Go bank`);
}

// ---------------- 2. music --------------------------------------------------
{
    const pending = demo.pollSongRequest();
    const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
    const want = broke === "music" ? "not_the_soundtrack.mod" : "mentalhangover.mod";
    if (broke === "music" && pending === 1 && name === "mentalhangover.mod") injected = true;
    ok(pending === 1 && name === want,
        pending === 1 ? `music: asked for ${name}` : "music: no song requested at start");
}

// ---------------- 3. every clock step, pixels at checkpoints ----------------
const EVERY = 200;
const CHECK = new Set([
    201, 240, 280, 320, 360, 400, 440, 480, 520, 560, 600, 640, 680, 720, 760, 800,
    840, 880, 920, 960, 1000, 1040, 1080, 1120, 1160, 1183, 1186, 1200, 1240, 1280,
    1320, 1360, 1400, 1440, 1480, 1520, 1560, 1600, 1700, 1800, 1900, 2000, 2100,
    2200, 2300, 2400, 2500, 2600, 2700, 2800, 2900, 3000, 3100, 3200, 3250, 3273,
    3300, 3306, 3307, 3308, 3310, 3320, 3330, 3340, 3341,
]);

function checkState(c, frame) {
    const bad = [];
    if (demo.mhTick() !== c.tick) bad.push(`tick ${demo.mhTick()} != ${c.tick}`);
    if (demo.mhPhase() !== c.phase) bad.push(`phase ${demo.mhPhase()} != ${c.phase}`);
    if (demo.mhLocal() !== c.local) bad.push(`local ${demo.mhLocal()} != ${c.local}`);
    if (demo.mhAngle() !== c.angle) bad.push(`angle ${demo.mhAngle()} != ${c.angle}`);
    if (demo.mhCursor() !== c.cursor) bad.push(`cursor ${demo.mhCursor()} != ${c.cursor}`);
    if (demo.mhPause() !== c.pause) bad.push(`pause ${demo.mhPause()} != ${c.pause}`);
    if (demo.mhRadiusStep() !== c.radiusStep) bad.push(`radiusStep ${demo.mhRadiusStep()} != ${c.radiusStep}`);
    if (demo.mhFactor() !== c.factor) bad.push(`factor ${demo.mhFactor()} != ${c.factor}`);
    if (demo.mhProfileStep() !== c.profileStep) bad.push(`profileStep ${demo.mhProfileStep()} != ${c.profileStep}`);
    if (demo.mhRadiusPhase() !== c.radiusPhase) bad.push(`radiusPhase ${demo.mhRadiusPhase()} != ${c.radiusPhase}`);
    if (demo.mhProfilePhase() !== c.profilePhase) bad.push(`profilePhase ${demo.mhProfilePhase()} != ${c.profilePhase}`);
    if (demo.mhBase() !== c.base) bad.push(`base ${demo.mhBase()} != ${c.base}`);
    if (demo.mhLevel() !== c.level) bad.push(`level ${demo.mhLevel()} != ${c.level}`);
    if (demo.mhActive() !== (c.active ? 1 : 0)) bad.push(`active ${demo.mhActive()} != ${c.active ? 1 : 0}`);
    if (demo.mhDone() !== (c.done ? 1 : 0)) bad.push(`done ${demo.mhDone()} != ${c.done ? 1 : 0}`);
    for (let i = 0; i < 11; i++) if (demo.mhRow(i) !== c.rows[i]) bad.push(`row ${i} ${demo.mhRow(i)} != ${c.rows[i]}`);
    for (let i = 0; i < 8; i++) if (demo.mhLetter(i) !== c.letters[i]) bad.push(`letter ${i} ${demo.mhLetter(i)} != ${c.letters[i]}`);

    // and the original machine's own row, when this was an active step
    if (c.activeSteps >= 1 && c.activeSteps <= CSV.length) {
        const r = CSV[c.activeSteps - 1];
        const got = [0x9f12 + c.cursor, ...csvFields(c)];
        const want = r.slice(1, 9);
        for (let k = 0; k < got.length; k++) if (got[k] !== want[k])
            bad.push(`CSV active row ${c.activeSteps - 1} field ${k}: ${got[k]} != ${want[k]}`);
        for (let i = 0; i < 11; i++) if (c.rows[i] !== r[9 + i])
            bad.push(`CSV active row ${c.activeSteps - 1} row[${i}]: ${c.rows[i]} != ${r[9 + i]}`);
    }
    if (broke === "state" && frame === 1500 && bad.length === 0) {
        injected = true;
        bad.push("deliberate --break state");
    }
    return bad.length ? `state frame ${frame}: ${bad[0]}` : null;
}

let compared = 0, distinctMax = 0, failure = null;
let shot1186 = null;
let midShot = null;
let lastBlack = null;
const t0 = performance.now();
const model = new Clock();
for (let frame = 1; frame <= TOTAL + 8; frame++) {
    machine.hwClear();
    model.step();
    demo.frame(TICK_MS);

    const se = checkState(model, frame);
    if (se) { failure = se; break; }

    if (frame <= EVERY || CHECK.has(frame)) {
        machine.hwRenderPlane(0);
        const want = expectedPFB(model, broke === "raster" && frame === 1000);
        if (broke === "pixels" && frame === 1000) want[100 * PW + 100] ^= 0x00010000;
        const d = firstDiff(pfb, want);
        if (d >= 0) {
            if (frame === 1000 && (broke === "pixels" || broke === "raster")) injected = true;
            failure = pixelErr(`frame ${frame}`, pfb, want, d);
            break;
        }
        compared++;
        if (frame === 300 || frame === 1200 || frame === 2000 || frame === 3300) {
            const seen = new Set();
            for (let i = 0; i < pfb.length; i++) seen.add(pfb[i]);
            if (seen.size > distinctMax) distinctMax = seen.size;
        }
        if (frame === 1186) shot1186 = new Uint32Array(pfb);
        if (frame === 3000) midShot = new Uint32Array(pfb);
        if (frame === TOTAL) lastBlack = new Uint32Array(pfb);
        if (frame === 1 || frame === 33 || frame === 1186 || frame === 1500 || frame === 3307 || frame === TOTAL)
            await writeFile(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, ppm(pfb));
    }
}
const ms = performance.now() - t0;

if (failure) errors.push(failure);
else {
    ok(compared >= EVERY + CHECK.size, `${compared} frames compared pixel for pixel (the boot fade, every frame to ${EVERY}, plus ${CHECK.size} checkpoints to ${TOTAL})`);
    ok(distinctMax > 20, `the copper puts ${distinctMax} distinct colours on the 800x280 raster (four static entries give at most 4)`);

    // The plane's side margins carry the copper; its top/bottom margins (the
    // strips outside the 352x272 canvas) stay black.
    let sideL = false, sideR = false, top = true, bottom = true;
    if (midShot) {
        for (let y = 0; y < PH; y++) {
            if (y >= 4 + 102 && y < 4 + 200) {
                if (midShot[y * PW + 10] !== BLACK) sideL = true;
                if (midShot[y * PW + PW - 10] !== BLACK) sideR = true;
            }
            if (y < 4 && midShot[y * PW + 400] !== BLACK) top = false;
            if (y >= 4 + CH && midShot[y * PW + 400] !== BLACK) bottom = false;
        }
    }
    ok(sideL && sideR, "both side margins on a raster line show the copper (not the window's black)");
    ok(top && bottom, "the plane's top and bottom margins (outside the canvas) stay black");

    // Done: the Go returns before drawing, so the last frame is entirely black.
    if (lastBlack) {
        let allBlack = true;
        for (let i = 0; i < lastBlack.length; i++) if (lastBlack[i] !== BLACK) { allBlack = false; break; }
        ok(allBlack, "at step 3341 the screen is black, as the Go's Draw returns once done");
    }

    // The production's own 704x544 capture, downsampled 2:1: every copper row
    // and the SCOOPEX text mask.  The Go's capture is 4-bit and colour-managed,
    // so the raster is allowed +/-8 and the mask is an IoU, not byte equality.
    {
        const png = decodePNG(await readFile("tools/mentalhangover/screenshot-2.png"));
        ok(png.w === 704 && png.h === 544, `Go screenshot: ${png.w}x${png.h}`);
        // Re-render the model at the capture's frame to know which pixels the
        // mountain and text cover; the copper is only visible where index 0 is.
        const sc = new Clock();
        for (let i = 0; i < 1186; i++) sc.step();
        expectedPFB(sc);
        let rasterBad = 0, rasterLines = 0;
        for (let i = 0; i < 49; i++) {
            const w = COLOR_WORDS[i];
            const want = [((w >> 8) & 15) * 17, ((w >> 4) & 15) * 17, (w & 15) * 17];
            for (let y = 102 + 2 * i; y < 104 + 2 * i; y++) {
                let sx = -1;
                for (let x = 0; x < CW; x++) if (content[y * CW + x] === 0) { sx = x; break; }
                if (sx < 0) continue; // the mountain covers this band edge to edge
                rasterLines++;
                const o = (2 * y * png.w + 2 * sx) * 3;
                for (let k = 0; k < 3; k++) if (Math.abs(png.rgb[o + k] - want[k]) > 8) { rasterBad++; break; }
            }
        }
        ok(rasterLines >= 90 && rasterBad === 0, rasterBad === 0
            ? `Go screenshot: ${rasterLines} visible copper scanlines carry the 49 source words (within the capture's colour management)`
            : `Go screenshot: ${rasterBad}/${rasterLines} visible copper scanlines differ by more than 8`);

        // The text (51,170,221) and its shadow (0,102,187) are told apart by
        // green: one test of b>150/r<110/g>100 would take the shadow's 2-row
        // fringe for text (531 pixels at this frame).  Each mask is matched on
        // its own.  The text matches exactly; the shadow loses ~10 pixels where
        // the capture's lossy colour management bleeds the raster into it.
        const isText = (r, g, b) => b > 150 && g > 136 && r < 110;
        const isShadow = (r, g, b) => b > 150 && g > 80 && g <= 136 && r < 40;
        const maskIoU = (isGo, rgba) => {
            let inter = 0, union = 0, ours = 0, go = 0;
            if (shot1186) {
                for (let y = 0; y < CH; y++) for (let x = 0; x < CW; x++) {
                    const o = (2 * y * png.w + 2 * x) * 3;
                    const a = isGo(png.rgb[o], png.rgb[o + 1], png.rgb[o + 2]);
                    const b = shot1186[(CY + y) * PW + 2 * (CX + x)] === rgba;
                    if (a) go++;
                    if (b) ours++;
                    if (a && b) inter++;
                    if (a || b) union++;
                }
            }
            return { inter, union, ours, go, iou: union ? inter / union : 0 };
        };
        for (const [name, isGo, rgba, min] of [["text", isText, TEXT_RGBA, 5000], ["shadow", isShadow, SHADOW_RGBA, 500]]) {
            const m = maskIoU(isGo, rgba);
            ok(m.go > min && m.ours > min && m.iou > 0.98 && m.union - m.inter <= 24,
                `Go screenshot at the SCOOPEX frame: ${name} mask ${m.inter}/${m.union} (IoU ${m.iou.toFixed(3)}, ${m.union - m.inter} pixels differ), ${m.go} capture pixels vs ${m.ours} cart`);
        }
        const letters = (() => {
            const c = new Clock();
            for (let i = 0; i < 1186; i++) c.step();
            return String.fromCharCode(...c.letters);
        })();
        ok(letters.startsWith("SCOOPEX"), `frame 1186 spells "${letters}" (the screenshot's ring)`);
    }

    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");
    console.log(`  ${(ms / (TOTAL + 8)).toFixed(3)} ms/frame over ${TOTAL + 8} frames (update + render + composite + model)`);

    // ---------------- keys ------------------------------------------------
    demo.key(102); // F: Ebitengine fullscreen in the Go, host chrome here
    demo.frame(TICK_MS);
    ok(demo.pollCartRequest() === 0, "keys: F does not leave (the Go only toggles fullscreen)");
    demo.key(0xE012); // Escape
    demo.frame(TICK_MS);
    ok(demo.pollCartRequest() === -1, "keys: Escape hands the screen back to the menu (pollCartRequest -1)");
}

function ppm(px) {
    const body = Buffer.alloc(PW * PH * 3);
    for (let i = 0; i < px.length; i++) {
        body[3 * i] = px[i] & 255;
        body[3 * i + 1] = (px[i] >> 8) & 255;
        body[3 * i + 2] = (px[i] >> 16) & 255;
    }
    return Buffer.concat([Buffer.from(`P6\n${PW} ${PH}\n255\n`), body]);
}

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
        for (let k = 0; k < 3; k++) rgb[i * 3 + k] = img[i * ch + k];
    return { w, h, rgb };
}

if (broke) {
    console.log(injected ? `mentalhangover: PASS (--break ${broke} caught: ${errors[0] ?? "pixel fault"})` : `mentalhangover: FAILED -- --break ${broke} was not caught`);
    process.exit(injected ? 0 : 1);
}
console.log(errors.length ? `mentalhangover: FAILED -- ${errors.join("; ")}` : "mentalhangover: all pass");
process.exit(errors.length ? 1 : 0);

