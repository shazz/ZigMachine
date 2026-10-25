// Boot a cart the way apps/scene_hash.mjs does (same machine, same host loop, fixed dt),
// with the cart and the ROM instrumented (instrument.mjs). Both run on ZIGGY on the
// board (wasm2c'd); the machine (FRESCO render, CHISEL blits) is hardware there, so it
// runs as-is and only its blitter calls and HBL interrupts are counted.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../../docs/wasm_hiwater.js";
import { makeDrive } from "../scene_hash_disk.mjs";
import { instrument } from "./instrument.mjs";
import { blitCycles, BLIT_CALL, BLIT_UNIT_ORDERED } from "./cost_model.mjs";
import { BLIT_SITE, STORE_TOTAL, PAL_TOTAL, MIS_LOADS, MIS_STORES } from "./hooks.mjs";
import { SNOOP_QUEUE } from "./cost_model.mjs";

const PAGES = 112;          // SHARED_PAGES in machine/sdk/memmap.zig
// machine/sdk/memmap.zig: palettes, VRAM pool, blitter block
export const OFF_PAL = 0x100, PAL_BYTES = 4 * 1024, OFF_VRAM = 0x1100;
export const REG_GLOBAL_HBL_ID = 0x10, REG_FB_HBL_ID = 0x20, REG_FB_MODE = 0x54;
const BLIT_COMMAND = 0x80, BLIT_W = 0xa8, BLIT_H = 0xaa, BLIT_CYCLES = 0xe0;
const BLIT_CON = 0x82, BLIT_CON2 = 0x87, BLIT_A_BASE = 0x88, BLIT_A_STRIDE = 0x8c, BLIT_B_BASE = 0x90, BLIT_B_STRIDE = 0x94;
const BLIT_D_BASE = 0xa0, BLIT_D_STRIDE = 0xa4, BLIT_X0 = 0xac, BLIT_Y0 = 0xae, CON_USEA = 1, CON_USEB = 2, CON2_SRC_ABS = 1;

// Whether this BLIT runs ORDERED on the board (cost_model.mjs BLIT_UNIT_ORDERED): the overlap test of
// fpga/rtl/blitter/zm_blit_chk.v, on spans and conservative. The destination span runs from D_BASE
// (the plane's base) to the box's last byte, d + (y0 + h - 1) * ds + x0 + w; a used source (A or B,
// as CON enables them) overlaps it unless its span [base, base + (h - 1) * stride + w) lies wholly
// before or after. Everything compared as video-region offsets (CON2.SRC_ABS sources are linear).
// The clip is ignored, which only widens the destination: conservative, like the RTL.
function inPlane(view, base) {
    const u16 = (o) => view.getUint16(base + o, true), i16 = (o) => view.getInt16(base + o, true);
    const con = view.getUint8(base + BLIT_CON), abs = view.getUint8(base + BLIT_CON2) & CON2_SRC_ABS;
    const w = u16(BLIT_W), h = u16(BLIT_H);
    if (!w || !h) return -1;
    const d = view.getUint32(base + BLIT_D_BASE, true);
    const dHi = d + (i16(BLIT_Y0) + h - 1) * u16(BLIT_D_STRIDE) + i16(BLIT_X0) + w;
    for (const [bit, reg, sreg] of [[CON_USEA, BLIT_A_BASE, BLIT_A_STRIDE], [CON_USEB, BLIT_B_BASE, BLIT_B_STRIDE]]) {
        if (!(con & bit)) continue;
        const raw = view.getUint32(base + reg, true), lo = abs ? raw - base : raw, hi = lo + (h - 1) * u16(sreg) + w;
        if (!(hi <= d || dHi <= lo)) return 0;
    }
    return -1;
}

function envFor(machine, extra) {
    const env = { ...extra };
    for (const k of ["hwVideoBase", "hwRamBase", "hwRamTop", "hwRamSize", "hwRamUsed", "hwRamFree", "hwRamAlloc",
        "hwRamMark", "hwRamRelease", "hwRamAllocFailures", "hwRomRamBase", "hwRomRamTop", "hwRomRamSize",
        "hwRomRamUsed", "hwRomRamFree"]) env[k] = machine[k];
    return env;
}

// hwBlit as the board runs it, counted: cycles by op, and a per-frame log of every op
// with its size and the call site that issued it (the site word each module's hook sets).
function blitter(machine, memory, base, hw, mods) {
    const view = new DataView(memory.buffer);
    return () => {
        const cmd = view.getUint8(base + BLIT_COMMAND), minterm = view.getUint8(base + BLIT_COMMAND + 1);
        const area = view.getUint16(base + BLIT_W, true) * view.getUint16(base + BLIT_H, true);
        const plane = cmd === 1 ? inPlane(view, base) : -1;
        machine.hwBlit();
        const units = view.getUint32(base + BLIT_CYCLES, true);
        const normal = blitCycles(cmd, units, minterm), cycles = plane >= 0 ? BLIT_CALL + units * BLIT_UNIT_ORDERED : normal;
        hw.blits++; hw.blitUnits += units; hw.blitCycles += cycles;
        if (cmd < hw.cmd.length) hw.cmd[cmd] += units;
        const m = mods.findIndex((x) => x.mem && new Int32Array(x.mem.buffer)[BLIT_SITE] >= 0);
        const site = m >= 0 ? new Int32Array(mods[m].mem.buffer)[BLIT_SITE] : -1;
        hw.blitLog.push({ mod: m, site, cmd, bytes: cmd === 1 || cmd === 2 ? area : units, cycles, inplane: plane >= 0, extra: cycles - normal });
    };
}

