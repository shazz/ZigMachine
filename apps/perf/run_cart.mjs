// Boot a cart the way apps/scene_hash.mjs does (same machine, same host loop, fixed dt),
// with the cart and the ROM instrumented (instrument.mjs). Both run on ZIGGY on the
// board (wasm2c'd); the machine (FRESCO render, CHISEL blits) is hardware there, so it
// runs as-is and only its blitter calls and HBL interrupts are counted.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../../docs/wasm_hiwater.js";
import { makeDrive } from "../scene_hash_disk.mjs";
import { instrument } from "./instrument.mjs";
import { blitCycles } from "./cost_model.mjs";

const PAGES = 112;          // SHARED_PAGES in machine/sdk/memmap.zig
const OFF_PAL = 0x100, PAL_BYTES = 4 * 1024, BLIT_COMMAND = 0x80, BLIT_CYCLES = 0xe0; // machine/sdk/memmap.zig

function envFor(machine, extra) {
    const env = { ...extra };
    for (const k of ["hwVideoBase", "hwRamBase", "hwRamTop", "hwRamSize", "hwRamUsed", "hwRamFree", "hwRamAlloc",
        "hwRamMark", "hwRamRelease", "hwRamAllocFailures", "hwRomRamBase", "hwRomRamTop", "hwRomRamSize",
        "hwRomRamUsed", "hwRomRamFree"]) env[k] = machine[k];
    return env;
}

// cartBytes: the cart wasm. opts: { machineDir, disk, pal, names: {cart, rom} (Maps) }.
// Returns { memory, machine, demo, hw, mods: [{tag, plan, mem}] }.
export async function bootInstrumented(cartBytes, { machineDir = "docs", disk = null, pal = true, names = {} } = {}) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const hw = { blits: 0, blitUnits: 0, blitCycles: 0, hbls: 0, cmd: [0, 0, 0, 0, 0] };
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile(`${machineDir}/machine-video.wasm`), {
        env: { memory, hblDispatch: (id, p, l, x) => { hw.hbls++; return demo.hblDispatch(id, p, l, x); } },
    })).instance.exports;
    const base = machine.hwVideoBase();
    const view = new DataView(memory.buffer);
    const hwBlit = () => {
        const cmd = view.getUint8(base + BLIT_COMMAND), minterm = view.getUint8(base + BLIT_COMMAND + 1);
        machine.hwBlit();
        const units = view.getUint32(base + BLIT_CYCLES, true);
        hw.blits++; hw.blitUnits += units; hw.blitCycles += blitCycles(cmd, units, minterm);
        if (cmd < hw.cmd.length) hw.cmd[cmd] += units;
    };
    const palWin = pal ? [base + OFF_PAL, base + OFF_PAL + PAL_BYTES] : null;

    const romBytes = await readFile(`${machineDir}/rom.wasm`);
    const romI = instrument(romBytes, { pal: palWin, names: names.rom });
    const romInst = (await WebAssembly.instantiate(romI.bytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit } })).instance;
    const rom = { ...romInst.exports };
    delete rom.__fc;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);

    const cartI = instrument(cartBytes, { pal: palWin, names: names.cart });
    const env = envFor(machine, { memory, hwBlit, ...rom });
    if (disk) env.diskReadBlock = makeDrive(memory, { buf: new Uint8Array(await readFile(disk)) });
    const noop = () => {};
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    const cartInst = (await WebAssembly.instantiate(cartI.bytes, { env })).instance;
    demo = cartInst.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const mods = [
        { tag: "cart", plan: cartI.plan, mem: cartInst.exports.__fc },
        { tag: "rom", plan: romI.plan, mem: romInst.exports.__fc },
    ];
    return { memory, machine, demo, hw, mods };
}

// One host frame, exactly scene_hash.mjs's loop body.
export function hostFrame({ machine, demo }) {
    machine.hwClear();
    demo.frame(16.6);
    const planes = machine.hwPlanesNumber();
    for (let p = 0; p < planes; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
}
