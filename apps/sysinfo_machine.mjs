// SYSINFO harness, the machine side (apps/sysinfo_check.mjs runs the checks):
// the sealed machine, the ROM and the cart over one memory as docs/sealed-loader.js
// wires them, its own disk in the drive, a host clock or none, and the ROM's
// drawing calls counted (a page that did not change must draw nothing).
//
// The page's text is read where the cart keeps it: its three 80 x 25 text grids
// (apps/zig/scenes/sysinfo/grid.zig: the page as composed, what the glass should
// show of it in the screen mode, what it shows), found by the program line every
// page has, each followed by its attributes (an extern struct). glassMismatches()
// then holds the glass to the shown grid, glyph by glyph, in the mode's geometry
// (apps/zig/scenes/sysinfo/view.zig): the system font for values (8 x 16, its rows
// doubled, in the desk), the ROM's small font for the program line, the prompt and
// the headings (screen.zig: a G_TEXT, its glyphs from the run's first cell).
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { parseDisk } from "../docs/zmdisk.js";

const PAGES = 128, BLOCK = 512, COLS = 80, ROWS = 25, CELL = 8, W = 640;
const TITLE = "SYSINFO FOR ZIGMACHINE, VERSION ";
const DRAWS = ["guiText", "guiTextAlign", "guiFill", "guiRect", "guiFrame", "guiBox", "guiButton", "guiPlot", "objcDraw"];
const ATTR = { plain: 0, under: 1, inverse: 2, small: 3 };
export const K = { F1: 0xe001, HELP: 0xe011, ESC: 0xe012 };

/// Boot SYSINFO. clock: "none" (hostMicros answers 0, as the gate's other carts get) or "host".
/// corrupt: a FAT file the DRIVE serves with one byte changed (the harness keeps the real image).
/// opts.board: hwAstro writes W_CYCLES as the board's wrapper does (the host reads as the board);
/// opts.pageJobs: hostBardJob as the page's loader answers it.
export async function boot(clock = "none", corrupt = null, opts = {}) {
    const disk = new Uint8Array(await readFile("docs/demo-sysinfo.zmd"));
    const served = disk.slice();
    if (corrupt) {
        const f = parseDisk(disk, "demo-sysinfo.zmd").mounted.files[corrupt];
        served[f.start + f.len - 1] ^= 0xff; // the last byte: past every header the cart checks
    }
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
    const s = { memory, machine, rom, demo: null, draws: 0, disk };
    const env = { memory, ...rom };
    for (const n of DRAWS) env[n] = (...a) => { s.draws++; return rom[n](...a); };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    env.hostMicros = clock === "host" ? () => (Math.floor(performance.now() * 1000) >>> 0) || 1 : () => 0;
    if (opts.board) { // the board's wrapper (fpga/cycles/bastro.c): W_CYCLES = the call's ZIGGY cycles.
        // A 100 MHz ZIGGY whose ARM round trip takes 1 ms: each call moves the host clock 1000 us on.
        const real = machine.hwAstro, clock = env.hostMicros;
        let lag = 0;
        env.hostMicros = () => (clock() + lag) >>> 0;
        env.hwAstro = (desc, count) => {
            const r = real(desc, count), u = new Uint32Array(memory.buffer);
            lag += 1000;
            for (let i = 0; i < count; i++) u[(desc >>> 2) + i * 20 + 9] = 100_000;
            return r;
        };
    }
    env.diskReadBlock = (block, dst) => {
        const src = served.subarray(block * BLOCK, block * BLOCK + BLOCK);
        new Uint8Array(memory.buffer, dst, src.length).set(src);
        return src.length;
    };
    if (opts.pageJobs) { // docs/sealed-loader.js hostBardJob: the page serves through the cart's bardJobServe
        let open = false;
        env.hostBardJob = (op, arg) => {
            if (op === 0) { open = !!arg && typeof demo.bardJobServe === "function"; return open ? 1 : 0; }
            if (!open) return 0;
            if (op === 3) { demo.bardJobServe(); return 1; }
            return op === 1 ? 1 : 0;
        };
    }
    const cartBytes = await readFile("docs/demo-sysinfo.wasm");
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = s.demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    rom.kosSetBoot(0, 1, 1, machine.hwRamFree()); // as the loader: a cold boot off drive A, a disk in
    demo.boot();
    demo.skipBoot();
    return s;
}

/// n frames as the host runs them: the cart's frame, then the machine's (REG_FRAME counts it).
export function frames(s, n = 1) {
    for (let i = 0; i < n; i++) {
        s.demo.frame(1000 / 60);
        s.machine.hwClear();
    }
}

