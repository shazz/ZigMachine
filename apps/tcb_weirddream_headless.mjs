// Headless TCB + REPLICANTS "WEIRD DREAM" driver (CODEF screen 345).
//
//   node apps/tcb_weirddream_headless.mjs [--break table|noclear|keys] [outdir]
//
// Boots the sealed machine + demo-tcb_weirddream the way sealed-loader.js does
// (hwClear, frame, hwRenderPlane(0)) and replays screen.js beside it: a JS
// model of dosplash() and go() — screen.js's own expressions, and its
// precalc_scroll_x run verbatim here, independent of the Zig comptime table —
// paints the expected 320x200 frame, which must equal the cart's window pixel
// for pixel on every compared frame. The model uses the cart's assets (the
// logo zooms are Chrome's precalc, baked), so what it proves is the SCREEN:
// which zoom frame, which parity, which row, which table entry, which glyph
// column, in which order, on which frame.
//
// Also checked: the border (colour 0 on an ST) is $777 grey for the whole
// splash and black from go()'s first frame on, top to bottom and edge to edge,
// with no one-frame lag at the switch; there is no raster (every border line
// equals colour 0); the cart requests rollout.sndh subtune 1 exactly when go()
// starts and not before, F2/F1 switch subtunes only to the OTHER tune, as
// screen.js:356-372 does.
//
// --break table   the model reads the scroll table one entry late
// --break noclear hwClear is skipped: the border is never painted
// --break keys    the model expects F1 to restart tune 1 while it plays
// Each must make the run fail; the harness then passes by catching it.
import { readFile, writeFile, mkdir, access } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const A = "apps/zig/assets/screens/tcb_weirddream/";
const SPLASH = 200;

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
    const noop = () => {};
    const cartBytes = await readFile(cart);
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const args = process.argv.slice(2);
const BREAK = args[0] === "--break" ? args[1] : null;
if (BREAK && !["table", "noclear", "keys"].includes(BREAK)) throw new Error(`unknown --break ${BREAK}`);
const out = (BREAK ? args[2] : args[0]) || "/tmp/tcb_weirddream";
await mkdir(out, { recursive: true });

// ---------------------------------------------------------------- the model
const pal = await readFile(A + "pal.dat");
const splashRaw = await readFile(A + "splash.raw");
const font = await readFile(A + "font.raw");
const sprite = await readFile(A + "sprite.raw");
const logosRaw = await readFile(A + "logos.raw");
const logosIdx = await readFile(A + "logos.idx");
const TEXT = await sceneText();
const GREY = 0xe0e0e0;
const rgb = (i) => (pal[i * 4] << 16) | (pal[i * 4 + 1] << 8) | pal[i * 4 + 2];
const palIndex = (c) => { for (let i = 1; i < 256; i++) if (rgb(i) === c) return i; throw new Error(`no ${c}`); };

// The scrolltext is text.zig's literal; where the CODEF mirror is present it
// is also checked against screen.js:174 itself.
async function sceneText() {
    const src = await readFile("apps/zig/scenes/tcb_weirddream/text.zig", "utf8");
    const parts = [...src.matchAll(/^\s+"((?:[^"\\]|\\.)*)"/gm)].map((m) => JSON.parse(`"${m[1]}"`));
    const text = parts.join("");
    const ref = "/home/matt/projects/ZigMachine/prototypes/codef/345/screen.js";
    try {
        await access(ref);
        const js = /var text="(.*?)";/s.exec(await readFile(ref, "utf8"))[1];
        if (js !== text) throw new Error("text.zig is not screen.js:174's scrolltext");
    } catch (e) { if (e.code !== "ENOENT") throw e; }
    return text;
}

// screen.js:204-247, verbatim (the fourth block rewrites 0..388 with itself).
function precalcScrollX() {
    const scroll_x = []; let scroll_x_mod = 0, stp1, stp2;
    stp1 = 7 / 180 * Math.PI; stp2 = 3 / 180 * Math.PI;
    for (let i = 0; i < 389; i++) scroll_x[i] = (20 * Math.sin(i * stp1)) + (30 * Math.cos(i * stp2));
    scroll_x_mod = scroll_x.length;
    stp1 = 72 / 180 * Math.PI;
    for (let i = 0; i < 120; i++) scroll_x[scroll_x_mod + i] = 4 * Math.sin(i * stp1);
    scroll_x_mod = scroll_x.length;
    stp1 = 8 / 180 * Math.PI;
    for (let i = 0; i < 68; i++) scroll_x[i + scroll_x_mod] = 40 * Math.sin(i * stp1);
    scroll_x_mod = scroll_x.length;
    stp1 = 7 / 180 * Math.PI; stp2 = 3 / 180 * Math.PI;
    for (let i = 0; i < 389; i++) scroll_x[i] = (20 * Math.sin(i * stp1)) + (30 * Math.cos(i * stp2));
    scroll_x_mod = scroll_x.length;
    stp1 = 72 / 180 * Math.PI;
    for (let i = 0; i < 36; i++) scroll_x[scroll_x_mod + i] = 4 * Math.sin(i * stp1);
    scroll_x_mod = scroll_x.length;
    stp1 = 8 / 180 * Math.PI;
    for (let i = 0; i < 189; i++) scroll_x[i + scroll_x_mod] = 30 * Math.sin(i * stp1);
    return scroll_x;
}
const scroll_x = precalcScrollX();
if (scroll_x.length !== 802) throw new Error(`scroll_x is ${scroll_x.length} entries`);
const st = (doubled) => Math.floor(doubled / 2 + 0.5); // nearest ST pixel

