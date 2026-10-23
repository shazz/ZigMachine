// Headless GNOMES driver (cart 104): The Gnomes Group's "BB25" cracktro intro
// (Buxton Bytes 2025), ported from the original ST binary. This harness holds the
// cart to its OWN model of the screen, written from the port's documented
// layout (apps/zig/scenes/gnomes.zig) and the ripped assets, not from the Zig:
//
//   state   every frame, the rainbow roll, the big band's text index and scroll
//           position, and the TTY's pointer/column/row/pause equal the model's
//   model   the composited 800x280 raster equals the model's pixel for pixel:
//           SpongeBob, the boxes, the rimmed logo, the 4x band and the typed
//           cyan message, every frame to 900 (two full TTY cycles, wipes
//           included), then checkpoints -- with the palette per PHYSICAL line,
//           so the three copper slots (rainbow, T2 brick, T1 logo ramp) are
//           pinned row by row in every border too
//   raster  the left and right border columns carry the rainbow on every line
//           (real per-line register writes, borders open, full width): dozens
//           of distinct colours down one column, no two neighbours equal
//   music   custodian.sndh #1 requested once at start; F1-F6 request #1..#6
//   keys    Escape and Back hand the screen back
//   soak    no zg.mem allocation refused
//
//   node apps/gnomes_headless.mjs [outdir]
//   node apps/gnomes_headless.mjs --break raster|state|pixels|music   (each must FAIL)
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const OUT = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/gnomes";
const TICK_MS = 20.0;

const BREAKS = ["raster", "state", "pixels", "music"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);

// ---------------- boot (the ikplus shape) -----------------------------------
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romEnv = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
const rom = (await WebAssembly.instantiate(await readFile("docs/rom.wasm"), { env: romEnv })).instance.exports;
const noop = () => {};
const cartBytes = await readFile("docs/demo-gnomes.wasm");
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
const ok = (cond, msg) => {
    console.log(`  ${cond ? "ok  " : "FAIL"} ${msg}`);
    if (!cond) errors.push(msg);
};

// ---------------- the ripped assets and the port's layout -------------------
const A = "apps/zig/assets/screens/gnomes/";
const font = await readFile(A + "font8.bin"); // 256 glyphs x 8 rows x 8 B, 1 = ink
const sbob = await readFile(A + "sbob.raw"); // 144x158 indices 0..15 (ST 4-plane decode)
const textSrc = await readFile("apps/zig/scenes/gnomes/text.zig", "utf8");
const zigString = (name) => {
    const m = textSrc.match(new RegExp(`pub const ${name} = "((?:[^"\\\\]|\\\\.)*)";`));
    if (!m) throw new Error(`text.zig: no ${name}`);
    return JSON.parse(`"${m[1]}"`);
};
const BIG = zigString("BIG_TEXT");
const CYAN = zigString("CYAN_TEXT");
const TTY_PAUSE = 250;

const RAINBOW = [
    0x710, 0x720, 0x730, 0x740, 0x750, 0x760, 0x770, 0x670, 0x570, 0x470, 0x370, 0x270, 0x170, 0x070, 0x071, 0x072,
    0x073, 0x074, 0x075, 0x076, 0x077, 0x067, 0x057, 0x047, 0x037, 0x027, 0x017, 0x007, 0x107, 0x207, 0x307, 0x407,
    0x507, 0x607, 0x707, 0x706, 0x705, 0x704, 0x703, 0x702, 0x701, 0x700, 0x710, 0x720, 0x730, 0x740, 0x750, 0x760,
    0x770, 0x670, 0x570, 0x470, 0x370, 0x270, 0x170, 0x070, 0x071, 0x072, 0x073, 0x074, 0x075, 0x076, 0x077, 0x067,
    0x057, 0x047, 0x037, 0x027, 0x017, 0x007, 0x107, 0x207, 0x307, 0x407, 0x507, 0x607, 0x707, 0x706, 0x705, 0x704,
    0x703, 0x702, 0x701, 0x700, 0x710, 0x720, 0x730, 0x740, 0x750, 0x760, 0x770, 0x670, 0x570, 0x470, 0x370, 0x270,
    0x170, 0x070, 0x071, 0x072, 0x073, 0x074, 0x075, 0x076, 0x077, 0x067, 0x057, 0x047, 0x037, 0x027, 0x017, 0x007,
    0x107, 0x207, 0x307, 0x407, 0x507, 0x607, 0x707, 0x706, 0x705, 0x704, 0x703, 0x702, 0x701, 0x700, 0x710, 0x720,
];
const T1 = [0x770, 0x771, 0x772, 0x773, 0x774, 0x775, 0x776, 0x777, 0x777, 0x677, 0x577, 0x477, 0x377, 0x277, 0x177, 0x077,
    0x077, 0x176, 0x275, 0x374, 0x473, 0x572, 0x671, 0x770];
