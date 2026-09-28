// The sealed machine + demo-ulm_dsots.wasm, booted as docs/sealed-loader.js
// does (apps/union_demo_headless.mjs's boot), for apps/ulm_dsots_headless.mjs.
import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
export const CANVAS = { x: 8, y: 5, w: 384, h: 270 }; // ulm_dsots/draw.zig OX, OY, CANVAS_W/H

export async function boot(cart = "docs/demo-ulm_dsots.wasm") {
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
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    const bytes = await readFile(cart);
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(bytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
    demo = (await WebAssembly.instantiate(bytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    rom.romReset();
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const m = { memory, machine, demo, cost: [] };
    m.val = (i) => demo.dsotsVal(i);
    m.tag = () => new TextDecoder().decode(new Uint8Array(memory.buffer, demo.getCartTagPtr(), demo.getCartTagLen()));
    return m;
}

/// One host frame: the cart's frame, the host's cart poll, the planes rendered.
/// Returns the cart request (0 none).
export function frame(m, dt = 1000 / 60) {
    m.machine.hwClear();
    const t = performance.now();
    m.demo.frame(dt);
    const req = m.demo.pollCartRequest();
    for (let p = 0; p < m.machine.hwPlanesNumber(); p++) if (m.demo.isPlaneEnabled(p)) m.machine.hwRenderPlane(p);
    m.cost.push(performance.now() - t);
    return req;
}

/// The remake's canvas (384x270 halved) out of the physical frame, RGB, read
/// `dx` pixels to the right (a --break render shifts it).
export function canvas(m, dx = 0) {
    const w = m.machine.hwPhysWidth();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), w * m.machine.hwPhysHeight() * 4);
    const out = new Uint8Array(CANVAS.w * CANVAS.h * 3);
    for (let y = 0; y < CANVAS.h; y++)
        for (let x = 0; x < CANVAS.w; x++) {
            const s = ((CANVAS.y + y) * w + 2 * (CANVAS.x + x + dx)) * 4, d = (y * CANVAS.w + x) * 3;
            out[d] = pfb[s]; out[d + 1] = pfb[s + 1]; out[d + 2] = pfb[s + 2];
        }
    return out;
}

/// Pixels of the 400x280 plane outside the canvas that are not opaque black.
export function outsideNotBlack(m) {
    const w = m.machine.hwPhysWidth(), h = m.machine.hwPhysHeight();
    const pfb = new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), w * h * 4);
    let n = 0;
    for (let y = 0; y < h; y++)
        for (let x = 0; x < w / 2; x++) {
            const inside = x >= CANVAS.x && x < CANVAS.x + CANVAS.w && y >= CANVAS.y && y < CANVAS.y + CANVAS.h;
            const s = (y * w + 2 * x) * 4;
            if (!inside && (pfb[s] | pfb[s + 1] | pfb[s + 2]) !== 0) n++;
        }
    return n;
}

export async function writePng(file, rgb, w, h) {
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
        const td = Buffer.concat([Buffer.from(type), data]);
        const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
        return Buffer.concat([len, td, c]);
    };
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) Buffer.from(rgb.buffer, rgb.byteOffset + y * w * 3, w * 3).copy(raw, y * (w * 3 + 1) + 1);
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
    const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    await writeFile(file, Buffer.concat([sig, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