// The stars: the cart's fixed xorshift32 seed, starfield2D_dot's motion.
const SPEED = [112, 56, 28], INK = [0xe0a0a0, 0xc06060, 0x804040].map(palIndex);
const stars = [];
{
    let s = 0x03451989;
    const xs = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s; };
    for (let i = 0; i < 105; i++) stars.push({ x10: xs() % 6400, y: xs() % 140, layer: Math.floor(i / 35) });
}
const moveStars = () => { for (const s of stars) { s.x10 += SPEED[s.layer]; if (s.x10 > 6400) s.x10 = 0; } };

function modelSplash(n) {
    const f = new Uint8Array(320 * 200);
    const rows = Math.min(200, Math.max(0, n * 40 - 20));
    f.set(splashRaw.subarray(0, rows * 320));
    return f;
}

function modelMain(m) {
    const f = new Uint8Array(320 * 200);
    // go(): the logos (screen.js:406-430); phases in whole degrees
    const offrep = ((m * 2) % 360) * Math.PI / 180, offtcb = ((m * 7) % 360) * Math.PI / 180;
    let zrep = (1 + Math.sin(offrep)) / 2; if (zrep < 0) zrep = 0;
    let yrep = 140 + (Math.cos(offrep) + Math.sin(offrep)) * 40;
    const ztcb = zrep + (Math.cos(offtcb) / 8);
    let ytcb = yrep + Math.sin(offtcb) * (70 * zrep);
    const zzrep = Math.round(zrep * 35), zztcb = Math.round(4 + (ztcb * 32));
    yrep = Math.round(yrep); ytcb = Math.round(ytcb);
    const rep = () => { if (zzrep > 0) logo(f, 80, zzrep, yrep - 22, 20); };
    const tcb = () => { if (zztcb > 0) logo(f, 0, zztcb, ytcb - 25, 112); };
    if (ztcb >= zrep) { rep(); tcb(); } else { tcb(); rep(); }
    for (const s of stars) { const x = Math.floor((s.x10 + 10) / 20); if (x < 320) f[s.y * 320 + x] = INK[s.layer]; }
    // the scroller: row j from strip x 64 + scroll_x[(vbl+j) % 802], blocks of 16
    const offsetscr = offsetscrAt(m), vbl = m + (BREAK === "table" ? 1 : 0);
    for (let j = 0; j < 25; j++) {
        const row = 4 * (m + 1) - 444 + 32 + st(scroll_x[(vbl + j) % 802]);
        for (let c = 0; c < 40; c++) {
            const y = st(280 + 35 + (Math.cos(offsetscr + (c * 0.1)) * 35)) + j;
            for (let i = 0; i < 8; i++) { const v = glyph(row + c * 8 + i, j); if (v !== null) f[y * 320 + c * 8 + i] = v; }
        }
    }
    keyed(f, sprite, 0, 48, 32, 16, st(326 - Math.abs(Math.cos(offsetscr) * 24)));
    keyed(f, sprite, 0, 48, 32, 256, st(326 - Math.abs(Math.sin(offsetscr) * 24)));
    return f;
}

const offsets = [0];
function offsetscrAt(m) { while (offsets.length <= m) offsets.push(offsets[offsets.length - 1] + 0.1); return offsets[m]; }

function glyph(at, row) {
    if (at < 0) return null;
    const s = at % (TEXT.length * 32), ch = TEXT.charCodeAt(Math.floor(s / 32));
    if (ch < 32 || ch > 91) return null; // drawTile of a tile outside the sheet draws nothing
    const g = ch - 32;
    return font[(Math.floor(g / 10) * 25 + row) * 320 + (g % 10) * 32 + (s % 32)];
}

function logo(f, first, zoom, top, x) {
    const e = (first + (zoom - 1) * 2 + (top & 1)) * 12;
    const dx = logosIdx.readInt16LE(e), dy = logosIdx.readInt16LE(e + 2);
    const w = logosIdx.readUInt16LE(e + 4), h = logosIdx.readUInt16LE(e + 6), off = logosIdx.readUInt32LE(e + 8);
    keyed(f, logosRaw, off, w, h, x + dx, Math.floor(top / 2) + dy);
}

function keyed(f, img, off, w, h, x, y) {
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
        const v = img[off + r * w + c], X = x + c, Y = y + r;
        if (v !== 0xff && X >= 0 && X < 320 && Y >= 0 && Y < 200) f[Y * 320 + X] = v;
    }
}

