// The STCS cart booted headless for apps/stcs_zig_headless.mjs: the host loop
// of docs/sealed-loader.js (clear, frame, render every enabled plane) and the
// COMPOSED picture (each enabled plane stacked as the browser's canvases are,
// scene_hash.mjs --composite), 400x280 at one pixel per low-res pixel.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";
import { makeDrive } from "./scene_hash_disk.mjs";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig

export async function boot(cartPath, diskPath) {
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
    const cartBytes = await readFile(cartPath);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hwRam") || k.startsWith("hwRomRam")) env[k] = machine[k];
    env.hwVideoBase = machine.hwVideoBase;
    env.hwBlit = machine.hwBlit;
    if (diskPath) env.diskReadBlock = makeDrive(memory, { buf: new Uint8Array(await readFile(diskPath)) });
    const noop = () => {};
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return new Screen(memory, machine, demo);
}

class Screen {
    constructor(memory, machine, demo) {
        this.memory = memory;
        this.machine = machine;
        this.demo = demo;
        this.pw = machine.hwPhysWidth(); // 800: low-res pixels are doubled
        this.h = machine.hwPhysHeight(); // 280
        this.w = this.pw / 2;
        this.comp = new Uint32Array(this.pw * this.h);
        this.frames = 0;
    }

    step() {
        const { machine, demo, comp } = this;
        machine.hwClear();
        demo.frame(16.6);
        this.frames += 1;
        comp.fill(0);
        for (let p = 0; p < machine.hwPlanesNumber(); p++) {
            if (!demo.isPlaneEnabled(p)) continue;
            machine.hwRenderPlane(p);
            const snap = new Uint32Array(this.memory.buffer, machine.hwPhysicalPtr(), comp.length);
            for (let i = 0; i < snap.length; i++) if (snap[i] >>> 24) comp[i] = snap[i];
        }
    }

    /// The composed RGBA word at low-res pixel (x, y) of the 400x280 frame.
    at(x, y) {
        return this.comp[y * this.pw + 2 * x];
    }
}
