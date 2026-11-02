// The sealed machine and the plane, for apps/rick_cracktro_headless.mjs: the
// RICK DANGEROUS cart booted the way docs/sealed-loader.js boots it, a host
// frame at a time, its song requests collected; the plane read back as ink.
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128; // SHARED_PAGES in machine/sdk/memmap.zig
const CART = "docs/demo-rick_dangerous.wasm";
const RW = 800; // the physical frame: 320x200 at (40, 40), x doubled
/// The ST's VBL: 512 x 313 cycles of 8.021247 MHz, 19.98 ms.
export const VBL_MS = 512 * 313 * 1000 / 8021247;
const dec = new TextDecoder();

export async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(CART);
    const env = { ...env0, ...rom };
    for (const n of Object.keys(machine)) if (n.startsWith("hwRam") || n.startsWith("hwRomRam")) env[n] = machine[n];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const songs = [];
    /// n host frames of dt ms (default: one ST VBL each).
    const step = (n = 1, dt = 20) => { // 20 ms: one ST VBL a frame, two every ~944
        for (let i = 0; i < n; i++) {
            machine.hwClear();
            demo.frame(dt);
            if (demo.pollSongRequest()) {
                const name = dec.decode(new Uint8Array(memory.buffer, demo.songNamePtr(), demo.songNameLen()));
                songs.push(name === "none" ? "none" : `${name}#${demo.songTune()}`);
            }
            machine.hwRenderPlane(0);
        }
    };
    const press = (cp, frames = 3) => { demo.key(cp); step(frames); demo.keyUp(cp); step(frames); };
    const val = (n) => demo.rickCrackVal(n);
    return { memory, machine, demo, songs, step, press, val };
}

/// The plane as shown, as ink bits (1 = a black pixel, rows of 40 bytes), and
/// the count of pixels that are neither the paper nor the ink.
export function shownInk(ctx) {
    const pfb = new Uint32Array(ctx.memory.buffer, ctx.machine.hwPhysicalPtr(), RW * 280);
    const ink = new Uint8Array(8000);
    let other = 0;
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const p = pfb[(40 + y) * RW + 80 + 2 * x] & 0xffffff;
        if (p === 0) ink[y * 40 + (x >> 3)] |= 0x80 >> (x & 7);
        else if (p !== 0xffffff) other++;
    }
    return { ink, other };
}

/// Pixels that differ between two ink images, and the text rows they are in.
export function inkDiff(a, b) {
    let n = 0;
    const rows = new Set();
    for (let i = 0; i < 8000; i++) {
        let x = a[i] ^ b[i];
        if (x) rows.add(Math.floor(i / 320));
        for (; x; x &= x - 1) n++;
    }
    return { n, rows: [...rows] };
}

export async function shot(ink, path) {
    const rgb = Buffer.alloc(320 * 200 * 3, 255);
    for (let i = 0; i < 64000; i++) if (ink[i >> 3] & (0x80 >> (i & 7))) rgb.fill(0, 3 * i, 3 * i + 3);
    await writeFile(path, Buffer.concat([Buffer.from("P6\n320 200\n255\n"), rgb]));
}

export const fnv = (bytes) => {
    let h = 0x811c9dc5;
    for (const b of bytes) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h.toString(16).padStart(8, "0");
};

/// Host frames until the typewriter is idle with text position `pos` next (the
/// step that read pos - 1 done, its wait running): the cracktro's VBL count then.
export function runTo(ctx, pos, limit = 5000) {
    for (let f = 0; f < limit; f++) {
        if (ctx.val(1) === pos && ctx.val(7) === 0 && ctx.val(8) === 0 && ctx.val(2) > 0) return ctx.val(5);
        ctx.step();
    }
    return -1;
}