// ---------------------------------------------------------------- the run
const { memory, machine, demo } = await boot("docs/demo-tcb_weirddream.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(); // 800x280, window at (80,40) x-doubled
const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
const errors = [];
const hex = (c) => "#" + c.toString(16).padStart(6, "0");
let frames = 0;

const songs = [];
function step() {
    if (BREAK !== "noclear") machine.hwClear();
    demo.frame(1000 / 60);
    machine.hwRenderPlane(0);
    frames++;
    if (demo.pollSongRequest()) {
        const name = new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
        songs.push({ frame: frames, name, tune: demo.songTune() });
    }
}

function compare(expect, colour0) {
    const b = pfb();
    let bad = 0, first = null;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const i = ((40 + y) * W + 80 + x * 2) * 4;
        const got = (b[i] << 16) | (b[i + 1] << 8) | b[i + 2];
        const v = expect[y * 320 + x], want = v === 0 ? colour0 : rgb(v);
        if (got !== want) { bad++; first ??= `(${x},${y}) ${hex(got)} want ${hex(want)}`; }
    }
    if (bad) errors.push(`frame ${frames}: ${bad} pixels differ from screen.js, first ${first}`);
    // colour 0 is the border: every line, both sides, top and bottom bands
    for (let y = 0; y < H; y++) for (const x of [0, 78, 722, W - 1]) {
        const i = (y * W + x) * 4, got = (b[i] << 16) | (b[i + 1] << 8) | b[i + 2];
        if (got !== colour0) { errors.push(`frame ${frames}: border (${x},${y}) ${hex(got)} want colour 0 ${hex(colour0)}`); return; }
    }
}

const SHOTS = new Set([3, 200, 201, 330, 700, 1800]);
const MAIN_CHECK = new Set([201, 202, 203, 250, 305, 306, 330, 381, 561, 700, 1000, 1210, 1800, 2400, 3000]);
let compared = 0;
const t0 = performance.now();
for (let f = 1; f <= 3000; f++) {
    step();
    if (f > SPLASH + 1) moveStars();
    if (f <= SPLASH && (f <= 7 || f === SPLASH)) { compare(modelSplash(f), GREY); compared++; }
    if (f > SPLASH && (MAIN_CHECK.has(f) || f % 97 === 0)) { compare(modelMain(f - SPLASH - 1), 0); compared++; }
    if (SHOTS.has(f)) await shot(`${out}/${String(f).padStart(4, "0")}.ppm`);
}
const cost = (performance.now() - t0) / frames;

// Music: go() starts subtune 1 (audio.playNextSong in dosplash), nothing before.
if (songs.length !== 1 || songs[0].frame !== SPLASH + 1 || songs[0].name !== "rollout.sndh" || songs[0].tune !== 1)
    errors.push(`song requests ${JSON.stringify(songs)}, want rollout.sndh tune 1 at frame ${SPLASH + 1} only`);
try { await access("docs/music/rollout.sndh"); } catch { errors.push("docs/music/rollout.sndh is missing"); }
// F1 while tune 1 plays does nothing; F2 -> tune 2; F2 again nothing; F1 -> tune 1.
const keyWant = BREAK === "keys" ? [[0xe001, 1], [0xe002, 2], [0xe002, null], [0xe001, 1]]
    : [[0xe001, null], [0xe002, 2], [0xe002, null], [0xe001, 1]];
for (const [k, want] of keyWant) {
    songs.length = 0;
    demo.key(k);
    step();
    const got = songs.length ? songs[0].tune : null;
    if (got !== want) errors.push(`key ${hex(k)}: requested tune ${got}, want ${want}`);
}

async function shot(path) {
    const hdr = new TextEncoder().encode(`P6\n${W / 2} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + (W / 2) * H * 3);
    buf.set(hdr);
    const b = pfb();
    for (let y = 0; y < H; y++) for (let x = 0; x < W / 2; x++)
        for (let c = 0; c < 3; c++) buf[hdr.length + (y * (W / 2) + x) * 3 + c] = b[(y * W + x * 2) * 4 + c];
    await writeFile(path, buf);
}

const unique = [...new Set(errors)];
// process.exitCode, never process.exit(): the --only gate once saw node wedge
// in a futex inside exit() here, with the harness's WebAssembly state live.
if (BREAK) {
    if (unique.length === 0) { console.log(`tcb_weirddream: FAIL, --break ${BREAK} was NOT caught`); process.exitCode = 1; }
    else console.log(`tcb_weirddream: PASS (--break ${BREAK} caught: ${unique.length} errors, first: ${unique[0]})`);
} else if (unique.length) {
    console.log("tcb_weirddream: WRONG");
    for (const e of unique.slice(0, 12)) console.log("  " + e);
    process.exitCode = 1;
} else console.log(`tcb_weirddream: ${compared} frames equal screen.js's model pixel for pixel (splash reveal, logo zooms, stars, the 802-entry table, the cosine band, the sprites); border = colour 0 on every line, grey through the splash and black from go()'s first frame; rollout.sndh tune 1 requested at frame ${SPLASH + 1}, F1/F2 switch as screen.js does; ${cost.toFixed(3)} ms/frame (clear + cart + plane, model included); shots in ${out}`);
