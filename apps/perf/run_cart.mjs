// Boot a cart the way apps/scene_hash.mjs does (same machine, same host loop, fixed dt),
// with the cart and the ROM instrumented (instrument.mjs). Both run on ZIGGY on the
// board (wasm2c'd); the machine (FRESCO render, CHISEL blits) is hardware there, so it
// runs as-is and only its blitter calls and HBL interrupts are counted.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../../docs/wasm_hiwater.js";
import { makeDrive } from "../scene_hash_disk.mjs";
import { instrument } from "./instrument.mjs";
import { blitCycles } from "./cost_model.mjs";
import { BLIT_SITE, STORE_TOTAL, PAL_TOTAL, MIS_LOADS, MIS_STORES } from "./hooks.mjs";
import { SNOOP_QUEUE } from "./cost_model.mjs";

const PAGES = 112;          // SHARED_PAGES in machine/sdk/memmap.zig
// machine/sdk/memmap.zig: palettes, VRAM pool, blitter block
export const OFF_PAL = 0x100, PAL_BYTES = 4 * 1024, OFF_VRAM = 0x1100;
const BLIT_COMMAND = 0x80, BLIT_W = 0xa8, BLIT_H = 0xaa, BLIT_CYCLES = 0xe0;

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
        machine.hwBlit();
        const units = view.getUint32(base + BLIT_CYCLES, true), cycles = blitCycles(cmd, units, minterm);
        hw.blits++; hw.blitUnits += units; hw.blitCycles += cycles;
        if (cmd < hw.cmd.length) hw.cmd[cmd] += units;
        const m = mods.findIndex((x) => x.mem && new Int32Array(x.mem.buffer)[BLIT_SITE] >= 0);
        const site = m >= 0 ? new Int32Array(mods[m].mem.buffer)[BLIT_SITE] : -1;
        hw.blitLog.push({ mod: m, site, cmd, bytes: cmd === 1 || cmd === 2 ? area : units, cycles });
    };
}

// An HBL handler, counted with the stores it makes: on the board they run inside FRESCO's
// line passes, which wait for them to drain (docs/FPGA_STEPS.md, the sequencer).
// Palette stores are SNOOPED to the compositor through a 16-entry queue; one handler's
// stores beyond it are counted apart (cost_model.mjs SNOOP_OVERFLOW).
function hbl(hw, mods, call) {
    const total = (w) => mods.reduce((a, x) => a + (x.mem ? new Uint32Array(x.mem.buffer)[w] : 0), 0);
    const stores = total(STORE_TOTAL), pal = total(PAL_TOTAL);
    call();
    hw.hbls++; hw.hblStores += total(STORE_TOTAL) - stores;
    hw.snoopOverflow += Math.max(0, total(PAL_TOTAL) - pal - SNOOP_QUEUE);
}

// cartBytes: the cart wasm. opts: { machineDir, disk, pal, names: {cart, rom} (Maps) }.
// Returns { memory, machine, demo, hw, mods: [{tag, plan, mem}], vlo }.
export async function bootInstrumented(cartBytes, { machineDir = "docs", disk = null, pal = true, names = {} } = {}) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const hw = { blits: 0, blitUnits: 0, blitCycles: 0, hbls: 0, hblStores: 0, snoopOverflow: 0, misaligned: 0, cmd: [0, 0, 0, 0, 0], blitLog: [] };
    const mods = [{ tag: "cart" }, { tag: "rom" }];
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile(`${machineDir}/machine-video.wasm`), {
        env: { memory, hblDispatch: (id, p, l, x) => hbl(hw, mods, () => demo.hblDispatch(id, p, l, x)) },
    })).instance.exports;
    const base = machine.hwVideoBase(), vlo = base + OFF_VRAM;
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
    if (disk) env.diskReadBlock = makeDrive(memory, { buf: new Uint8Array(await readFile(disk)) });
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
export function hostFrame({ machine, demo }) {
    machine.hwClear();
    demo.frame(Number(process.env.PERF_DT ?? 16.6)); // PERF_DT: a slower host frame (a cart that runs ST VBLs per elapsed ms does more work per frame)
    const planes = machine.hwPlanesNumber();
    for (let p = 0; p < planes; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
}
