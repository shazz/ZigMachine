// Headless BUBBLE BOBBLE driver (cart 97): the Atari ST game (Firebird 1987),
// BUBBLE.PRG's 68000 code translated to Zig (apps/zig/scenes/bubblebobble/gen,
// tools/bubblebobble/st_recomp.py) on a model of the ST it ran on (st/).
//
//   rounds   all 100 rounds' playfield grids, as the GAME builds them ($1092 +
//            $10EA into $2854: blocks, the walls, the air currents with their
//            rectangles and mirrors), equal the grids an independent decoder of
//            BDATA.DAT + AIRFLOW.DAT (below, from the format in
//            prototypes/bubble_re/ANALYSIS.md) makes; and the enemy lists parse
//   play     power-on runs as on the ST: the title picture, the hi-score table
//            with its Timer B rasters, the story; '1' starts round 1 with Bub
//            and its three Zen-Chans dropping in; the joystick walks Bub, fire
//            blows a bubble (and its effect); no jump into an unknown address,
//            no unmodelled hardware access, no unanswered TOS call, no stuck
//            interrupt over a 20,000-frame soak of the attract mode and play;
//            two runs of the same script end in the same RAM
//   sound    bubble_bobble_st.sndh on the sealed audio machine: each of the 9
//            tunes and the 6 effects, started as the game starts them, leaves
//            the SNDH's driver RAM equal to the cart's own copy, tick for tick
//   live     the host path: the plane IS the ST screen (palette indices pixel
//            for pixel), '1' starts, 50 Hz ST frames on a 60 Hz host, Z toggles
//            the ZIG mode (a 24-bit copper sky on colour 0, the pixels the same),
//            Escape quits a game and leaves from the title; the second pad (input2) is
//            Bob's joystick, fire included, and leaves Bub's alone
//
//   node apps/harness/bubblebobble_headless.mjs [outdir] [--break rounds|soak|sound|plane]
//   --break rounds  the decoder drops the airflow mirror: the rounds check fails
//   --break soak    a byte of the program's data is corrupted: the soak sees a stuck run
//   --break sound   the SNDH plays the next tune: the driver RAM check fails
//   --break plane   the plane check compares against the other screen: it fails
//   --break pad2    the second pad drives Bub instead of Bob: the live check fails
//   --break beam    the picture is the screen as the frame leaves it: the drop-in check fails
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../../docs/wasm_hiwater.js";

const PAGES = 128; // SHARED_PAGES in machine/sdk/memmap.zig
const CART = "docs/demo-bubblebobble.wasm";
const MUSIC = "bubble_bobble_st.sndh";
const RESIDENT = 0x8000;
const ASSETS = "apps/zig/assets/screens/bubblebobble";
const BASE = 0x10000; // st_prg.BASE: where TEXT is loaded
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
const BREAKS = ["rounds", "soak", "sound", "plane", "beam", "pad2"];
if (bi > 0 && !BREAKS.includes(broke)) { console.error(`--break ${BREAKS.join("|")}`); process.exit(2); }
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/bubblebobble";
const dec = new TextDecoder();

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(CART);
    const env = { ...env0, ...rom };
    for (const n of Object.keys(machine)) if (n.startsWith("hwRam") || n.startsWith("hwRomRam")) env[n] = machine[n];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const ram = (ctx) => new Uint8Array(ctx.memory.buffer, ctx.demo.bbTestMem(), 0x100000);
const stat = (ctx, i) => ctx.demo.bbTestStat(i) >>> 0;
const STAT = { bad: 0, lastBad: 1, dropped: 2, tos: 3, stuck: 4, tunes: 8, effects: 9, lastTune: 10, lastFx: 11 };

