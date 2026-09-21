// Headless POLKA DOTS driver — boots the sealed machine + demo-polkadots the
// way docs/sealed-loader.js does, dumps composited frames as PPMs and measures
// what the screen actually costs.
//
// Why this exists: the effect is a halftone, so "is it right?" is a question
// about the DISTRIBUTION of dot sizes, not about one pixel — and the reason
// Matt asked for this port is the COST, one hardware blit per lit cell. Both
// are numbers, and this is where they get measured: the harness recovers the
// blit count from the picture (a stamped cell's field is (7,7,7), the cleared
// screen is (0,0,0)) and times the cart's own frame separately from the plane
// composite the host would do.
//
//   node apps/polkadots_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1; // the whole screen is one plane, as the original is one canvas
const CELL = 7;
const CELLS_X = 45, CELLS_Y = 28;
const X_OFF = 2, Y_OFF = 2; // (320 - 315) / 2, (200 - 196) / 2

async function boot(cart = "docs/demo-polkadots.wasm") {
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
        this.frames = 0;
        this.cart_ms = 0;
        this.snaps = [];
    }

    // One host frame, as docs/sealed-loader.js sequences it. hwRenderPlane
    // OVERWRITES the shared PFB, so each plane is snapshotted and blended in
    // shot() rather than read back once at the end.
    run(n) {
        for (let i = 0; i < n; i++) {
            this.machine.hwClear();
            const t = performance.now();
            this.demo.frame(16.6);
            this.cart_ms += performance.now() - t;
            this.frames += 1;
            this.snaps = [];
            for (let p = 0; p < PLANES; p++) {
                this.machine.hwRenderPlane(p);
                this.snaps.push(this.pfb.slice());
            }
        }
    }

    // The visible 320x200 window sits at physical (80, 40) with x doubled, so
    // in the half-width image a logical (lx, ly) is (40 + lx, 40 + ly).
    rgb(lx, ly) {
        const i = ((40 + ly) * this.w + (80 + lx * 2)) * 4;
        let r = 0, g = 0, b = 0;
        for (const s of this.snaps) {
            const a = s[i + 3] / 255;
            r = s[i] * a + r * (1 - a);
            g = s[i + 1] * a + g * (1 - a);
            b = s[i + 2] * a + b * (1 - a);
        }
        return [r, g, b];
    }

    // A stamped cell carries the tiles' own (7,7,7) field; a cell the screen
    // left alone is the cleared (0,0,0). Counting the first is counting the
    // blits the cart issued this frame.
    census() {
        let blits = 0;
        const sizes = new Array(10).fill(0);
        for (let cy = 0; cy < CELLS_Y; cy++) {
            for (let cx = 0; cx < CELLS_X; cx++) {
                let lit = false, ink = 0;
                for (let y = 0; y < CELL; y++) {
                    for (let x = 0; x < CELL; x++) {
                        const [r] = this.rgb(X_OFF + cx * CELL + x, Y_OFF + cy * CELL + y);
                        if (r > 0) lit = true;
                        if (r > 7) ink++;
                    }
                }
                if (!lit) continue;
                blits++;
                sizes[TILE_OF_INK.get(ink) ?? 0]++;
            }
        }
        return { blits, sizes };
    }

    async shot(path) {
        const half = this.w / 2;
        const hdr = new TextEncoder().encode(`P6\n${half} ${this.h}\n255\n`);
        const out = new Uint8Array(hdr.length + half * this.h * 3);
        out.set(hdr);
        for (let y = 0; y < this.h; y++) {
            for (let x = 0; x < half; x++) {
                let r = 0, g = 0, b = 0;
                for (const s of this.snaps) {
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
        const { blits, sizes } = this.census();
        if (blits < 100) throw new Error(`${path}: only ${blits} cells stamped — the torus is missing or tiny`);
        if (blits > 700) throw new Error(`${path}: ${blits} cells stamped — the torus has lost its hole or is drawing the whole grid`);
        if (sizes.slice(6).reduce((a, b) => a + b, 0) === 0) {
            throw new Error(`${path}: no bright dots — the directional light is not reaching any face`);
        }
        console.log(`  shot: ${path} (frame ${this.frames}, ${blits} blits, sizes ${sizes.join("/")})`);
        return blits;
    }
}

// Ink pixels per 7x7 tile, measured on pat.raw: the dot grows 0, 1, 5, 9, 13,
// 17, 25, 37, 45, 49 — the halftone ramp itself.
const TILE_OF_INK = new Map([[0, 0], [1, 1], [5, 2], [9, 3], [13, 4], [17, 5], [25, 6], [37, 7], [45, 8], [49, 9]]);

const out = process.argv[2] || "/tmp/polkadots";
await mkdir(out, { recursive: true });
const screen = await boot();
screen.run(1);
let peak = await screen.shot(`${out}/00-first.ppm`);     // rotation (0.02, 0.04): the ring near face-on
screen.run(24);
peak = Math.max(peak, await screen.shot(`${out}/01-quarter.ppm`)); // y has turned a radian
screen.run(55);
peak = Math.max(peak, await screen.shot(`${out}/02-edge.ppm`));    // the tube seen close to edge-on
screen.run(79);
peak = Math.max(peak, await screen.shot(`${out}/03-back.ppm`));

// Soak: the rotation is two unbounded f64 accumulators, so no frame repeats.
// What is being proven is that the stamp never walks off the plane (blitImage
// clips, but a bad offset would show as a blit count that jumps) and what the
// screen costs when the torus is at its widest.
const t0 = screen.cart_ms, f0 = screen.frames;
screen.run(600);
const ms = (screen.cart_ms - t0) / (screen.frames - f0);
peak = Math.max(peak, screen.census().blits);
console.log(`  soak: ${screen.frames} frames clean, ${ms.toFixed(3)} ms/frame in the cart ` +
    `(project + shade + ${peak} peak blits), ${(1000 / ms).toFixed(0)} fps of headroom`);
if (ms > 16.6) throw new Error(`the cart needs ${ms.toFixed(2)} ms a frame — that is under 60 fps`);
