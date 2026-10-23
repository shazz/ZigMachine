// The sealed machine for apps/ancool_headless.mjs, booted the way
// apps/scene_hash.mjs (and docs/sealed-loader.js) boot it, plus what that
// harness needs: a count of the cart's CHISEL blits (hwBlit wrapped) and the
// browser's composite of the enabled planes (scene_hash's stackOver).
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig

export async function boot(cartBytes, machineDir = "docs") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile(`${machineDir}/machine-video.wasm`), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    let blits = 0;
    const hwBlit = () => { blits++; machine.hwBlit(); };
    const romBytes = await readFile(`${machineDir}/rom.wasm`);
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const env = { memory, hwVideoBase: machine.hwVideoBase, hwBlit, ...rom };
    for (const k of Object.keys(machine)) if (/^hw(Rom)?Ram/.test(k)) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
    return {
        W, H,
        blits: () => blits,
        resetBlits: () => { blits = 0; },
        // The host loop (sealed-loader.js): clear, then the cart's frame.
        frame: () => { machine.hwClear(); demo.frame(16.6); },
        // Render every enabled plane (HBLs run inside) and stack them as the
        // browser's canvases are; returns how many planes were enabled.
        composite(comp) {
            comp.fill(0);
            let n = 0;
            for (let p = 0; p < machine.hwPlanesNumber(); p++) {
                if (!demo.isPlaneEnabled(p)) continue;
                n++;
                machine.hwRenderPlane(p);
                const snap = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), W * H);
                for (let i = 0; i < snap.length; i++) if (snap[i] >>> 24) comp[i] = snap[i];
            }
            if (machine.hwRamAllocFailures()) throw new Error("ancool: a zg.mem allocation was refused");
            return n;
        },
    };
}