// ------------------------------------------------------------- the rounds
// BDATA.DAT: 100 maps of 25 rows x 4 bytes (bit 31 = column 0); a row's bits 1-0 are
// its air current. AIRFLOW.DAT from $12C: one record a round (bit 7: "as round n";
// 0: none; else its length, then 1-byte "mirror the left half" entries and 3-byte
// rectangles: dir<<6 | x, y<<3 | w-1 (high bits), (w-1 low 2 bits)<<6 | h-1).
function decodeRound(bdata, air, r) {
    const grid = new Uint8Array(32 * 25);
    for (let y = 0; y < 25; y++) {
        const row = (bdata[r * 100 + y * 4] << 24 | bdata[r * 100 + y * 4 + 1] << 16 |
            bdata[r * 100 + y * 4 + 2] << 8 | bdata[r * 100 + y * 4 + 3]) >>> 0;
        for (let x = 0; x < 32; x++) grid[y * 32 + x] = (row >>> (31 - x)) & 1;
    }
    const walk = (n) => {
        let p = 0x12c;
        for (let i = 0; i < n; i++) {
            const b = air[p];
            p += (b & 0x80) || b === 0 ? 1 : b & 0x7f;
        }
        return p;
    };
    let p = walk(r), mapOf = r;
    if (air[p] & 0x80) { mapOf = air[p] & 0x7f; p = walk(mapOf); }
    for (let y = 0; y < 25; y++) {
        const dir = (bdata[mapOf * 100 + y * 4 + 3] & 3) << 6;
        for (let x = 0; x < 32; x++) grid[y * 32 + x] |= dir;
    }
    if (air[p] !== 0) {
        const start = p, len = air[p++];
        while (p - start < len) {
            const b0 = air[p];
            if (!(b0 & 0x80)) {
                if (broke !== "rounds") mirror(grid);
                p += 1;
                continue;
            }
            const b1 = air[p + 1], b2 = air[p + 2];
            const dir = (b0 << 1) & 0xc0, x = b0 & 0x1f, y = b1 >> 3;
            const w = ((b1 << 2) | (b2 >> 6)) & 0x1f, h = b2 & 0x1f;
            for (let j = 0; j <= h; j++) for (let i = 0; i <= w; i++) {
                const c = (y + j) * 32 + x + i;
                if (c < grid.length) grid[c] = (grid[c] & 3) | dir;
            }
            p += 3;
        }
    }
    for (let y = 0; y < 25; y++) for (const x of [0, 1, 30, 31]) grid[y * 32 + x] = 1;
    if (r === 0x62) for (let y = 0; y < 3; y++) for (let x = 10; x < 14; x++) grid[y * 32 + x] = 0x80; // round 99 ($1180)
    return grid;
}

function mirror(grid) { // $129A: the left half's currents, reflected into the right half (24 rows)
    for (let y = 0; y < 24; y++) for (let i = 0; i < 16; i++) {
        let d = grid[y * 32 + 15 - i] & 0xc0;
        if (d === 0xc0) d = 0x40; else if (d === 0x40) d = 0xc0;
        grid[y * 32 + 16 + i] = (grid[y * 32 + 16 + i] & 3) | d;
    }
}

// The start-up's fixes to the map data after loading it ($A2-$136): 14 to BDATA.DAT (one
// round's floor, three rows moved up a row...), 4 to AIRFLOW.DAT's first table.
function startupFixes(bdata, air) {
    const B = (a) => a - 0x25080, A = (a) => a - 0x20876;
    bdata[B(0x25403)] = 0xfc;
    bdata[B(0x27865)] |= 1 << 2;
    bdata[B(0x255fb)] = 0xfe;
    bdata.copyWithin(B(0x257b0), B(0x257b4), B(0x257b8));
    bdata.copyWithin(B(0x257b4), B(0x257b8), B(0x257bc));
    bdata.copyWithin(B(0x257b8), B(0x257bc), B(0x257c0));
    bdata[B(0x259fc)] = 0xd5;
    air[A(0x208c6)] = 0x32;
    air[A(0x2092a)] = 0xec;
    air[A(0x2098e)] = 0xb0;
    air[A(0x20995)] &= ~1;
    bdata[B(0x2753b)] = 0xfe;
    bdata[B(0x27e84)] = (bdata[B(0x27e84)] & 7) | 0x50;
    bdata[B(0x276fc)] &= ~1;
    bdata[B(0x27704)] |= 1;
    bdata[B(0x276ff)] &= ~0x80;
    bdata[B(0x27707)] |= 0x80;
}

// BDATA.DAT from 10,000: each round's enemies, 3 bytes each, 0-terminated.
function enemyLists(bdata) {
    const lists = [];
    let p = 10000;
    for (let r = 0; r < 100; r++) {
        const l = [];
        while (bdata[p] !== 0) { l.push({ type: bdata[p] & 7, col: bdata[p] >> 3, row: bdata[p + 1] >> 3 }); p += 3; }
        lists.push(l);
        p++;
    }
    return { lists, end: p };
}

