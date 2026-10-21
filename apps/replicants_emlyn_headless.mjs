// Headless REPLICANTS / Emlyn Hughes driver — boots the sealed machine +
// demo-replicants_emlyn.wasm the way docs/sealed-loader.js does and proves the
// thing this screen is about: the bars are REAL RASTERS, edge to edge.
//
// It reads the plane's INDEX framebuffer, not just the composited pixels, so
// the claims are direct: no pixel anywhere carries one of bar.png's 16 colours
// (entries 2..17 are dead), the background is nothing but bucket indices, and
// the colours come from the per-scanline palette the plane's HBL installs.
//
// Geometry: an overscan plane, 400x280, content window at (40,20). The physical
// framebuffer is 800x280 with x DOUBLED, so plane pixel (X, Y) is at (2X, Y).
//
//   node apps/replicants_emlyn_headless.mjs [outdir] [--break <what>] [--cart <wasm>]
//
// --cart runs the same proof on another build of the screen: the gate runs it
// on demo-replicants_emlyn.wasm (fixed point, the default) and on
// demo-replicants_emlyn_f32.wasm (the CODEF algorithm in f32, kept for the FPU
// test). Both must show the same screen.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeZigChecks } from "./replicants_emlyn_zig.mjs";

const PAGES = 112, AUDIO_PAGES = 48; // SHARED_PAGES / AUDIO_PAGES in machine/sdk
const OFF_PAL = 0x0100, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44; // memmap.zig
const FIRST_BUCKET = 107, MAX_BUCKETS = 149; // emlyn/assets.zig, emlyn/rasters.zig
const FIRST_BAR = 2, FIRST_FONT = 18, FIRST_LOGO = 48; // the asset script's palette
const CONTENT_X = 40, CONTENT_Y = 20, CONTENT_W = 320, CONTENT_H = 240;
const SCROLL_TOP = 195, SCROLL_BOTTOM = 226; // drawTile(390) halved, 32 rows tall
const MAGIC_X = 40, HBL_PLANE_ID = 0; // OVERSCAN_MAGIC_X; id 5 would be the global HBL
const K_ESC = 0xe012, DIR_FIRE = 5;
const WANT_MUSIC = "seven_gates_of_jambala.sndh", WANT_TUNE = 9;
const SPIN_FRAMES = 40; // theta = 0.02 * 40 = 0.80 rad; the bend is full by 20
const RETURN_FRAMES = 21; // 0.80 rad home at 0.16 a frame: 5, and 20 from the far side
// SHA-256 prefixes of ORIGINAL's frame 1 and 120 shots, recorded from the build
// before ZIG mode opened the top and bottom borders (a9a032eb); the f32 cart
// draws the same two frames
const ORIGINAL_SHA = "e4f109ade24cde34 d81bc2133c86cde2";
// ... and of ZIG + 40's content window (rows 20..259), which opening the top
// and bottom borders must not change either: the fixed and f32 carts differ
const ZIG_WINDOW_SHA = { "docs/demo-replicants_emlyn.wasm": "4ccc3af1126cdfa6", "docs/demo-replicants_emlyn_f32.wasm": "a415ece9acb38ae6" };

