// SYSINFO harness, the machine side (apps/sysinfo_check.mjs runs the checks):
// the sealed machine, the ROM and the cart over one memory as docs/sealed-loader.js
// wires them, its own disk in the drive, a host clock or none, and the ROM's
// drawing calls counted (a page that did not change must draw nothing).
//
// The page's text is read where the cart keeps it: its two 80 x 25 text grids
// (apps/zig/scenes/sysinfo/grid.zig), found by the program line every page has.
// glassMismatches() then holds the glass to that text, glyph by glyph, in the
// system font the ROM draws with.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { parseDisk } from "../docs/zmdisk.js";

const PAGES = 112, BLOCK = 512, COLS = 80, ROWS = 25, CELL = 8, W = 640;
const TITLE = "SYSINFO FOR ZIGMACHINE, VERSION ";
const DRAWS = ["guiText", "guiTextAlign", "guiFill", "guiRect", "guiFrame", "guiBox", "guiButton", "guiPlot"];
export const K = { F1: 0xe001, HELP: 0xe011, ESC: 0xe012 };

/// Boot SYSINFO. clock: "none" (hostMicros answers 0, as the gate's other carts get) or "host".
/// corrupt: a FAT file the DRIVE serves with one byte changed (the harness keeps the real image).
export async function boot(clock = "none", corrupt = null) {
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
    const s = { memory, machine, demo: null, draws: 0, disk };
    const env = { memory, ...rom };
    for (const n of DRAWS) env[n] = (...a) => { s.draws++; return rom[n](...a); };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    env.hostMicros = clock === "host" ? () => (Math.floor(performance.now() * 1000) >>> 0) || 1 : () => 0;
    env.diskReadBlock = (block, dst) => {
        const src = served.subarray(block * BLOCK, block * BLOCK + BLOCK);
        new Uint8Array(memory.buffer, dst, src.length).set(src);
        return src.length;
    };
    const cartBytes = await readFile("docs/demo-sysinfo.wasm");
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = s.demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
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

/// The cart's text grids, each as 25 strings (want and shown: both carry the program line).
export function grids(s) {
    const mem = new Uint8Array(s.memory.buffer, 0x100000, 0x200000);
    const key = new TextEncoder().encode(TITLE);
    const out = [];
    for (let i = mem.indexOf(key[0]); i >= 0; i = mem.indexOf(key[0], i + 1)) {
        if (!key.every((b, j) => mem[i + j] === b)) continue;
        if (mem[i + key.length] < 0x30 || mem[i + key.length] > 0x39) continue; // the format string has "{s}"
        const at = i - 1; // the line starts at column 1
        out.push(Array.from({ length: ROWS }, (_, r) => String.fromCharCode(...mem.subarray(at + r * COLS, at + (r + 1) * COLS))));
    }
    return out;
}

/// The text on the glass: the shown grid (the cart keeps two equal copies once a page is drawn).
export function page(s) {
    const g = grids(s);
    if (g.length !== 2) throw new Error(`expected the cart's two text grids, found ${g.length}`);
    return g[0];
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

/// Plane 0's pixels: palette indices, 640 a row.
export function glass(s) {
    const base = s.machine.hwVideoBase();
    const off = new DataView(s.memory.buffer).getUint32(base + 0x44, true); // REG_FB_BASE[0]
    return new Uint8Array(s.memory.buffer, base + off, W * 200);
}

/// Cells of `rows` the glass does not show in the 8x8 system font (BLACK 0 on WHITE 1;
/// an underlined cell has its last row inked, an inverse one swaps the colours).
export async function glassMismatches(s, rows) {
    const font = new Uint8Array(await readFile("libs/zig/assets/fonts/system_font_atari_1bit.raw"));
    const px = glass(s);
    const bad = [];
    for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
        const ch = rows[r].charCodeAt(c);
        const cell = (inv, under) => {
            for (let y = 0; y < CELL; y++) for (let x = 0; x < CELL; x++) {
                let ink = font[ch * 64 + y * 8 + x] === 1 || (under && y === CELL - 1);
                if (inv) ink = !ink;
                if (px[(r * CELL + y) * W + c * CELL + x] !== (ink ? 0 : 1)) return false;
            }
            return true;
        };
        if (!(cell(false, false) || cell(false, true) || cell(true, false))) bad.push(`${r}:${c}'${rows[r][c]}'`);
    }
    return bad;
}