const T2 = [0x700, 0x710, 0x610, 0x620, 0x520, 0x530, 0x430, 0x440, 0x340, 0x350, 0x250, 0x260, 0x160, 0x170, 0x070, 0x070];
// SpongeBob's registers 2..15, the 14 words at depacked.bin 0x5fe0 (the Timer-B swap at $93ac)
const SBOB_PAL = [0x774, 0x553, 0x332, 0x321, 0x210, 0x666, 0x777, 0x755, 0x701, 0x622, 0x356, 0x377, 0x555, 0x000];
// machine/beam.zig stToRgba: gun = ((n & 7) << 1 | n >> 3 & 1) * 16, ABGR in a u32.
const gun = (n) => ((((n & 7) << 1) | ((n >> 3) & 1)) * 16);
const st = (w) => (0xFF000000 | (gun(w) << 16) | (gun(w >> 4) << 8) | gun(w >> 8)) >>> 0;

const PW = 400, PH = 280, PFB_W = 800;

// ---------------- the model -----------------------------------------------
const M = { frame: 0, rot: 0, first: 0, pos: 0, ptr: 0, col: 0, row: 0, pause: 0 };
const plane = new Uint8Array(PW * PH);
const fill = (x, y, w, h, v) => {
    for (let yy = Math.max(y, 0); yy < Math.min(y + h, PH); yy++)
        for (let xx = Math.max(x, 0); xx < Math.min(x + w, PW); xx++) plane[yy * PW + xx] = v;
};
const glyph = (ch, x, y, k, ink, clipY0 = 0, clipY1 = PH) => {
    for (let py = 0; py < 8; py++)
        for (let px = 0; px < 8; px++) {
            if (!font[ch * 64 + py * 8 + px]) continue;
            for (let dy = 0; dy < k; dy++) {
                const yy = y + py * k + dy;
                if (yy < clipY0 || yy >= clipY1) continue;
                for (let dx = 0; dx < k; dx++) {
                    const xx = x + px * k + dx;
                    if (xx >= 0 && xx < PW) plane[yy * PW + xx] = ink;
                }
            }
        }
};
// init: sprite (colour 0 transparent, 1 -> the T2 entry, 2..15 -> 18..31), the three boxes, the rimmed logo
for (let y = 0; y < 158; y++) for (let x = 0; x < 144; x++) {
    const v = sbob[y * 144 + x];
    if (v) plane[(84 + y) * PW + 248 + x] = v === 1 ? 1 : 16 + v;
}
for (const bx of [26, 80, 134]) fill(bx, 44, 40, 26, 1);
const LOGO = "THE GNOMES GROUP";
for (let i = 0; i < LOGO.length; i++) {
    const c = LOGO.charCodeAt(i);
    if (c === 32) continue;
    const x = 8 + i * 24;
    for (const [dx, dy] of [[-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1]]) glyph(c, x + dx, 12 + dy, 3, 3);
    glyph(c, x, 12, 3, 2);
}