// --break <what> SABOTAGES one measurement and passes only if the check it
// belongs to notices: a check nobody can fail is not a check.
const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
const DEFAULT_CART = "docs/demo-replicants_emlyn.wasm", F32_CART = "docs/demo-replicants_emlyn_f32.wasm";
const CART = process.argv.includes("--cart") ? process.argv[process.argv.indexOf("--cart") + 1] : DEFAULT_CART;
let failures = 0;
function check(name, got, want) {
    const ok = got === want;
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}: got ${got}, want ${want}`);
}

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
    const cartBytes = await readFile(cart), env = { memory, ...rom };
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

/// ~5 s of the requested subtune on the sealed audio machine. audioUnhandled*
/// is the SNDH player's dropped-hardware-write diagnostic: a write nobody
/// answers is silent by construction, so a music harness asserts it is empty
/// (it named the $FF8804/$FF8806 movep.l bug in one line).
async function sndhPlay(name, tune) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n]; // the sealed YM
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(tune);
    let peak = 0;
    for (let b = 0; b < 250; b++) {
        audio.audioRender(882);
        for (const v of new Float32Array(memory.buffer, m.audioLeftPtr(), 882)) peak = Math.max(peak, Math.abs(v));
    }
    const unhandled = [];
    for (let i = 0; i < Math.min(8, audio.audioUnhandledCount()); i++) unhandled.push("$" + audio.audioUnhandled(i).toString(16).toUpperCase());
    return { peak, stuckPc: audio.audioSndhStuckPc(), unhandled };
}

const { memory, machine, demo } = await boot(CART);
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const VB = machine.hwVideoBase();
const regs = new DataView(memory.buffer, VB, OFF_PAL);
const PW = regs.getUint16(REG_FB_STRIDE, true); // 400, the whole raster
const palette = () => new Uint32Array(memory.buffer, VB + OFF_PAL, 256);
const indices = () => new Uint8Array(memory.buffer, VB + regs.getUint32(REG_FB_BASE, true), PW * H);
const BLACK_RGBA = 0xff000000;
let frames = 0;

/// The bucket colours the plane's HBL installs for PHYSICAL line `line` — the
/// raster table itself, read the way the machine reads it.
function bucketsAt(line) {
    demo.hblDispatch(HBL_PLANE_ID, 0, line, MAGIC_X);
    return Array.from(palette().subarray(FIRST_BUCKET, FIRST_BUCKET + MAX_BUCKETS));
}

/// What the whole 400x280 plane is made of this frame.
///   pixels   a byte per class: bar.png colours used as PIXELS must stay 0
///   count    buckets in use, from the ramp itself (1 = one raster register)
///   tilted   lines whose buckets are not all one colour (only a tilt does that)
///   changes  lines whose bucket palette differs from the line above
///   side     non-black raster pixels in the LEFT and RIGHT border columns
///   logoSide logo pixels there, and fontSide scrolltext pixels: the logo and
///            the scrolltext are drawn to the whole raster too
///   tbLit    TOP and BOTTOM border lines (physical 0..19, 260..279) whose used
///            buckets are not all black: only ZIG mode fills them
///   lines    every line's used bucket colours, for the seam checks
function census() {
    const lfb = indices();
    const n = { bucket: 0, bar: 0, art: 0, other: 0 };
    let count = 1, tilted = 0, changes = 0, prev = "", side = 0, logoSide = 0, fontSide = 0;
    let fontTop = 1e9, fontBottom = -1, lowest = -1, tbLit = 0;
    const all = [];
    for (let y = 0; y < H; y++) {
        let b = bucketsAt(broke === "rasters" ? CONTENT_Y : y); // sabotage: one static palette
        const tb = y < CONTENT_Y || y >= CONTENT_Y + CONTENT_H;
        if (tb && broke === "topbottom") b = b.map(() => BLACK_RGBA); // sabotage: borders closed
        all.push(b);
        const key = b.join(",");
        if (y && key !== prev) changes++;
        prev = key;
        for (let x = 0; x < PW; x++) {
            const i = lfb[y * PW + x];
            // sabotage: pretend nothing is drawn outside the content window,
            // which is the .top_bottom + window-clipped behaviour this replaced
            const inBorder = (x < CONTENT_X || x >= CONTENT_X + CONTENT_W) && broke !== "borders";
            if (i >= FIRST_BUCKET) {
                n.bucket++;
                count = Math.max(count, i - FIRST_BUCKET + 1);
                if (inBorder && b[i - FIRST_BUCKET] !== BLACK_RGBA) side++;
            } else if (i >= FIRST_BAR && i < FIRST_FONT) n.bar++;
            else if (i >= FIRST_FONT) {
                n.art++;
                if (i >= FIRST_LOGO) {
                    if (inBorder) logoSide++;
                } else {
                    if (inBorder) fontSide++;
                    const row = y - CONTENT_Y;
                    if (row < fontTop) fontTop = row;
                    if (row > fontBottom) fontBottom = row;
                }
            } else n.other++;
            if (i !== 0) lowest = Math.max(lowest, y);
        }
    }
    const lines = all.map((b) => b.slice(0, count));
    for (const [y, used] of lines.entries()) {
        if (used.some((c) => c !== used[0])) tilted++;
        if ((y < CONTENT_Y || y >= CONTENT_Y + CONTENT_H) && used.some((c) => c !== BLACK_RGBA)) tbLit++;
    }
    return { ...n, count, tilted, changes, side, logoSide, fontSide, fontTop, fontBottom, lowest, tbLit, lines };
}

/// SHA-256 prefixes of the shot, whole (`all`) and of the content window's
/// rows 20..259 (`win`): ORIGINAL's frames and ZIG's window are pinned by them.
async function shot(path) {
    const buf = await shotOf({ memory, machine }, path);
    const sha = (b) => createHash("sha256").update(b).digest("hex").slice(0, 16);
    const hdr = buf.length - PW * H * 3;
    const r = { all: sha(buf), win: sha(buf.subarray(hdr + CONTENT_Y * PW * 3, hdr + (CONTENT_Y + CONTENT_H) * PW * 3)) };
    console.log(`        (go() call ${frames}, sha ${r.all}, window ${r.win})`);
    return r;
}

/// A PPM of the composited plane, one pixel per plane column, of any instance.
async function shotOf(m, path) {
    m.machine.hwRenderPlane(0);
    const w = m.machine.hwPhysWidth();
    const px = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), w * H * 4);
    const hdr = new TextEncoder().encode(`P6\n${PW} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + PW * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < PW; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * PW + x) * 3 + c] = px[(y * w + x * 2) * 4 + c];
    await writeFile(path, buf);
    console.log(`  shot: ${path}`);
    return buf;
}

