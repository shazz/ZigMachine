// The falcon_ays cart booted over the real machine + ROM, run frame by frame (60 Hz, no sound:
// the frame clock), and the raster it composites: shared by apps/falcon_ays_headless.mjs and
// apps/falcon_ays_board.mjs.
import { readFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

export const PAGES = 128, RW = 800, RH = 280, W = 320, H = 200, X0 = 40, Y0 = 40;
const CART = "docs/demo-falcon_ays.wasm";

export async function boot() {
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
    const cartBytes = await readFile(CART);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, video: machine.hwVideoBase(), frame: 0 };
}

// Run the cart to song second `t` (60 Hz frames), then composite every enabled plane and return
// the whole 400x280 raster, borders included, as 0xBBGGRR (the raster doubles each pixel).
export function raster(m, t) {
    const target = Math.round(t * 60);
    while (m.frame < target) { m.machine.hwClear(); m.demo.frame(1000 / 60); m.frame++; }
    // The browser stacks each enabled plane's snapshot on its own canvas: a pixel is the topmost
    // snapshot's that is not transparent (alpha 0), as apps/scene_hash.mjs composites.
    m.machine.hwClear();
    const comp = new Uint32Array(RW * RH);
    for (let p = 0; p < 8; p++) {
        if (!m.demo.isPlaneEnabled(p)) continue;
        m.machine.hwRenderPlane(p);
        const px = new Uint32Array(m.memory.buffer, m.machine.hwPhysicalPtr(), RW * RH);
        for (let i = 0; i < comp.length; i++) if (px[i] >>> 24) comp[i] = px[i];
    }
    return Uint32Array.from({ length: (RW / 2) * RH }, (_, i) => comp[i * 2] & 0xFFFFFF);
}

// The same, cut to the 320x200 window.
export function at(m, t) {
    const r = raster(m, t);
    return Uint32Array.from({ length: W * H }, (_, i) => r[(Y0 + Math.floor(i / W)) * (RW / 2) + X0 + (i % W)]);
}
