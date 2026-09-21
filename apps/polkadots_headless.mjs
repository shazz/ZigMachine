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
// FOUR MODES. The screen is a bench: the same intensity grid drawn four ways,
// picked with demo.setShadeMode(0..3). This harness renders every one of them,
// proves each draws a DIFFERENT picture, reads the op count the cart wrote into
// its 24-pixel binary tap (readout.zig) rather than trusting the label, and
// times each mode separately — the comparison table at the end is the point of
// the screen.
//
//   node apps/polkadots_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1; // the whole screen is one plane, as the original is one canvas
const CELL = 7;
const zgWidth = 320;
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
        // The readout sits along the bottom row of the screen and paints over
        // the last row of cells, so that row cannot be counted from pixels.
        for (let cy = 0; cy < CELLS_Y - 1; cy++) {
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

    // The cart's own count, read out of the 24-pixel binary tap in the last
    // row: 8 bits of mode, then 16 bits of blitter operations, LSB first, in an
    // ink that is (0,0,1) — black on screen, a 1 here.
    tap() {
        let bits = 0;
        for (let b = 0; b < 24; b++) {
            const [, , blue] = this.rgb(zgWidth - 24 + b, 199);
            if (blue > 0.5) bits |= 1 << b;
        }
        return { mode: bits & 0xFF, ops: bits >>> 8 };
    }

    mode(n) {
        if (!this.demo.setShadeMode(n)) throw new Error(`setShadeMode(${n}) was not accepted by the cart`);
    }

    // Fingerprint of the PICTURE only, above the readout, so two modes are
    // judged different by what they drew and not by their label.
    picture() {
        let h = 0x811c9dc5;
        for (let ly = 0; ly < 190; ly += 3) {
            for (let lx = 0; lx < 320; lx += 3) {
                const [r, g, b] = this.rgb(lx, ly);
                h = Math.imul(h ^ ((r | 0) + (g | 0) * 7 + (b | 0) * 13), 0x01000193) >>> 0;
            }
        }
        return h;
    }

    async shot(path, withCensus = false) {
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
        if (!withCensus) {
            console.log(`  shot: ${path} (frame ${this.frames}, ${this.tap().ops} ops)`);
            return 0;
        }
        // Only MODE 1 draws an opaque 7x7 tile per cell, so only there does the
        // picture spell out the blit count and the distribution of dot sizes.
        const { blits, sizes } = this.census();
        if (blits < 100) throw new Error(`${path}: only ${blits} cells stamped — the torus is missing or tiny`);
        if (blits > 700) throw new Error(`${path}: ${blits} cells stamped — the torus has lost its hole or is drawing the whole grid`);
        if (sizes.slice(6).reduce((a, b) => a + b, 0) === 0) {
            throw new Error(`${path}: no bright dots — the directional light is not reaching any face`);
        }
        // The tap is the cart's own count over ALL cell rows; the census can
        // only see the rows the readout does not cover, so it is a lower bound
        // that may miss at most one row of cells.
        const { mode, ops } = this.tap();
        if (mode !== 0) throw new Error(`${path}: the tap says mode ${mode}, expected 0`);
        if (ops < blits || ops > blits + CELLS_X) {
            throw new Error(`${path}: the cart claims ${ops} blits, the picture shows ${blits} in the rows it can see`);
        }
        console.log(`  shot: ${path} (frame ${this.frames}, ${ops} blits, sizes ${sizes.join("/")})`);
        return blits;
    }
}

// Ink pixels per 7x7 tile, measured on pat.raw: the dot grows 0, 1, 5, 9, 13,
// 17, 25, 37, 45, 49 — the halftone ramp itself.
const TILE_OF_INK = new Map([[0, 0], [1, 1], [5, 2], [9, 3], [13, 4], [17, 5], [25, 6], [37, 7], [45, 8], [49, 9]]);

const out = process.argv[2] || "/tmp/polkadots";
await mkdir(out, { recursive: true });
const screen = await boot();

// --- MODE 1, the port itself: the picture is checked against the original ---
screen.run(1);
let peak = await screen.shot(`${out}/00-first.ppm`, true);     // rotation (0.02, 0.04): the ring near face-on
screen.run(24);
peak = Math.max(peak, await screen.shot(`${out}/01-quarter.ppm`, true)); // y has turned a radian
screen.run(55);
peak = Math.max(peak, await screen.shot(`${out}/02-edge.ppm`, true));    // the tube seen close to edge-on
screen.run(79);
peak = Math.max(peak, await screen.shot(`${out}/03-back.ppm`, true));

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

// --- THE BENCH: the same grid, four renderers, measured against each other ---
// The modes are INTERLEAVED, one frame each, round after round: the torus turns
// by a single step between them, so the four figures describe the same picture
// instead of four different moments of the rotation. Timing each of those
// frames separately keeps the CPU half (project + shade) in all four figures —
// which is right, because it is the part that does NOT change.
const NAMES = ["DOT SIZE", "HALFTONE", "SOLID", "FILL DOTS"];
const ROUNDS = 40;
const bench = NAMES.map((name) => ({ name, ops: 0, px: 0, ms: 0 }));
const seen = new Map();
for (let round = 0; round < ROUNDS; round++) {
    for (let m = 0; m < NAMES.length; m++) {
        screen.mode(m);
        const a = screen.cart_ms;
        screen.run(1);
        bench[m].ms += screen.cart_ms - a;
        const { mode, ops } = screen.tap();
        if (mode !== m) throw new Error(`mode ${m}: the cart's tap says ${mode} — setShadeMode did not take`);
        if (ops < 20) throw new Error(`mode ${m} (${NAMES[m]}): only ${ops} blitter ops — it is drawing nothing`);
        bench[m].ops += ops;
        if (round > 0) continue;
        await screen.shot(`${out}/1${m}-mode${m + 1}-${NAMES[m].toLowerCase().replace(" ", "")}.ppm`);
        const pic = screen.picture();
        if (seen.has(pic)) throw new Error(`mode ${m} (${NAMES[m]}) draws the same picture as mode ${seen.get(pic)}`);
        seen.set(pic, m);
    }
}

console.log("  bench (the same torus, drawn four ways, averaged over " + ROUNDS + " rounds):");
for (const [i, b] of bench.entries()) {
    b.ops /= ROUNDS;
    b.ms /= ROUNDS;
    console.log(`    ${i + 1} ${b.name.padEnd(10)} ${b.ops.toFixed(0).padStart(4)} blitter ops  ${b.ms.toFixed(3)} ms/frame`);
    if (b.ms > 16.6) throw new Error(`mode ${i + 1} (${b.name}) needs ${b.ms.toFixed(2)} ms a frame — under 60 fps`);
}

// The teaching claim, asserted rather than left to the prose: the halftone
// register shades a whole RUN of equal cells in one FILL, so it costs far fewer
// operations than one dot-sheet blit per cell — and cannot vary the dot.
const [dot, half, solid, fills] = bench;
if (!(half.ops < dot.ops / 2)) {
    throw new Error(`HALFTONE issued ${half.ops} ops against DOT SIZE's ${dot.ops}: the run collapsing is not working`);
}
if (half.ops > solid.ops) throw new Error("HALFTONE should never issue more fills than SOLID: they share the same runs");
if (fills.ops > dot.ops) throw new Error("FILL DOTS should never issue more ops than DOT SIZE: both are one op per lit cell");
console.log(`  claim: HALFTONE covers the grid in ${half.ops.toFixed(0)} fills where DOT SIZE needs ${dot.ops.toFixed(0)} blits ` +
    `(${(dot.ops / half.ops).toFixed(1)}x fewer operations)`);