function run(n) {
    for (let i = 0; i < n; i++) demo.frame(16.6);
    frames += n;
}

const out = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/replicants_emlyn";
await mkdir(out, { recursive: true });
if (W !== 800 || PW !== 400) console.log(`  note: physical ${W}x${H}, plane stride ${PW}`);

// Frame 1 is go()'s first call: rotation 0.04, logo at posx 0, ORIGINAL mode,
// and the ring's leftmost letter still at canvas x 700 — off the 640 canvas.
run(1);
const sha1 = await shot(`${out}/0001.ppm`);
let c = census();
console.log(`  frame 1: ${c.count} bucket(s), ${c.bucket} bucket px, ${c.art} art px, bar-as-pixel ${c.bar}, palette changes on ${c.changes} lines, border raster ${c.side} logo ${c.logoSide}`);
check("bar.png's colours are never pixels — the bars are only ever palette", c.bar, 0);
check("the background is nothing but bucket indices", c.bucket > 0, true);
check("the raster table really changes from line to line", c.changes > 100, true);
check("theta 0 needs ONE colour register a line, as a raster bar does", c.count, 1);
check("the rasters run into the LEFT and RIGHT borders", c.side > 0, true);
check("... and so does the logo, which is drawn to the whole raster", c.logoSide > 0, true);
check("content reaches the opened bottom border", c.lowest >= 240, true);
check("the logo depacked and draws over the rasters", c.art > 0, true);

// 16 frames at 4 canvas pixels bring letter 0's left edge to canvas 640; by 120
// the 32-tall tiles are well inside their band. drawTile's y is the TOP.
run(119);
const sha120 = await shot(`${out}/0120.ppm`);
c = census();
console.log(`  frame 120: ${c.count} bucket(s), scroller rows ${c.fontTop}..${c.fontBottom}, in the border ${c.fontSide}`);
check("ORIGINAL keeps the scroller flat, inside ST rows 195..226", c.fontTop >= SCROLL_TOP && c.fontBottom <= SCROLL_BOTTOM, true);
check("the scrolltext runs into the LEFT and RIGHT borders too", c.fontSide > 0, true);
// ORIGINAL is pinned to the screen it was before ZIG opened the top and bottom
// borders (the shots of the build before, 2026-10-20), and its border lines
// are black: only ZIG fills them.
const zc = makeZigChecks({ check, census, run, demo, fire: () => demo.input(DIR_FIRE), broke });
check("ORIGINAL frames 1 and 120 are the screen pinned before ZIG's borders opened", `${sha1.all} ${sha120.all}`, ORIGINAL_SHA);
zc.closed(c, "ORIGINAL frame 120");