function step() {
    M.frame++;
    M.rot = (M.rot + 1) % 128;
    M.pos += 2;
    if (M.pos >= 40) { M.pos -= 40; M.first = (M.first + 1) % BIG.length; }
    // band: rows 244..275 cleared and redrawn
    fill(0, 244, PW, 32, 0);
    for (let i = 0; i < 11; i++) glyph(BIG.charCodeAt((M.first + i) % BIG.length), i * 40 - M.pos, 244, 4, 1, 244, 276);
    // the TTY, one action a frame
    if (M.pause > 0) {
        if (--M.pause === 0) { M.col = 0; M.row = 0; M.ptr = 0; fill(0, 80, 176, 112, 0); }
        return;
    }
    const ch = CYAN.charCodeAt(M.ptr++);
    if (ch === 13) M.col = 0;
    else if (ch === 10) M.row = Math.min(M.row + 1, 13);
    else {
        for (let py = 0; py < 8; py++)
            for (let px = 0; px < 8; px++)
                if (font[ch * 64 + py * 8 + px]) plane[(80 + M.row * 8 + py) * PW + M.col * 8 + px] = 4;
        if (++M.col >= 22) { M.col = 0; M.row = Math.min(M.row + 1, 13); }
    }
    if (M.ptr >= CYAN.length) M.pause = TTY_PAUSE;
}

const STATIC = new Map([[3, st(0x760)], [4, st(T1[15])], ...SBOB_PAL.map((w, i) => [18 + i, st(w)])]);
function expected(shift) {
    const out = new Uint32Array(PFB_W * PH);
    for (let y = 0; y < PH; y++) {
        const pal = [st(RAINBOW[(y + M.rot + shift) % 128]), st(T2[y % 16]), st(T1[(y + PH - 12) % 24])];
        for (let x = 0; x < PFB_W; x++) {
            const i = plane[y * PW + (x >> 1)];
            out[y * PFB_W + x] = i < 3 ? pal[i] : STATIC.get(i);
        }
    }
    return out;
}

const pfb = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), PFB_W * PH);
const hx = (v) => "0x" + (v >>> 0).toString(16).padStart(8, "0");
function compare(frame) {
    const want = expected(broke === "raster" ? 1 : 0);
    if (broke === "pixels" && frame === 50) want[(260 * PFB_W) + 401] ^= 0x10;
    for (let i = 0; i < want.length; i++)
        if (pfb[i] !== want[i]) return `frame ${frame}: physical (${i % PFB_W},${(i / PFB_W) | 0}) is ${hx(pfb[i])} not ${hx(want[i])}`;
    return null;
}
function checkState(frame) {
    const got = [0, 1, 2, 3, 4, 5, 6, 7].map((f) => demo.gnState(f));
    const want = [M.frame, M.rot, M.first, M.pos, M.ptr, M.col, M.row, M.pause];
    if (broke === "state" && frame === 7) want[4]++;
    for (let f = 0; f < 8; f++) if (got[f] !== want[f]) return `state frame ${frame}: word ${f} is ${got[f]}, model ${want[f]}`;
    return null;
}
function ppm(px) {
    const body = Buffer.alloc(PFB_W * PH * 3);
    for (let i = 0; i < px.length; i++) { body[3 * i] = px[i] & 255; body[3 * i + 1] = (px[i] >> 8) & 255; body[3 * i + 2] = (px[i] >> 16) & 255; }
    return Buffer.concat([Buffer.from(`P6\n${PFB_W} ${PH}\n255\n`), body]);
}
const songName = () => new TextDecoder().decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));

// ---------------- 1. music at start -----------------------------------------
{
    const pending = demo.pollSongRequest();
    const want = broke === "music" ? "tgg_custodian.sndh" : "custodian.sndh";
    ok(pending === 1 && songName() === want && demo.songTune() === 1,
        pending === 1 ? `music: asked for ${songName()} #${demo.songTune()} (want ${want} #1)` : "music: no song requested at start");
}
ok(demo.gnBigTextLen() === BIG.length && demo.gnCyanTextLen() === CYAN.length && BIG.length === 2885 && CYAN.length === 187,
    `text: the big scroller is ${demo.gnBigTextLen()} chars and the TTY message ${demo.gnCyanTextLen()} (2885 / 187 in the original)`);