async function rounds(ctx) {
    const errors = [];
    const bdata = new Uint8Array(await readFile(`${ASSETS}/bdata.dat`));
    const air = new Uint8Array(await readFile(`${ASSETS}/airflow.dat`));
    startupFixes(bdata, air);
    ctx.demo.bbTestPowerOn();
    ctx.demo.bbTestFrames(150); // the game's start-up loads GRAPHICS\*.* while the title shows
    const m = ram(ctx);
    for (const [name, file, at] of [["BDATA.DAT", bdata, 0x25080], ["AIRFLOW.DAT", air, 0x20876]]) {
        let diff = 0;
        for (let i = 0; i < file.length; i++) if (m[at + i] !== file[i]) diff++;
        if (diff) errors.push(`${name} in RAM differs from the file + the start-up fixes in ${diff} bytes`);
    }
    let blocks = 0, currents = 0;
    for (let r = 0; r < 100; r++) {
        m[BASE + 0x540] = 0; m[BASE + 0x541] = 0; m[BASE + 0x542] = 0; m[BASE + 0x543] = r;
        ctx.demo.bbTestCall(0x1092, 0);
        ctx.demo.bbTestCall(0x10ea, 0);
        const game = ram(ctx).subarray(BASE + 0x2854, BASE + 0x2854 + 32 * 25);
        const want = decodeRound(bdata, air, r);
        for (let c = 0; c < want.length; c++) {
            if (game[c] !== want[c]) { errors.push(`round ${r + 1}: cell (${c % 32},${c >> 5}) game $${game[c].toString(16)} decoder $${want[c].toString(16)}`); break; }
            blocks += game[c] & 1; currents += game[c] >> 6 ? 1 : 0;
        }
        if (errors.length > 3) break;
    }
    const { lists, end } = enemyLists(bdata);
    const n = lists.reduce((a, l) => a + l.length, 0);
    if (end > 0x2e38) errors.push(`the enemy lists run to ${end}, past the extra maps at $2E38`);
    if (lists[0].length !== 3 || lists[0].some((e) => e.type !== 0)) errors.push(`round 1 is not three Zen-Chans: ${JSON.stringify(lists[0])}`);
    console.log(`  rounds: 100 playfields built by the game = the decoder's (${blocks} block cells, ${currents} air cells); ` +
        `${n} enemies in 100 lists (round 1: ${lists[0].length}, round 100: ${lists[99].length})`);
    return errors;
}

// ------------------------------------------------------------- play
function crc32(buf) {
    let c = ~0;
    for (let i = 0; i < buf.length; i++) { c ^= buf[i]; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); }
    return ~c >>> 0;
}

/// The picture as palette indices (320 x 200): what the beam showed last frame (bbTestBeam),
/// or, given a base, an ST screen in RAM.
function stIndices(ctx, base) {
    const m = base === undefined ? new Uint8Array(ctx.memory.buffer, ctx.demo.bbTestBeam(), 32000) : ram(ctx);
    const at = base === undefined ? 0 : base, out = new Uint8Array(320 * 200);
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const g = at + y * 160 + (x >> 4) * 8, b = 15 - (x & 15);
        let c = 0;
        for (let p = 0; p < 4; p++) c |= (((m[g + 2 * p] << 8 | m[g + 2 * p + 1]) >> b) & 1) << p;
        out[y * 320 + x] = c;
    }
    return out;
}