// Space switches ORIGINAL -> ZIG (the host sends it as input(5): the cart does
// not own the keyboard). Sabotage: never press it.
if (broke !== "spin") demo.input(DIR_FIRE);
run(SPIN_FRAMES);
const sha160 = await shot(`${out}/0160-zig.ppm`);
c = census();
console.log(`  ZIG + ${SPIN_FRAMES}: ${c.count} buckets, ${c.tilted} tilted lines, bar-as-pixel ${c.bar}`);
check("ZIG mode tilts the bars off horizontal", c.tilted > 200, true);
check("... and bends the scrolltext off flat with them", c.fontBottom - c.fontTop > 40, true);
check("... and pays for it with a finer ramp", c.count > 50, true);
check("a tilted bar is still only ever palette entries", c.bar, 0);
zc.borders(c, `ZIG + ${SPIN_FRAMES}`);
check(`ZIG + ${SPIN_FRAMES}: the content window is the one pinned before the borders opened`, sha160.win, ZIG_WINDOW_SHA[CART]);

// Space again switches back, and it has to answer the key PROMPTLY: the short
// way round at eight times the sweep is at most 20 frames.
if (broke !== "spin") demo.input(DIR_FIRE);
run(RETURN_FRAMES);
c = census();
console.log(`  ORIGINAL + ${RETURN_FRAMES}: ${c.count} buckets, ${c.tilted} tilted lines`);
check("Space switches back to ORIGINAL within 20 frames", c.count === 1 && c.tilted === 0, true);
check("... and the scrolltext is dead flat again with it", c.fontBottom - c.fontTop < 32, true);
zc.closed(c, `ORIGINAL + ${RETURN_FRAMES}`);
zc.keys(SPIN_FRAMES, RETURN_FRAMES);

// The cart declares key() (for F), so Escape is its own: wants_quit -> menu.
demo.key(K_ESC);
check("Escape still leaves for the menu", demo.pollCartRequest(), -1);

// THE LEFT EDGE, pixel for pixel. The remake's ring recycles a letter at
// canvas -64, which on this raster is plane column 8: the letter vanished with
// all 32 of its columns still in the opened left border. So two fresh
// machines run in lockstep, one left in ORIGINAL and one switched to ZIG at
// once (posx never depends on the mode, only the bend does), and across the
// frames where letters cross the left edge:
//   ORIGINAL  a flat scroller moving 2 ST px a frame is its own reference:
//             every scrolltext pixel of frame n+1 at column x is the one frame n
//             had at x+2, border columns included — a letter that vanishes, or
//             is cut, breaks that on the very next frame.
//   ZIG       each column of the bent scroller is the ORIGINAL machine's same
//             column, index for index, moved down by one whole number of rows.
//   both      columns 0..7, where the remake's ring can never reach, carry ink.
// --break leftclip reproduces the remake's ring on the readout: any letter
// whose left edge is at or left of column 8 is dropped, as the cart used to.
const EDGE_FROM = 190, EDGE_TO = 240; // letter 0 reaches the left border at frame 176 and leaves at 212
const OLD_EXIT_X = 8; // canvas -64 halved, on the raster
{
    const a = await boot(CART);
    const b = await boot(CART);
    b.demo.input(DIR_FIRE);
    const plane = (m) => {
        const r = new DataView(m.memory.buffer, m.machine.hwVideoBase(), OFF_PAL);
        return new Uint8Array(m.memory.buffer, m.machine.hwVideoBase() + r.getUint32(REG_FB_BASE, true), PW * H);
    };
    /// The scrolltext's own pixels as a [x][y] index grid, 0 where it has none.
    const ink = (m, n) => {
        const lfb = plane(m), cols = [];
        const edge0 = 392 - 2 * n; // letter 0's left edge; the others are 32 apart
        for (let x = 0; x < PW; x++) {
            const col = new Uint8Array(H);
            const letterLeft = x - ((((x - edge0) % 32) + 32) % 32);
            const dropped = broke === "leftclip" && letterLeft <= OLD_EXIT_X;
            if (!dropped) for (let y = 0; y < H; y++) {
                const i = lfb[y * PW + x];
                if (i >= FIRST_FONT && i < FIRST_LOGO) col[y] = i;
            }
            cols.push(col);
        }
        return cols;
    };
    const same = (p, q, shift) => p.every((v, y) => v === (q[y - shift] ?? 0));
    const shiftOf = (p, q) => { // the whole-row move that turns q into p, or null
        const top = (c) => c.findIndex((v) => v !== 0);
        const tp = top(p), tq = top(q);
        if (tp < 0 || tq < 0) return tp === tq ? 0 : null;
        return same(p, q, tp - tq) ? tp - tq : null;
    };
    for (let n = 0; n < EDGE_FROM; n++) { a.demo.frame(16.6); b.demo.frame(16.6); }
    let prev = ink(a, EDGE_FROM), flatBad = 0, bentBad = 0, flatEdge = 0, bentEdge = 0, half = false;
    for (let n = EDGE_FROM + 1; n <= EDGE_TO; n++) {
        a.demo.frame(16.6);
        b.demo.frame(16.6);
        const fa = ink(a, n), fb = ink(b, n);
        for (let x = 0; x < PW - 2; x++) if (!same(fa[x], prev[x + 2], 0)) flatBad++;
        for (let x = 0; x < CONTENT_X; x++) {
            if (shiftOf(fb[x], fa[x]) === null) bentBad++;
            if (x < OLD_EXIT_X && fa[x].some((v) => v)) flatEdge++;
            if (x < OLD_EXIT_X && fb[x].some((v) => v)) bentEdge++;
        }
        if (!half && (392 - 2 * n) === -16) { // letter 0 exactly half into the left border
            half = true;
            await shotOf(a, `${out}/left-edge-original.ppm`);
            await shotOf(b, `${out}/left-edge-zig.ppm`);
        }
        prev = fa;
    }
    console.log(`  left edge, frames ${EDGE_FROM}..${EDGE_TO}: ORIGINAL ${flatBad} column(s) off the scroll, ${flatEdge} inked in cols 0..7; ZIG ${bentBad} column(s) off the ORIGINAL, ${bentEdge} inked in cols 0..7`);
    check("ORIGINAL: every scrolltext pixel moves 2 columns a frame, through the left border", flatBad, 0);
    check("ORIGINAL: letters reach columns 0..7 and scroll off the raster", flatEdge > 0, true);
    check("ZIG: every left-border column is the ORIGINAL's, bent by whole rows", bentBad, 0);
    check("ZIG: letters reach columns 0..7 and scroll off the raster", bentEdge > 0, true);
}