/// The cart's text grids, each as 25 strings with `.at` (25 arrays of attributes).
export function grids(s) {
    const mem = new Uint8Array(s.memory.buffer, 0x100000, 0x200000);
    const key = new TextEncoder().encode(TITLE);
    const out = [];
    for (let i = mem.indexOf(key[0]); i >= 0; i = mem.indexOf(key[0], i + 1)) {
        if (!key.every((b, j) => mem[i + j] === b)) continue;
        const at = i - 1; // the line starts at column 1, after a blank cell
        if (mem[at] !== 0x20 || mem[i + key.length] < 0x30 || mem[i + key.length] > 0x39) continue;
        if (mem[at + ROWS * COLS + 1] !== ATTR.small) continue; // not a grid: the string literal
        const rows = Array.from({ length: ROWS }, (_, r) => String.fromCharCode(...mem.subarray(at + r * COLS, at + (r + 1) * COLS)));
        rows.at = Array.from({ length: ROWS }, (_, r) => Array.from(mem.subarray(at + ROWS * COLS + r * COLS, at + ROWS * COLS + (r + 1) * COLS)));
        out.push(rows);
    }
    return out;
}

const whole = (g) => g[0].includes("(AFTER HWAM");

/// The page as composed (80 columns, whatever the screen mode).
export function page(s) {
    const g = grids(s);
    if (g.length !== 3) throw new Error(`expected the cart's three text grids, found ${g.length}`);
    return g.find(whole);
}

/// What the glass shows: the shown grid (80 columns, or low res's 40 of a half).
export function shownRows(s) {
    const g = grids(s);
    return g.find((x) => !whole(x)) ?? g[0];
}

/// The screen mode on the glass, off the machine's registers: "low", "medium" or "desk".
export function mode(s) {
    const res = new Uint8Array(s.memory.buffer, s.machine.hwVideoBase(), 1)[0];
    return res === 3 ? "desk" : res === 2 ? "medium" : "low";
}

/// "LABEL : value" off a page, by label (first match), or null.
export function field(rows, label) {
    for (const r of rows) {
        for (const col of [0, 41]) {
            if (r.substr(col, 16).trimEnd() === label && r.substr(col + 16, 2) === ": ")
                return r.substr(col + 18, col === 0 ? 23 : 39).trimEnd();
        }
    }
    return null;
}

/// Plane 0's pixels: palette indices, `w` a row (640, or 320 in low res).
export function glass(s) {
    const base = s.machine.hwVideoBase(), dv = new DataView(s.memory.buffer);
    const off = dv.getUint32(base + 0x44, true); // REG_FB_BASE[0]
    const m = mode(s), w = m === "low" ? 320 : W;
    const px = new Uint8Array(s.memory.buffer, base + off, w * (m === "desk" ? 480 : 200));
    px.w = w;
    return px;
}

/// Where a row's cells are in each mode (view.zig): top pixel row and height.
const cellY = (m, r) => (m === "desk" ? 40 + 16 * r : 8 * r);
const cellH = (m) => (m === "desk" ? 16 : 8);

/// Cells of the shown grid the glass does not show (BLACK 0 on WHITE 1): a plain or inverse
/// cell in the 8x8 system font (each glyph row twice in the desk), a small-font run as the
/// ROM's 6x6 G_TEXT from its first cell (the rest of the run paper), a heading's rule under it.
export async function glassMismatches(s) {
    const font = new Uint8Array(await readFile("libs/zig/assets/fonts/system_font_atari_1bit.raw"));
    const small = new Uint8Array(await readFile("libs/zig/assets/fonts/system_font_atari_6x6.raw"));
    const rows = shownRows(s), px = glass(s), m = mode(s), w = px.w, cols = w / CELL, h = cellH(m);
    const bad = [];
    const at = (x, y) => px[y * w + x];
    for (let r = 0; r < ROWS; r++) {
        const y0 = cellY(m, r), a = rows.at[r];
        for (let c = 0; c < cols;) {
            if (a[c] === ATTR.small || a[c] === ATTR.under) {
                let e = c + 1;
                while (e < cols && a[e] === a[c]) e++;
                const gy = y0 + Math.floor((h - 6 + 1) / 2);
                for (let k = c; k < e; k++) {
                    let ok = true;
                    for (let y = y0; y < y0 + h && ok; y++) for (let x = 8 * k; x < 8 * k + 8 && ok; x++) {
                        const i = Math.floor((x - 8 * c) / 6), gx = (x - 8 * c) % 6, ch = rows[r].charCodeAt(c + i);
                        let ink = a[c] === ATTR.under && y === y0 + h - 1;
                        if (!ink && i < e - c && y >= gy && y < gy + 6) ink = small[ch * 36 + (y - gy) * 6 + gx] !== 0;
                        ok = at(x, y) === (ink ? 0 : 1);
                    }
                    if (!ok) bad.push(`${r}:${k}'${rows[r][k]}'`);
                }
                c = e;
                continue;
            }
            const ch = rows[r].charCodeAt(c), inv = a[c] === ATTR.inverse;
            let ok = true;
            for (let y = 0; y < h && ok; y++) for (let x = 0; x < CELL && ok; x++) {
                let ink = font[ch * 64 + (h === 16 ? y >> 1 : y) * 8 + x] === 1;
                if (inv) ink = !ink;
                ok = at(c * CELL + x, y0 + y) === (ink ? 0 : 1);
            }
            if (!ok) bad.push(`${r}:${c}'${rows[r][c]}'`);
            c++;
        }
    }
    return bad;
}