{
    // The first rip lost every other 16-px column of SpongeBob (a planar
    // decode slip): the body rows must have ink in every one of the 9 groups.
    let groups = 0;
    for (let g = 0; g < 9; g++) {
        let ink = 0;
        for (let y = 20; y < 120; y++) for (let x = 0; x < 16; x++) if (sbob[y * 144 + g * 16 + x]) ink++;
        if (ink > 0) groups++;
    }
    const body = sbob.filter((v) => v === 2).length;
    ok(groups === 9 && body > 3000, `sprite: SpongeBob's body rows have ink in ${groups}/9 16-px groups, ${body} pixels of colour 2 ($774, his yellow)`);
}

// ---------------- 2. state + pixels -----------------------------------------
const EVERY = 900;
const CHECK = [1200, 1500, 2000, 3000, 4000];
let compared = 0, failure = null, borderColours = 0, neighboursDiffer = true, bandMoved = 0;
let prevBand = null;
for (let frame = 1; frame <= CHECK[CHECK.length - 1] && !failure; frame++) {
    machine.hwClear();
    step();
    demo.frame(TICK_MS);
    failure = checkState(frame);
    if (failure || !(frame <= EVERY || CHECK.includes(frame))) continue;
    machine.hwRenderPlane(0);
    failure = compare(frame);
    compared++;
    const band = pfb.slice(244 * PFB_W, 276 * PFB_W).join(",");
    if (prevBand !== null && band !== prevBand) bandMoved++;
    prevBand = band;
    if (frame === 300) {
        for (const x of [0, PFB_W - 1]) {
            const col = new Set();
            for (let y = 0; y < PH; y++) {
                col.add(pfb[y * PFB_W + x]);
                if (y > 0 && pfb[y * PFB_W + x] === pfb[(y - 1) * PFB_W + x] && plane[y * PW + (x >> 1)] === 0 && plane[(y - 1) * PW + (x >> 1)] === 0) neighboursDiffer = false;
            }
            borderColours = Math.max(borderColours, col.size);
        }
    }
    if ([1, 100, 300, 600, EVERY].includes(frame)) await writeFile(`${OUT}/frame_${String(frame).padStart(6, "0")}.ppm`, ppm(pfb));
}
if (failure) errors.push(failure);
else {
    ok(compared === EVERY + CHECK.length, `${compared} frames equal the model pixel for pixel (every frame to ${EVERY}: two TTY cycles with their wipes; then ${CHECK.join("/")})`);
    ok(borderColours >= 40 && neighboursDiffer, `raster: a border column carries ${borderColours} colours over 280 lines, every line a different one (real per-line writes, borders open)`);
    ok(bandMoved >= EVERY - 1, `scroller: the band changed on ${bandMoved} compared frames`);
    ok(machine.hwRamAllocFailures() === 0, "no zg.mem allocation refused");

    // ---------------- 3. keys -----------------------------------------------
    const tunes = [];
    for (let n = 0; n < 6; n++) {
        demo.key(0xE001 + n);
        demo.frame(TICK_MS);
        tunes.push(demo.pollSongRequest() === 1 && songName() === "custodian.sndh" ? demo.songTune() : -1);
    }
    ok(tunes.join() === "1,2,3,4,5,6", `keys: F1-F6 request custodian.sndh #${tunes.join(", #")}`);
    ok(demo.pollCartRequest() === 0, "keys: the F keys do not leave");
    demo.key(0xE012);
    demo.frame(TICK_MS);
    ok(demo.pollCartRequest() === -1, "keys: Escape hands the screen back (pollCartRequest -1)");
    await startCart();
    demo.input(6);
    demo.frame(TICK_MS);
    ok(demo.pollCartRequest() === -1, "keys: Back hands the screen back (pollCartRequest -1)");
}

if (broke) {
    console.log(errors.length ? `gnomes: PASS (--break ${broke} caught: ${errors[0]})` : `gnomes: FAILED -- --break ${broke} was not caught`);
    process.exit(errors.length ? 0 : 1);
}
console.log(errors.length ? `gnomes: FAILED -- ${errors.join("; ")}` : "gnomes: all pass");
process.exit(errors.length ? 1 : 0);
