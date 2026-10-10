// Headless FUJI HOBBYTRONIC driver: boots the cart (apps/zig/scenes/fuji_hobbytronic.zig)
// as docs/ loads it and checks the screen's three promises.
//
//   node apps/fuji_hobbytronic_headless.mjs [<shot dir>] [--break raster|still|song]
//
// Checked:
//   1. the MUSIC: the cart requests Hobbytronic_92_1.sap song 1 when it starts; the
//      file is in docs/music/, is ASMA's (NAME, AUTHOR, TYPE B), loads in
//      docs/demo-audio.wasm's SAP player and is not silent on the POKEY;
//   2. the LOGO: front-cap pixels (palette index FRONT) and shaded sides are drawn,
//      the picture changes from frame to frame, and half a turn later the back cap
//      shows instead of the front (it really rotates, it is not a sprite);
//   3. the RASTERS are REAL: the colour of FRONT is read after the plane's HBL on
//      every line, it differs down the logo (many colours, changing most lines),
//      every front pixel the machine displays on line y has the colour that line's
//      register held, all are ST-legal (channel = nibble x 32), at most 2 registers
//      change per line, and the bars roll from one frame to the next;
//   4. the credits scroller moves; Escape leaves to the menu.
//
// --break raster: the plane's HBL is never dispatched, so the logo is one flat colour.
// --break still:  the frame is not advanced between the two pictures compared.
// --break song:   the request's song is read as 0 (DEFSONG, what requestSong sends).
// Each must fail.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const argv = process.argv.slice(2);
const BREAK = argv.includes("--break") ? argv[argv.indexOf("--break") + 1] : null;
if (BREAK !== null && !["raster", "still", "song"].includes(BREAK)) { console.error(`fuji_hobbytronic: unknown --break ${BREAK}`); process.exit(1); }
const OUT = argv[0] && !argv[0].startsWith("--") ? argv[0] : null;

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const OFF_PAL = 0x0100, REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44; // memmap.zig
const FRONT = 4, BACK = 5, SIDE = 6, SIDES = 8, SCROLL = 14; // raster.zig, logo.zig
const SCROLL_Y = 184, H = 200, W = 320;
const MUSIC = "Hobbytronic_92_1.sap";
const K_ESC = 0xE012;
const errors = [];
const fail = (m) => errors.push(m);

let lines = null; // while recording: per line, the registers after the HBL ran
async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo, pal;
    const hbl = (id, p, l, x) => {
        if (BREAK !== "raster") demo.hblDispatch(id, p, l, x);
        if (lines && p === 0 && l < H) lines[l] = [pal()[FRONT], pal()[BACK], pal()[SCROLL]];
    };
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch: hbl } })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile("docs/demo-fuji_hobbytronic.wasm"), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const VB = machine.hwVideoBase();
    pal = () => new Uint32Array(memory.buffer, VB + OFF_PAL, 256);
    const regs = () => new DataView(memory.buffer, VB, OFF_PAL);
    const indices = () => new Uint8Array(memory.buffer, VB + regs().getUint32(REG_FB_BASE, true), regs().getUint16(REG_FB_STRIDE, true) * H);
    return { memory, machine, demo, pal, indices, stride: () => regs().getUint16(REG_FB_STRIDE, true) };
}

const S = await boot();
const step = (advance = true) => { S.machine.hwClear(); if (advance) S.demo.frame(1000 / 60); lines = new Array(H); S.machine.hwRenderPlane(0); const l = lines; lines = null; return l; };
const count = (idx, pred) => { let n = 0; for (const v of idx) if (pred(v)) n++; return n; };
const PW = S.machine.hwPhysWidth(), BX = S.machine.hwBorderX(), BY = S.machine.hwBorderY();
const SX = (PW - 2 * BX) / W; // physical pixels per low-res pixel (2: the raster is medium-res wide)
const shown = (x, y) => new DataView(S.memory.buffer, S.machine.hwPhysicalPtr()).getUint32(((BY + y) * PW + BX + x * SX) * 4, true);

// --- 1: the music ------------------------------------------------------------
step();
if (!S.demo.pollSongRequest()) fail("no song request when the screen starts");
else {
    const name = new TextDecoder().decode(new Uint8Array(S.memory.buffer, S.demo.songNamePtr(), S.demo.songNameLen()));
    const tune = BREAK === "song" ? 0 : S.demo.songTune();
    if (name !== MUSIC || tune !== 1) fail(`requested ${name} song ${tune}, want ${MUSIC} song 1`);
}
const sap = await readFile(`docs/music/${MUSIC}`).catch(() => null);
if (!sap) fail(`${MUSIC} is not in docs/music/, the site would 404`);
else {
    const head = sap.subarray(0, 400).toString("latin1");
    for (const tag of [`NAME "Hobbytronic '92 - 1"`, `AUTHOR "Stephan Duesterhoeft (Benjy)"`, "TYPE B"])
        if (!head.includes(tag)) fail(`${MUSIC}: no ${tag} in its header`);
    const loud = await playSap(sap);
    if (loud < 0.01) fail(`${MUSIC}: silence over 1.5 s on the POKEY`);
}