const dec = new TextDecoder();
const song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
check("it asks for the tune the YM dump matched", `${song} #${demo.songTune()}`, `${WANT_MUSIC} #${WANT_TUNE}`);
const r = await sndhPlay(WANT_MUSIC, WANT_TUNE);
console.log(`  ${WANT_MUSIC} #${WANT_TUNE}: peak ${r.peak?.toFixed(4)}, stuck PC ${r.stuckPc}, unhandled [${r.unhandled}]`);
check("the tune plays (not silence, no stuck PC)", !r.why && r.peak > 0.01 && !r.stuckPc, true);
check("no hardware write went unanswered", r.unhandled?.length, 0);

check("no zg.mem allocation was refused", machine.hwRamAllocFailures(), 0);

// ONE SCREEN, TWO NUMBER SYSTEMS. The default cart computes in integers
// (emlyn/fixed.zig) and replicants_emlyn_f32 runs the CODEF algorithm in f32;
// they must show the same screen, a rounding apart: a band edge one line or one
// bucket over, a scrolltext column one row over. Both run in lockstep through
// ZIG mode (every angle, so every ramp width) and back; every 10th frame the
// rendered planes are compared pixel for pixel. --break fixed compares against
// a cart a frame AHEAD instead, which a real difference in the bars looks like.
//
// F switches either cart's maths live (emlyn/app.zig, swap.zig). Pressed before
// the first frame, the default cart must BE the f32 cart, pixel for pixel, and
// pressed twice it must be itself again; pressed mid-sweep, it must carry the
// state across (the screen stays within the rounding of the other cart, never
// restarts). --break fkey never presses F, so the identity has to fail.
if (CART === DEFAULT_CART) {
    const pixels = (m) => {
        m.machine.hwRenderPlane(0);
        const w = m.machine.hwPhysWidth(), px = new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), w * H);
        return Uint32Array.from({ length: PW * H }, (_, i) => px[Math.floor(i / PW) * w + (i % PW) * 2]);
    };
    // The worst pixel count apart, every 10th of 420 frames: ZIG at once, home at 330.
    // `keys(n)` returns the keys each cart gets before frame n: [a's, b's].
    const lockstep = (a, b, keys = () => [[], []]) => {
        a.demo.input(DIR_FIRE);
        b.demo.input(DIR_FIRE);
        let worst = 0, worstAt = 0;
        for (let n = 1; n <= 420; n++) {
            if (n === 330) { a.demo.input(DIR_FIRE); b.demo.input(DIR_FIRE); } // and home again
            const [ka, kb] = keys(n);
            for (const k of ka) a.demo.key(k);
            for (const k of kb) b.demo.key(k);
            a.demo.frame(16.6);
            b.demo.frame(16.6);
            if (n % 10) continue;
            const pa = pixels(a), pb = pixels(b);
            let d = 0;
            for (let i = 0; i < pa.length; i++) if (pa[i] !== pb[i]) d++;
            if (d > worst) { worst = d; worstAt = n; }
        }
        return { worst, worstAt };
    };
    const K_F = 0x66, fkey = broke === "fkey" ? [] : [K_F];
    const a = await boot(CART), b = await boot(F32_CART);
    if (broke === "fixed") b.demo.frame(16.6);
    let r = lockstep(a, b);
    console.log(`  fixed vs f32, 42 frames over ZIG and back: at most ${r.worst} of ${PW * H} pixels differ (frame ${r.worstAt})`);
    check("the fixed-point cart shows the f32 cart's screen (under 1% of the pixels on every frame)", r.worst < PW * H / 100, true);

    r = lockstep(await boot(CART), await boot(F32_CART), (n) => [n === 1 ? fkey : [], []]);
    check("F before frame 1: the default cart IS the f32 cart, pixel for pixel", r.worst, 0);
    r = lockstep(await boot(CART), await boot(CART), (n) => [n === 1 ? [...fkey, ...fkey] : [], []]);
    check("F twice: the default cart is itself again, pixel for pixel", r.worst, 0);
    r = lockstep(await boot(CART), await boot(F32_CART), (n) => [n === 200 ? fkey : [], []]);
    console.log(`  F at frame 200 (mid-sweep) vs the f32 cart: at most ${r.worst} pixels differ (frame ${r.worstAt})`);
    check("F mid-sweep carries the screen across (under 1% from the f32 cart)", r.worst < PW * H / 100, true);

    // ORIGINAL ignores ZIG's style keys: 1 and 2 at frame 50, and 200 frames
    // later not one pixel differs from a cart that never got them.
    const [p, q] = [await boot(CART), await boot(CART)];
    let off = 0;
    for (let n = 1; n <= 200; n++) {
        if (n === 50) { p.demo.key(0x31); p.demo.key(0x32); }
        p.demo.frame(16.6);
        q.demo.frame(16.6);
        if (n % 10) continue;
        const pp = pixels(p), pq = pixels(q);
        off = Math.max(off, pp.reduce((d, v, i) => d + (v !== pq[i] ? 1 : 0), 0));
    }
    check("ORIGINAL: 1 and 2 change not one pixel", off, 0);
}

