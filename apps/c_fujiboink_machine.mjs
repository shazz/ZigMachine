// The sealed machine as apps/c_fujiboink_headless.mjs drives it, plus the two
// readers its checks need: Hatari's PNG screenshots (the references) and the
// machine's own frame, both reduced to ST colour levels (3 bits a gun) so the
// two emulators' different gun scales (Hatari v*34, the machine v*32) compare.
import { readFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
export const OFF_PAL = 0x0100, REG_FB_BASE = 0x44; // memmap.zig

// Boot the cart the way docs/sealed-loader.js does. `hbl` wraps the cart's
// hblDispatch so a harness can watch (or sabotage) the per-line handler.
export async function boot(cart, hbl = (demo, id, p, l, x) => demo.hblDispatch(id, p, l, x)) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => hbl(demo, id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart), env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

// A 320x200 frame of ST colour words (0x0RGB, 3 bits a gun) from the machine's
// physical framebuffer: 800x280, the visible window at (80,40), x doubled.
export function stFrame(memory, machine) {
    const w = machine.hwPhysWidth();
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), w * machine.hwPhysHeight() * 4);
    const out = new Uint16Array(320 * 200);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++) {
            const i = ((40 + y) * w + 80 + x * 2) * 4;
            out[y * 320 + x] = (px[i] >> 5) << 8 | (px[i + 1] >> 5) << 4 | (px[i + 2] >> 5);
        }
    return out;
}

// A Hatari screenshot (640x400 RGB PNG of the 320x200 low-res screen, doubled
// both ways, guns v*34) as the same 320x200 array of ST colour words.
export async function hatariFrame(path) {
    const png = await readFile(path);
    const w = png.readUInt32BE(16), h = png.readUInt32BE(20);
    if (png[24] !== 8 || png[25] !== 2 || png[28] !== 0) throw new Error(`${path}: want 8-bit RGB, non-interlaced`);
    const idat = [];
    for (let o = 8; o < png.length;) {
        const len = png.readUInt32BE(o), type = png.toString("latin1", o + 4, o + 8);
        if (type === "IDAT") idat.push(png.subarray(o + 8, o + 8 + len));
        o += 12 + len;
    }
    const raw = inflateSync(Buffer.concat(idat)), bpp = 3, stride = w * bpp;
    const img = Buffer.alloc(h * stride);
    for (let y = 0; y < h; y++) { // PNG filters 0-4
        const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        for (let i = 0; i < stride; i++) {
            const a = i >= bpp ? img[y * stride + i - bpp] : 0, b = y ? img[(y - 1) * stride + i] : 0;
            const c = i >= bpp && y ? img[(y - 1) * stride + i - bpp] : 0;
            const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
            const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f];
            img[y * stride + i] = (src[i] + pred) & 255;
        }
    }
    if (w !== 640 || h !== 400) throw new Error(`${path}: ${w}x${h}, want Hatari's 640x400 low-res capture`);
    const out = new Uint16Array(320 * 200), lv = (v) => Math.round(v / 34);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++) {
            const i = (y * 2 * w + x * 2) * 3;
            out[y * 320 + x] = lv(img[i]) << 8 | lv(img[i + 1]) << 4 | lv(img[i + 2]);
        }
    return out;
}

// Fraction of the 64000 pixels with the same ST colour.
export function same(a, b) {
    let n = 0;
    for (let i = 0; i < a.length; i++) if (a[i] === b[i]) n++;
    return n / a.length;
}