function png(path, w, h, rgb) {
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
    const chunk = (t, d) => {
        const b = Buffer.alloc(12 + d.length);
        b.writeUInt32BE(d.length, 0); b.write(t, 4); d.copy(b, 8);
        b.writeUInt32BE(crc32(b.subarray(4, 8 + d.length)), 8 + d.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
    return writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
        chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}

/// The shown screen with its per-line palette (the rasters), as RGB.
function shot(ctx) {
    const idx = stIndices(ctx);
    const pal = Array.from(new Uint16Array(ctx.memory.buffer, ctx.demo.bbTestPalette(), 16));
    const n = ctx.demo.bbTestRasterCount();
    const rw = new Uint8Array(ctx.memory.buffer, ctx.demo.bbTestRasters(), n * 4);
    const rgb = Buffer.alloc(320 * 200 * 3);
    let ri = 0;
    for (let y = 0; y < 200; y++) {
        while (ri < n && rw[ri * 4] < y) { pal[rw[ri * 4 + 1]] = rw[ri * 4 + 2] | rw[ri * 4 + 3] << 8; ri++; }
        for (let x = 0; x < 320; x++) {
            const c = pal[idx[y * 320 + x]], o = (y * 320 + x) * 3;
            rgb[o] = ((c >> 8) & 7) * 255 / 7; rgb[o + 1] = ((c >> 4) & 7) * 255 / 7; rgb[o + 2] = (c & 7) * 255 / 7;
        }
    }
    return rgb;
}

const OBJ = 0x20e80, OBJ_SIZE = 0x23e; // the object table ($96F0): Bub first
const word = (m, a) => (m[a] << 8 | m[a + 1]) << 16 >> 16;

// The round's entry: Bub in his bubble drifts down to his spot under "ROUND 01 / READY !".
// The game draws both straight into the SHOWN screen after its frame wait and erases them
// before the next, so they exist only while the beam passes (st/io.zig beam). Every frame of
// the drop: the text's box is lit, the bubble is a whole bubble (>= 120 lit pixels: an arc
// is ~15), and over the drop the bubble moves down. --break beam shows the screen as the frame
// leaves it, which is what drew only an arc and no text on the board (21 Nov).
const TEXT_BOX = [88, 86, 168, 110]; // x0, y0, x1, y1 of "ROUND 01 / READY !" (round 1)
async function dropIn(ctx) {
    const errors = [];
    // lit = not black on screen (the picture's RGB, through the palette and its rasters)
    const lit = (rgb, [x0, y0, x1, y1]) => {
        let n = 0;
        for (let y = Math.max(0, y0); y < Math.min(200, y1); y++) for (let x = x0; x < x1; x++) {
            const o = (y * 320 + x) * 3;
            if (rgb[o] | rgb[o + 1] | rgb[o + 2]) n++;
        }
        return n;
    };
    // Bub's bubble, where his object says it is (+8: the screen offset of its 16 lines, 32 pixels)
    const bubBox = () => {
        const m = ram(ctx), off = (m[OBJ + 8] << 24 | m[OBJ + 9] << 16 | m[OBJ + 10] << 8 | m[OBJ + 11]) | 0;
        const line = Math.floor(off / 160), x = ((off - line * 160) >> 3) * 16;
        return [x, line, x + 32, line + 16];
    };
    let frames = 0, textFrames = 0, bubbleFrames = 0, worst = 1e9;
    const y0 = bubBox()[1];
    for (let i = 0; i < 60; i++) {
        ctx.demo.bbTestFrames(1);
        const rgb = shot(ctx), box = bubBox();
        frames++;
        if (lit(rgb, TEXT_BOX) > 150) textFrames++;
        if (box[1] >= 0) { // (it starts above the picture)
            const n = lit(rgb, box);
            if (n >= 100) bubbleFrames++; else worst = Math.min(worst, n);
        } else bubbleFrames++;
        if (i === 30) await png(`${outdir}/03b_dropin.png`, 320, 200, rgb);
    }
    const y1 = bubBox()[1];
    if (textFrames < frames) errors.push(`drop-in: "ROUND 01 READY !" lit on ${textFrames} of ${frames} frames`);
    if (bubbleFrames < frames) errors.push(`drop-in: Bub's bubble whole on ${bubbleFrames} of ${frames} frames (fewest lit pixels ${worst})`);
    if (!(y1 > y0 + 5)) errors.push(`drop-in: the bubble did not drift down (line ${y0} -> ${y1})`);
    dropInfo = `${frames} frames: the text on ${textFrames}, a whole bubble on ${bubbleFrames}, line ${y0} -> ${y1}`;
    return errors;
}
let dropInfo = "";

async function play(ctx) {
    const errors = [];
    const d = ctx.demo;
    const health = (what) => {
        for (const k of ["bad", "dropped", "tos", "stuck"]) if (stat(ctx, STAT[k])) errors.push(`${what}: ${k} = ${stat(ctx, STAT[k])} (last bad pc $${stat(ctx, STAT.lastBad).toString(16)}, last dropped $${stat(ctx, 12).toString(16)})`);
    };
    d.bbTestPowerOn();
    d.bbTestFrames(50);
    const title = stIndices(ctx);
    const titleInk = title.reduce((a, v) => a + (v ? 1 : 0), 0);
    if (titleInk < 20000) errors.push(`frame 50: the title picture (SPIC.PI1) is not up (${titleInk} lit pixels)`);
    await png(`${outdir}/01_title.png`, 320, 200, shot(ctx));
    d.bbTestFrames(150);
    await png(`${outdir}/02_hiscores.png`, 320, 200, shot(ctx));
    d.bbTestFrames(60);
    d.bbTestType(0x31); // '1'
    d.bbTestFrames(240);
    await png(`${outdir}/03_story.png`, 320, 200, shot(ctx));
    d.bbTestFrames(400);
    const m = ram(ctx);
    if (m[BASE + 0x598] === 0) errors.push("'1' did not start a game (Bub's lives $598 = 0)");
    let f = 0;
    if (broke === "beam") d.bbTestBeamAtEnd(1);
    while (ram(ctx)[BASE + 0x573] === 0 && f < 2000) { d.bbTestFrames(1); f++; } // $572: enemies in the round
    errors.push(...await dropIn(ctx));
    if (ram(ctx)[BASE + 0x573] !== 3) errors.push(`round 1 has ${ram(ctx)[BASE + 0x573]} enemies, not its three Zen-Chans`);
    d.bbTestFrames(150); // they drop in, Bub is set down
    await png(`${outdir}/04_round1.png`, 320, 200, shot(ctx));
    // Bub (object 0, $20E80): the stick right walks him right (+0: x in 8-pixel columns)
    const bx0 = word(ram(ctx), OBJ);
    d.bbTestJoy(1, 8); d.bbTestFrames(25); d.bbTestJoy(1, 0); d.bbTestFrames(2);
    const bx1 = word(ram(ctx), OBJ);
    if (!(bx1 > bx0)) errors.push(`the stick right did not walk Bub right (x ${bx0} -> ${bx1})`);
    // fire blows a bubble: a type-11 object ($11: the type)
    const bubbles = () => Array.from({ length: 27 }, (_, o) => ram(ctx)[OBJ + o * OBJ_SIZE + 0x11]).filter((t) => t === 11).length;
    const b0 = bubbles();
    d.bbTestJoy(1, 0x80); d.bbTestFrames(3); d.bbTestJoy(1, 0); d.bbTestFrames(3);
    const b1 = bubbles();
    if (!(b1 > b0)) errors.push(`fire blew no bubble (${b0} -> ${b1} bubble objects)`);
    await png(`${outdir}/05_bubble.png`, 320, 200, shot(ctx));
    // up jumps (+3: y in 8-pixel rows) with its effect (5, $3A7E)
    const fx0 = stat(ctx, STAT.effects), by0 = ram(ctx)[OBJ + 3];
    d.bbTestJoy(1, 1); d.bbTestFrames(8);
    const by1 = ram(ctx)[OBJ + 3];
    d.bbTestJoy(1, 0); d.bbTestFrames(40);
    if (!(by1 < by0)) errors.push(`up did not jump (y ${by0} -> ${by1})`);
    if (stat(ctx, STAT.effects) === fx0) errors.push("the jump requested no effect");
    if (stat(ctx, STAT.tunes) < 2) errors.push(`only ${stat(ctx, STAT.tunes)} tunes requested by round 1`);
    // the round won ($572, the enemies left, to 0): the end of the round, then the scroll to
    // round 2 ($2D96: VBL $FA4 + Timer B $F74 change colours 11-14 and 2 at a split line that
    // climbs 4 lines a frame, the old round scrolling up under it): real rasters
    const l32 = (a) => (ram(ctx)[a] << 24 | ram(ctx)[a + 1] << 16 | ram(ctx)[a + 2] << 8 | ram(ctx)[a + 3]) >>> 0;
    ram(ctx)[BASE + 0x572] = 0; ram(ctx)[BASE + 0x573] = 0;
    let wait = 0;
    while (l32(0x70) !== BASE + 0xfa4 && wait < 2000) { d.bbTestFrames(1); wait++; }
    let rasterFrames = 0, writes = 0;
    for (let i = 0; i < 25; i++) { d.bbTestFrames(1); if (d.bbTestRasterCount()) rasterFrames++; writes += d.bbTestRasterCount(); }
    await png(`${outdir}/06_scroll.png`, 320, 200, shot(ctx));
    if (l32(0x70) !== BASE + 0xfa4) errors.push(`no scroll to round 2 within ${wait} frames of the round won`);
    if (rasterFrames < 20) errors.push(`the scroll to round 2 changed colours mid-picture on ${rasterFrames} of 25 frames`);
    while (ram(ctx)[BASE + 0x543] !== 1 || l32(0x70) !== BASE + 0xeb0) { d.bbTestFrames(1); if (++wait > 3000) break; }
    d.bbTestFrames(200);
    await png(`${outdir}/07_round2.png`, 320, 200, shot(ctx));
    if (ram(ctx)[BASE + 0x543] !== 1) errors.push("round 2 did not follow");
    health("play");
    console.log(`  play: title (${titleInk} px), hi-scores, story, '1' -> the drop-in (${dropInfo}) -> round 1 with ` +
        `three Zen-Chans, Bub walks ${bx0} -> ${bx1}, fire blows a bubble (${b0} -> ${b1}), up jumps (${by0} -> ${by1}) with effect 5; ` +
        `round won -> the scroll to round 2 (${rasterFrames} frames of rasters, ${writes} colour writes mid-picture) -> round 2`);
    return errors;
}

// A soak: the attract loop, then games played by a pseudo-random stick, 20,000 frames.
async function soak(ctx) {
    const errors = [];
    const run = () => {
        const d = ctx.demo;
        d.bbTestPowerOn();
        if (broke === "soak") ram(ctx)[BASE + 0x3d34 + 2] ^= 0x40; // a jump table entry off into data
        let seed = 12345;
        const rnd = () => (seed = (seed * 1103515245 + 12345) >>> 0) >>> 16;
        for (let f = 0; f < 20000; f += 10) {
            if (f % 2000 === 300) d.bbTestType(0x31);
            const r = rnd();
            d.bbTestJoy(1, [0, 4, 8, 1, 0x80, 0x84, 0x88, 0][r & 7]);
            d.bbTestFrames(10);
            if (stat(ctx, STAT.bad) || stat(ctx, STAT.stuck)) break;
        }
        return crc32(ram(ctx).subarray(0x10000, 0x100000));
    };
    const c1 = run();
    for (const k of ["bad", "dropped", "tos", "stuck"]) if (stat(ctx, STAT[k])) errors.push(`soak: ${k} = ${stat(ctx, STAT[k])} (last bad pc $${stat(ctx, STAT.lastBad).toString(16)}, last dropped $${stat(ctx, 12).toString(16)})`);
    const tunes = stat(ctx, STAT.tunes), fx = stat(ctx, STAT.effects);
    const c2 = errors.length ? c1 : run();
    if (c1 !== c2) errors.push(`two runs of the same 20,000-frame script differ (RAM CRC ${c1.toString(16)} / ${c2.toString(16)})`);
    console.log(`  soak: 20,000 frames x 2 (attract + random play), ${tunes} tunes and ${fx} effects requested, RAM CRC ${c1.toString(16)} both runs`);
    return errors;
}

// ------------------------------------------------------------- sound
async function audioMachine() {
    const memory = new WebAssembly.Memory({ initial: 48, maximum: 48 });
    const m = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(m)) if (n.startsWith("machine")) env[n] = m[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    return { memory, m, audio };
}

// The driver's state both copies must agree on: the tune table and its variables
// (TEXT $AB76-$AC0C) and the effect state ($AF70-$AF80). Its code is not in the cart's RAM.
const DRIVER = [[0x1ab76, 0x1ac0c], [0x1af70, 0x1af80]];

async function sound(ctx) {
    const bytes = new Uint8Array(await readFile(`docs/music/${MUSIC}`));
    const text = new Uint8Array(await readFile(`${ASSETS}/text.bin`));
    const errors = [];
    const d = ctx.demo;
    let ticks = 0, moving = 0;
    const cases = [];
    for (let t = 0; t < 9; t++) cases.push({ tune: t });
    for (let e = 1; e <= 6; e++) cases.push({ tune: 1, effect: e });
    for (const c of cases) {
        d.bbTestPowerOn();
        d.bbTestFrames(2); // MUSIC.DAT loaded and patched ($370C)
        const a = await audioMachine();
        a.audio.audioInit();
        new Uint8Array(a.memory.buffer, a.audio.audioSongPtr(), bytes.length).set(bytes);
        if (!a.audio.audioLoadSndh(bytes.length)) { errors.push("audioLoadSndh refused the image"); return errors; }
        const sub = c.tune + 1;
        a.audio.audioSndhPlay(broke === "sound" ? sub % 9 + 1 : sub);
        const cart = () => ram(ctx);
        // the game's start-up already ran its title tune on its copy: the driver's variables
        // back to the program's own values, as the SNDH's install copies them
        for (const [lo, hi] of DRIVER) cart().set(text.subarray(lo - BASE, hi - BASE), lo);
        cart()[0x1ac08] = 0; cart()[0x1ac06] = c.tune;
        d.bbTestCall(0xa7ae, 0);
        const ram68 = () => new Uint8Array(a.memory.buffer, a.audio.audioSongPtr(), 0x100000);
        let bad = null, prev = null;
        for (let t = 0; t < 200 && !bad; t++) {
            if (c.effect && t === 20) {
                if (!a.audio.audioSndhCall(RESIDENT | 0x100 | c.effect)) errors.push(`effect ${c.effect}: the call found no SNDH playing`);
                cart()[0x1ac10] = c.effect;
                d.bbTestCall(0xac12, 0);
            }
            a.audio.audioRender(882); // 20 ms: one 50 Hz play call
            d.bbTestCall(0xa810, 0); // the game's VBL tick ($EB4)
            ticks++;
            const s = ram68(), k = cart();
            const now = s.subarray(0x1ab76, 0x1af80).join();
            if (prev !== null && now !== prev) moving++;
            prev = now;
            for (const [lo, hi] of DRIVER) for (let p = lo; p < hi && !bad; p++)
                if (s[p] !== k[p]) bad = `tick ${t}: $${p.toString(16)} SNDH ${s[p]} cart ${k[p]}`;
        }
        if (bad) errors.push(`${c.effect ? `effect ${c.effect}` : `tune ${c.tune}`}: ${bad}`);
        if (a.audio.audioSndhStuckPc && a.audio.audioSndhStuckPc()) errors.push(`tune ${c.tune}: stuck at PC ${a.audio.audioSndhStuckPc()}`);
        if (errors.length > 3) break;
    }
    if (moving < 1000) errors.push(`the driver state changed on only ${moving} ticks: nothing is playing`);
    console.log(`  sound: 9 tunes + 6 effects, ${ticks} ticks (${moving} moving): the SNDH's driver RAM = the cart's, tick for tick`);
    return errors;
}

// ------------------------------------------------------------- live
async function live() {
    const ctx = await boot();
    const { demo, machine, memory } = ctx;
    const errors = [];
    const step = (n, ms) => { for (let i = 0; i < n; i++) { machine.hwClear(); demo.frame(ms); } };
    step(300, 20);
    const stride = demo.bbTestPlaneStride();
    if (!stride) { errors.push("the plane was never presented"); return errors; }
    const compare = () => {
        const want = broke === "plane" ? stIndices(ctx, demo.bbTestShown() ^ (0x78000 ^ 0x6e200)) : stIndices(ctx);
        const plane = new Uint8Array(memory.buffer, demo.bbTestPlanePtr(), stride * 200);
        let diff = 0;
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) if (plane[y * stride + x] !== want[y * 320 + x]) diff++;
        return diff;
    };
    const d1 = compare();
    if (d1) errors.push(`the plane differs from the ST screen in ${d1} pixels (title)`);
    // a 60 Hz host keeps the ST's 50 Hz: 10 s = ~500 frames
    const f0 = demo.bbTestStat(5) >>> 0;
    step(600, 1000 / 60);
    const cyc = ((demo.bbTestStat(5) >>> 0) - f0 + 2 ** 32) % 2 ** 32;
    const frames = Math.round(cyc / 160256);
    if (Math.abs(frames - 500) > 8) errors.push(`10 s at 60 Hz ran ${frames} ST frames, not ~500`);
    demo.key(0x31); step(1, 20); demo.keyUp(0x31);
    step(700, 20);
    if (ram(ctx)[BASE + 0x598] === 0) errors.push("'1' on the host did not start a game");
    const d2 = compare();
    if (d2) errors.push(`the plane differs from the ST screen in ${d2} pixels (round 1)`);
    demo.input(3); step(2, 20);
    if (ram(ctx)[BASE + 0x3ca3] !== 8) errors.push(`the right arrow did not set joystick 1 right ($3CA3 = ${ram(ctx)[BASE + 0x3ca3]})`);
    demo.inputRelease(3); step(2, 20);
    // Player 2 (R83): the second pad is Bob's joystick (port 0, $3CA2), fire included; Bub's stays put.
    const joy = (port) => ram(ctx)[BASE + 0x3ca2 + port];
    const pad2 = broke === "pad2" ? { down: (d) => demo.input(d), up: (d) => demo.inputRelease(d) } : { down: (d) => demo.input2(d), up: (d) => demo.inputRelease2(d) };
    if (!demo.input2 || !demo.inputRelease2) errors.push("the cart has no input2/inputRelease2 export");
    else {
        pad2.down(3); pad2.down(5); step(2, 20);
        if (joy(0) !== 0x88) errors.push(`pad 2 right+fire did not set Bob's joystick 0 ($3CA2 = ${joy(0)}, want 136)`);
        if (joy(1) !== 0) errors.push(`pad 2 moved Bub's joystick 1 ($3CA3 = ${joy(1)})`);
        demo.input(2); step(2, 20); // pad 1 at the same time: Bub only
        if (joy(1) !== 4 || joy(0) !== 0x88) errors.push(`pad 1 left with pad 2 held: $3CA3 = ${joy(1)} (want 4), $3CA2 = ${joy(0)} (want 136)`);
        demo.inputRelease(2); pad2.up(3); pad2.up(5); step(2, 20);
        if (joy(0) !== 0 || joy(1) !== 0) errors.push(`releasing both pads left a joystick held ($3CA2 = ${joy(0)}, $3CA3 = ${joy(1)})`);
    }
    // Z: the ZIG mode -- a sky on colour 0, a colour a line, and the picture itself unchanged
    demo.key(0x7a); demo.keyUp(0x7a); step(2, 20);
    const sky = [0, 100, 199].map((y) => demo.bbTestSky(y) >>> 0);
    if (!(sky[0] !== sky[1] && sky[1] !== sky[2] && (sky[0] & 0xffffff) !== 0)) errors.push(`ZIG mode: no sky (${sky.map((c) => c.toString(16))})`);
    if (compare()) errors.push("ZIG mode changed the picture's pixels");
    demo.key(0x7a); demo.keyUp(0x7a); step(2, 20);
    if (demo.bbTestSky(100) !== 0) errors.push("Z again did not leave the ZIG mode");
    demo.key(0xe012); step(10, 20); demo.keyUp(0xe012); // a key held 0.2 s
    step(600, 20);
    if (ram(ctx)[BASE + 0x58a] === 0) errors.push("Escape in a game did not quit to the title ($58A, the title loop's flag)");
    demo.key(0xe012); step(1, 20);
    if (demo.pollCartRequest() !== -1) errors.push("Escape on the title did not leave");
    if (machine.hwRamAllocFailures()) errors.push(`${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
    console.log(`  live: the plane = the ST screen pixel for pixel (title, round 1), ${frames} ST frames in 10 s at 60 Hz, ` +
        `'1' starts, the arrows are joystick 1, Z = the ZIG mode's sky and back, Escape quits the game, then leaves`);
    return errors;
}

await mkdir(outdir, { recursive: true });
const ctx = await boot();
console.log("boot ok");
let errors = [];
// A --break runs the one check it breaks.
const BREAK_CHECK = { rounds: "rounds", soak: "soak", sound: "sound", plane: "live", beam: "play", pad2: "live" };
const only = broke ? [BREAK_CHECK[broke]] : process.env.BB_ONLY ? process.env.BB_ONLY.split(",") : null;
for (const [name, fn] of [["rounds", rounds], ["play", play], ["soak", soak], ["sound", sound], ["live", live]]) {
    if (only && !only.includes(name)) continue;
    const e = name === "live" ? await fn() : await fn(ctx);
    for (const x of e) console.log(`  FAIL ${name}: ${x}`);
    errors = errors.concat(e);
}
if (broke) {
    if (errors.length === 0) { console.log(`=> FAIL: --break ${broke} was NOT caught`); process.exit(1); }
    console.log(`=> PASS ✅ --break ${broke} caught (${errors.length} failures)`);
    process.exit(0);
}
if (errors.length) { console.log(`=> FAIL (${errors.length})`); process.exit(1); }
console.log("=> PASS ✅ BUBBLE BOBBLE: the ST game's own code, data and sound");
process.exit(0);
