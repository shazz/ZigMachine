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
//   node apps/replicants_emlyn_headless.mjs [outdir] [--break <what>]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

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

// --break <what> SABOTAGES one measurement and passes only if the check it
// belongs to notices: a check nobody can fail is not a check.
const broke = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : "";
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

const { memory, machine, demo } = await boot("docs/demo-replicants_emlyn.wasm");
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
function census() {
    const lfb = indices();
    const n = { bucket: 0, bar: 0, art: 0, other: 0 };
    let count = 1, tilted = 0, changes = 0, prev = "", side = 0, logoSide = 0, fontSide = 0;
    let fontTop = 1e9, fontBottom = -1, lowest = -1;
    for (let y = 0; y < H; y++) {
        const b = bucketsAt(broke === "rasters" ? CONTENT_Y : y); // sabotage: one static palette
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
        const used = b.slice(0, count);
        if (used.some((c) => c !== used[0])) tilted++;
    }
    return { ...n, count, tilted, changes, side, logoSide, fontSide, fontTop, fontBottom, lowest };
}

async function shot(path) {
    machine.hwRenderPlane(0);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const hdr = new TextEncoder().encode(`P6\n${PW} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + PW * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < PW; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * PW + x) * 3 + c] = px[(y * W + x * 2) * 4 + c];
    await writeFile(path, buf);
    console.log(`  shot: ${path} (go() call ${frames})`);
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
await shot(`${out}/0001.ppm`);
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
await shot(`${out}/0120.ppm`);
c = census();
console.log(`  frame 120: ${c.count} bucket(s), scroller rows ${c.fontTop}..${c.fontBottom}, in the border ${c.fontSide}`);
check("ORIGINAL keeps the scroller flat, inside ST rows 195..226", c.fontTop >= SCROLL_TOP && c.fontBottom <= SCROLL_BOTTOM, true);
check("the scrolltext runs into the LEFT and RIGHT borders too", c.fontSide > 0, true);

// Space switches ORIGINAL -> ZIG (the host sends it as input(5); this cart
// declares no key(), so it keeps the host's Escape). Sabotage: never press it.
if (broke !== "spin") demo.input(DIR_FIRE);
run(SPIN_FRAMES);
await shot(`${out}/0160-zig.ppm`);
c = census();
console.log(`  ZIG + ${SPIN_FRAMES}: ${c.count} buckets, ${c.tilted} tilted lines, bar-as-pixel ${c.bar}`);
check("ZIG mode tilts the bars off horizontal", c.tilted > 200, true);
check("... and bends the scrolltext off flat with them", c.fontBottom - c.fontTop > 40, true);
check("... and pays for it with a finer ramp", c.count > 50, true);
check("a tilted bar is still only ever palette entries", c.bar, 0);

// Space again switches back, and it has to answer the key PROMPTLY: the short
// way round at eight times the sweep is at most 20 frames.
if (broke !== "spin") demo.input(DIR_FIRE);
run(RETURN_FRAMES);
c = census();
console.log(`  ORIGINAL + ${RETURN_FRAMES}: ${c.count} buckets, ${c.tilted} tilted lines`);
check("Space switches back to ORIGINAL within 20 frames", c.count === 1 && c.tilted === 0, true);
check("... and the scrolltext is dead flat again with it", c.fontBottom - c.fontTop < 32, true);

// The cart declares no key(), so demo_main's own Escape -> menu still applies.
demo.key(K_ESC);
check("Escape still leaves for the menu", demo.pollCartRequest(), -1);

const dec = new TextDecoder();
const song = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
check("it asks for the tune the YM dump matched", `${song} #${demo.songTune()}`, `${WANT_MUSIC} #${WANT_TUNE}`);
const r = await sndhPlay(WANT_MUSIC, WANT_TUNE);
console.log(`  ${WANT_MUSIC} #${WANT_TUNE}: peak ${r.peak?.toFixed(4)}, stuck PC ${r.stuckPc}, unhandled [${r.unhandled}]`);
check("the tune plays (not silence, no stuck PC)", !r.why && r.peak > 0.01 && !r.stuckPc, true);
check("no hardware write went unanswered", r.unhandled?.length, 0);

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