// An HBL handler, counted with the stores it makes: on the board they run inside FRESCO's
// line passes, which wait for them to drain (docs/FPGA_STEPS.md, the sequencer).
// Palette stores are SNOOPED to the compositor through a 16-entry queue; one handler's
// stores beyond it are counted apart (cost_model.mjs SNOOP_OVERFLOW).
// `by`: calls per plane 0..3, and [4] the global (border/background) handler's.
function hbl(hw, mods, call, by) {
    const total = (w) => mods.reduce((a, x) => a + (x.mem ? new Uint32Array(x.mem.buffer)[w] : 0), 0);
    const stores = total(STORE_TOTAL), pal = total(PAL_TOTAL);
    call();
    hw.hbls++; hw.hblBy[by]++; hw.hblStores += total(STORE_TOTAL) - stores;
    hw.snoopOverflow += Math.max(0, total(PAL_TOTAL) - pal - SNOOP_QUEUE);
}

// cartBytes: the cart wasm. opts: { machineDir, disk, pal, names: {cart, rom} (Maps) }.
// Returns { memory, machine, demo, hw, mods: [{tag, plan, mem}], vlo }.
export async function bootInstrumented(cartBytes, { machineDir = "docs", disk = null, pal = true, names = {} } = {}) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const hw = { blits: 0, blitUnits: 0, blitCycles: 0, hbls: 0, hblBy: [0, 0, 0, 0, 0], hblStores: 0, snoopOverflow: 0, diskBlocks: 0, misaligned: 0, cmd: [0, 0, 0, 0, 0], blitLog: [] };
    const mods = [{ tag: "cart" }, { tag: "rom" }];
    let demo, globalId = () => 0;
    const machine = (await WebAssembly.instantiate(await readFile(`${machineDir}/machine-video.wasm`), {
        env: { memory, hblDispatch: (id, p, l, x) => hbl(hw, mods, () => demo.hblDispatch(id, p, l, x), id === globalId() ? 4 : p) },
    })).instance.exports;
    const base = machine.hwVideoBase(), vlo = base + OFF_VRAM;
    globalId = () => new DataView(memory.buffer).getUint16(base + REG_GLOBAL_HBL_ID, true); // the global handler dispatches as plane 0
    const hwBlit = blitter(machine, memory, base, hw, mods);
    const palWin = pal ? [base + OFF_PAL, base + OFF_PAL + PAL_BYTES] : null;

    const romBytes = await readFile(`${machineDir}/rom.wasm`);
    const romI = instrument(romBytes, { pal: palWin, vlo, names: names.rom });
    const romInst = (await WebAssembly.instantiate(romI.bytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit } })).instance;
    const rom = { ...romInst.exports };
    delete rom.__fc;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);

    const cartI = instrument(cartBytes, { pal: palWin, vlo, names: names.cart });
    const env = envFor(machine, { memory, hwBlit, ...rom });
    if (disk) { // counted: on the board each 512-byte block is copied out of DDR by the firmware
        const drive = makeDrive(memory, { buf: new Uint8Array(await readFile(disk)) });
        env.diskReadBlock = (block, dst) => { const n = drive(block, dst); if (n) hw.diskBlocks++; return n; };
    }
    const noop = () => {};
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    const cartInst = (await WebAssembly.instantiate(cartI.bytes, { env })).instance;
    Object.assign(mods[0], { plan: cartI.plan, mem: cartInst.exports.__fc });
    Object.assign(mods[1], { plan: romI.plan, mem: romInst.exports.__fc });
    for (const x of mods) new Int32Array(x.mem.buffer)[BLIT_SITE] = -1;
    demo = cartInst.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    // misaligned wide loads and stores so far, both modules (each traps on the board)
    const misaligned = () => mods.reduce((a, x) => {
        const w = x.mem ? new Uint32Array(x.mem.buffer) : null;
        return a + (w ? w[MIS_LOADS] + w[MIS_STORES] : 0);
    }, 0);
    return { memory, machine, demo, hw, mods, vlo, misaligned };
}

// One host frame, exactly scene_hash.mjs's loop body.
// songMs: what the host mirrors into zigos.song_ms from the playing tune (the board's BARD does it
// every frame); a cart that paces its parts on the music never leaves its first part without it.
export function hostFrame({ machine, demo, memory }, songMs = null) {
    if (songMs !== null && demo.getSongMsPointer) new Uint32Array(memory.buffer, demo.getSongMsPointer(), 1)[0] = songMs;
    machine.hwClear();
    demo.frame(Number(process.env.PERF_DT ?? 16.6)); // PERF_DT: a slower host frame (a cart that runs ST VBLs per elapsed ms does more work per frame)
    const planes = machine.hwPlanesNumber();
    for (let p = 0; p < planes; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
}