async function playSap(bytes) {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 }); // machine/sdk/audio.zig
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const a = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    a.audioInit();
    new Uint8Array(memory.buffer, a.audioSongPtr(), bytes.length).set(bytes);
    if (!a.audioLoadSap(bytes.length)) { fail(`${MUSIC}: the SAP player refused it, status ${a.audioSapStatus()}`); return 0; }
    a.audioSapPlay(1);
    let lo = Infinity, hi = -Infinity;
    for (let done = 0; done < 1.5 * 44100; done += 882) {
        a.audioRender(882);
        for (const s of new Float32Array(memory.buffer, machine.audioLeftPtr(), 882)) { lo = Math.min(lo, s); hi = Math.max(hi, s); }
    }
    return hi - lo;
}

// --- 2 + 3: the logo and its rasters -----------------------------------------
for (let i = 0; i < 30; i++) step();
const regs30 = step();
const idx30 = Uint8Array.from(S.indices()).subarray(0, S.stride() * H);
const front30 = count(idx30, (v) => v === FRONT);
const sides30 = count(idx30, (v) => v >= SIDE && v < SIDE + SIDES);
if (front30 < 1500) fail(`frame 31: ${front30} front-cap pixels, want the Fuji's face (1500+)`);
if (sides30 < 100) fail(`frame 31: ${sides30} side pixels, want the solid's flanks`);
if (OUT) { await mkdir(OUT, { recursive: true }); await writeFile(`${OUT}/fuji_hobbytronic.png`, png()); }

const frontLines = [];
for (let y = 0; y < SCROLL_Y; y++) if (idx30.subarray(y * S.stride(), y * S.stride() + W).includes(FRONT)) frontLines.push(y);
const colours = new Set(frontLines.map((y) => regs30[y]?.[0]));
let changes = 0, overBudget = 0, offGrid = 0, mismatched = 0;
for (let i = 1; i < frontLines.length; i++) if (regs30[frontLines[i]]?.[0] !== regs30[frontLines[i - 1]]?.[0]) changes++;
for (let y = 1; y < H; y++) {
    const a = regs30[y], b = regs30[y - 1];
    if (a && b && a.filter((v, k) => v !== b[k]).length > 2) overBudget++;
    for (const v of a ?? []) for (let k = 0; k < 3; k++) { const c = (v >>> (8 * k)) & 255; if (c % 32 || c > 224) offGrid++; }
}
for (const y of frontLines) for (let x = 0; x < W; x++)
    if (idx30[y * S.stride() + x] === FRONT && shown(x, y) !== regs30[y][0]) mismatched++;
if (colours.size < 8) fail(`the front cap shows ${colours.size} colours down its ${frontLines.length} lines, want a raster (8+)`);
if (changes < frontLines.length / 2) fail(`the front cap's register changed on ${changes} of ${frontLines.length} lines, want most`);
if (overBudget) fail(`${overBudget} lines change more than 2 colour registers (the per-line budget)`);
if (offGrid) fail(`${offGrid} raster colour channels off the ST's nibble x 32 grid`);
if (mismatched) fail(`${mismatched} front pixels are not displayed in their line's register colour`);

const regs31 = step(BREAK !== "still");
const idx31 = S.indices();
let moved = 0;
for (let i = 0; i < idx30.length; i++) if ((idx30[i] === FRONT) !== (idx31[i] === FRONT)) moved++;
if (moved < 50) fail(`the front cap moved ${moved} pixels in a frame, want a turning logo`);
if (!frontLines.some((y) => regs31[y]?.[0] !== regs30[y]?.[0])) fail("the raster bars did not roll from one frame to the next");
let scroll = 0;
for (let y = SCROLL_Y; y < SCROLL_Y + 8; y++) for (let x = 0; x < W; x++) if ((idx30[y * S.stride() + x] === SCROLL) !== (idx31[y * S.stride() + x] === SCROLL)) scroll++;
if (scroll === 0) fail("the credits scroller did not move in a frame");

for (let i = 0; i < 170; i++) step(); // about half a turn (341 frames a turn)
const idxHalf = S.indices();
const frontHalf = count(idxHalf, (v) => v === FRONT), backHalf = count(idxHalf, (v) => v === BACK);
if (backHalf < 1500 || frontHalf > 0) fail(`half a turn on: ${backHalf} back-cap and ${frontHalf} front-cap pixels, want the back showing`);

// --- 4: the way out -------------------------------------------------------------
S.demo.key(K_ESC);
if (S.demo.pollCartRequest() !== -1) fail("Escape does not leave to the menu");

function png() {
    const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = crcT[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const raw = Buffer.alloc(H * (W * 3 + 1));
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const v = shown(x, y), o = y * (W * 3 + 1) + 1 + x * 3;
        raw[o] = v & 255; raw[o + 1] = (v >>> 8) & 255; raw[o + 2] = (v >>> 16) & 255;
    }
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

if (BREAK) {
    const caught = errors.length > 0;
    console.log(caught ? `fuji_hobbytronic: PASS (--break ${BREAK} caught: ${errors.length} errors, first: ${errors[0]})`
        : `fuji_hobbytronic: FAIL, --break ${BREAK} was NOT caught`);
    process.exit(caught ? 0 : 1);
}
if (errors.length) {
    console.log("fuji_hobbytronic: WRONG");
    for (const e of errors.slice(0, 12)) console.log("  " + e);
    process.exit(1);
}
console.log(`fuji_hobbytronic: ${MUSIC} song 1 requested and playing on the POKEY; frame 31 = ${front30} front + ${sides30} side px, ` +
    `${colours.size} raster colours over ${frontLines.length} lines (${changes} changes, all ST-legal, <= 2 registers a line, displayed as written), ` +
    `bars rolling, logo turning (${moved} px a frame; back cap ${backHalf} px half a turn on), scroller moving, Escape leaves`);