// Warm frame cost in ZIG mode, which is the expensive one: 600 frames sweep
// almost two full turns, so the average covers every ramp width from 1 bucket
// to the palette's 149. The plane figure includes the per-line palette writes
// and the border flicker.
demo.input(DIR_FIRE);
const N = 600;
let bestCart = Infinity, bestPlane = Infinity;
for (let i = 0; i < 5; i++) {
    let t = process.hrtime.bigint();
    for (let k = 0; k < N; k++) demo.frame(16.6);
    bestCart = Math.min(bestCart, Number(process.hrtime.bigint() - t) / 1e6 / N);
    t = process.hrtime.bigint();
    for (let k = 0; k < N; k++) machine.hwRenderPlane(0);
    bestPlane = Math.min(bestPlane, Number(process.hrtime.bigint() - t) / 1e6 / N);
}
console.log(`  frame cost: cart ${bestCart.toFixed(3)} ms, plane ${bestPlane.toFixed(3)} ms`);

if (broke) {
    const ok = failures > 0;
    console.log(ok ? `\nreplicants_emlyn: PASS (--break ${broke} was caught)` : `\nreplicants_emlyn: FAILED — --break ${broke} was not caught`);
    process.exit(ok ? 0 : 1);
}
console.log(failures ? `\nreplicants_emlyn: ${failures} FAILED` : "\nreplicants_emlyn: PASS");
process.exit(failures ? 1 : 0);
