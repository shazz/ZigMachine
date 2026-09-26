// Headless COLORSHOCK 2 driver — boots the sealed machine + demo-tcb_colorshock
// the way docs/sealed-loader.js does and dumps composited frames as PPMs.
//
// Why this exists: the screen is a hardware pan whose read window follows a
// Lissajous, a per-scanline palette replayed from an HBL, and a scroll strip
// that rides a 1873-entry table. "Is the window still inside the pan buffer,
// does the palette still line up with the scroll, does the strip stay off the
// logo?" are all questions about frame N, which here is just a number.
//
//   node apps/tcb_colorshock_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 2; // 0 = the panned field, 1 = logo + scroll strip

// Machine registers this driver reads directly (machine/sdk/memmap.zig). The pan
// is a READ-POINTER move, so "did the window stay inside the pan buffer?" is a
// question about FB_BASE, not about pixels — and an answer the picture cannot
// give, because reading past the buffer corrupts silently instead of trapping.
const REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44;
const BUF_BYTES = 800 * 568; // the scene's BUF_W * BUF_H

async function boot(cart = "docs/demo-tcb_colorshock.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;

    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);

    const noop = () => {};
    const cartBytes = await readFile(cart);
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
            consoleLogJS: (p, l) => console.log("[wasm]", dec.decode(new Uint8Array(memory.buffer, p, l))),
            hwVideoBase: machine.hwVideoBase,
            hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed,
            hwRamFree: machine.hwRamFree,
            hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree,
            ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);

    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return new Screen(memory, machine, demo);
}

class Screen {
    constructor(memory, machine, demo) {
        this.machine = machine;
        this.demo = demo;
        this.w = machine.hwPhysWidth();   // 800: the visible window is x-DOUBLED
        this.h = machine.hwPhysHeight();  // 280, borders and all
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        this.regs = new DataView(memory.buffer, machine.hwVideoBase());
        this.origin = this.reg32(REG_FB_BASE); // plane 0's buffer, before any pan
        this.frames = 0;
        this.snaps = [];
    }

    reg32(off) { return this.regs.getUint32(off, true); }
    reg16(off) { return this.regs.getUint16(off, true); }

    // One host frame, exactly as docs/sealed-loader.js sequences it: clear the
    // PFB (which also runs the global HBL), let the cart draw, then composite
    // every enabled plane. hwRenderPlane OVERWRITES the shared PFB — the host
    // uploads one plane per canvas — so each plane is snapshotted and blended in
    // shot(). Rendering is done on EVERY frame, not just on a shot, because the
    // per-scanline palette only exists during a render: it is an HBL side effect.
    run(n) {
        for (let i = 0; i < n; i++) {
            this.machine.hwClear();
            this.demo.frame(16.6);
            this.frames += 1;
            this.checkPan();
            this.snaps = [];
            for (let p = 0; p < PLANES; p++) {
                this.machine.hwRenderPlane(p);
                this.snaps.push(this.pfb.slice());
            }
        }
    }

    // The machine composites plane 0 as buf[(base - origin) + y*stride + x] for
    // y < 280, x < 400, with no bounds check anywhere. Past the buffer it would
    // scribble over the next VRAM allocation — the ink plane — so assert the
    // last byte it can touch this frame is still inside.
    checkPan() {
        const off = this.reg32(REG_FB_BASE) - this.origin;
        const stride = this.reg16(REG_FB_STRIDE);
        const last = off + (this.h - 1) * stride + 399;
        if (off < 0 || last >= BUF_BYTES) {
            throw new Error(`frame ${this.frames}: pan window left the buffer ` +
                `(x=${off % stride}, y=${Math.floor(off / stride)}, last byte ${last} of ${BUF_BYTES})`);
        }
    }

    async shot(path) {
        const snaps = this.snaps;
        const half = this.w / 2; // undo the horizontal doubling
        const hdr = new TextEncoder().encode(`P6\n${half} ${this.h}\n255\n`);
        const out = new Uint8Array(hdr.length + half * this.h * 3);
        out.set(hdr);
        for (let y = 0; y < this.h; y++) {
            for (let x = 0; x < half; x++) {
                let r = 0, g = 0, b = 0;
                for (const s of snaps) {
                    const i = (y * this.w + x * 2) * 4;
                    const a = s[i + 3] / 255;
                    r = s[i] * a + r * (1 - a);
                    g = s[i + 1] * a + g * (1 - a);
                    b = s[i + 2] * a + b * (1 - a);
                }
                const o = hdr.length + (y * half + x) * 3;
                out[o] = r; out[o + 1] = g; out[o + 2] = b;
            }
        }
        await writeFile(path, out);
        // The field covers all 400x280 — borders included — so a frame that is
        // more than a few per cent dark means the pan left the buffer, a border
        // stayed shut, or the per-line palette stopped being installed. Measured
        // 0.85-0.96% on a good frame (the artwork's own near-black cells).
        let dark = 0;
        for (let i = 0; i < half * this.h; i++) {
            if (Math.max(out[hdr.length + i * 3], out[hdr.length + i * 3 + 1], out[hdr.length + i * 3 + 2]) < 40) dark++;
        }
        const pct = (100 * dark) / (half * this.h);
        if (pct > 5) throw new Error(`${path}: ${pct.toFixed(2)}% of the screen is dark — the background is not covering it`);
        console.log(`  shot: ${path} (frame ${this.frames}, ${pct.toFixed(2)}% dark)`);
    }
}

const out = process.argv[2] || "/tmp/tcb_colorshock";
await mkdir(out, { recursive: true });
const screen = await boot();
screen.run(1);
await screen.shot(`${out}/00-first.ppm`);       // the strip's end caps, the text still off to the right
screen.run(124);
await screen.shot(`${out}/01-panned.ppm`);      // sin at its far end, text arriving
screen.run(125);
await screen.shot(`${out}/02-halfway.ppm`);     // sin back, cos a quarter round
screen.run(250);
await screen.shot(`${out}/03-strip-high.ppm`);  // movescroll is climbing out of 240
screen.run(350);
await screen.shot(`${out}/04-strip-low.ppm`);   // ...and down at the top of its travel

// Soak. vbl is an f32 accumulator that does NOT wrap back to a bit-exact 0, so
// the Lissajous phase creeps; the pan bound survives that by construction (the
// x is clamped, the y is taken mod the tile height) and checkPan proves it frame
// by frame. movescroll's 937-frame cycle is covered several times over.
const t0 = performance.now();
screen.run(4000);
console.log(`  soak: ${screen.frames} frames clean, ` +
    `${((performance.now() - t0) / 4000).toFixed(2)} ms/frame (update + render + 2 plane composites)`);
