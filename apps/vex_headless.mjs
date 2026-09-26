// Headless VEX 2025 driver — boots the sealed machine + demo-vex the way
// docs/sealed-loader.js does and dumps composited frames as PPMs.
//
// Why this exists: the screen is ONE plane whose lower 150 rows are recomposed
// every frame out of four bit layers, with a per-row palette installed from an
// HBL. "Is the scroller still on its wave, are the cubes still rolling, did the
// credits page wipe and come back?" are questions about frame N, which here is
// just a number. It also times the frame, since the recompose is per pixel.
//
//   node apps/vex_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1;  // the whole intro is one 16-colour plane, as the ST screen was

async function boot(cart = "docs/demo-vex.wasm") {
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
        this.frames = 0;
        this.snaps = [];
    }

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
            this.snaps = [];
            for (let p = 0; p < PLANES; p++) {
                this.machine.hwRenderPlane(p);
                this.snaps.push(this.pfb.slice());
            }
        }
    }

    // `floor` is the minimum lit percentage this frame must reach. The default
    // suits every screen here: the pre-title is mostly WHITE surround (~73%),
    // the title a full-screen picture, the intro always busy. Pass a lower one
    // only for a frame that is sparse by design, and say why.
    async shot(path, floor = 4) {
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
        // VEX's body is black by design, so "not dark" is the wrong guard here:
        // what must never happen is the visible band going EMPTY (a layer that
        // stopped drawing, or a palette left at zero). Count lit pixels in the
        // 320x200 window instead — a good frame runs 12-30%.
        let lit = 0;
        for (let y = 40; y < 240; y++) {
            for (let x = 40; x < 200; x++) {
                const o = hdr.length + (y * half + x) * 3;
                if (Math.max(out[o], out[o + 1], out[o + 2]) >= 40) lit++;
            }
        }
        const pct = (100 * lit) / (200 * 160);
        if (pct < floor) throw new Error(`${path}: only ${pct.toFixed(2)}% of the screen is lit (floor ${floor}%) — a layer stopped drawing`);
        console.log(`  shot: ${path} (frame ${this.frames}, ${pct.toFixed(2)}% lit)`);
    }
}

const out = process.argv[2] || "/tmp/vex";
await mkdir(out, { recursive: true });
const screen = await boot();

// Two screens run before the intro proper, and every shot below is offset past
// them so the names keep meaning what they say — without the offset the shots
// land on a white flash and still pass the lit test.
//   PRETITLE  $b5b8's script: three pages of 8x8 text. This is the frame the
//             script HANDS OVER on, which is NOT the 850 the delays sum to: a
//             frame that drains a delay to zero does not also run the next
//             record, so each of the 13 non-zero delays costs one frame more.
//             Simulate intro_script.dat rather than re-deriving it by hand.
//   TITLE     the V picture: out of white, hold, white again at 250, hand over
//             at 300 ($12c)
const PRETITLE = 865;
const TITLE = 300;

screen.run(1);
await screen.shot(`${out}/00-pretitle.ppm`);    // page 1 up, white surround behind it
screen.run(120);
await screen.shot(`${out}/01-pretitle-lit.ppm`); // still page 1, ink faded up
screen.run(PRETITLE - 121 + 1); // one past the handover, inside the white
await screen.shot(`${out}/02-title-white.ppm`); // $80a's white, before the fade
screen.run(59);
await screen.shot(`${out}/03-title.ppm`);       // 60: the V has resolved out of it
screen.run(TITLE - 60);
await screen.shot(`${out}/04-first.ppm`);       // PRETITLE+TITLE: the handover, the intro's own first
screen.run(59);
await screen.shot(`${out}/05-faded.ppm`);       // +60: the 21-word crossfade has landed
screen.run(240);
await screen.shot(`${out}/06-running.ppm`);     // scroller on its wave, cubes rolling
screen.run(700);
await screen.shot(`${out}/07-mid-page.ppm`);    // still page 0, deep into the 1000-frame hold
screen.run(360);
await screen.shot(`${out}/08-wiping.ppm`);      // intro 1060: the panel erases a line a frame
screen.run(180);
await screen.shot(`${out}/09-page1.ppm`);       // intro 1240: page 1 is back
screen.run(1240);
await screen.shot(`${out}/10-page2.ppm`);

const t0 = performance.now();
screen.run(3000);
console.log(`  soak: ${screen.frames} frames clean, ` +
    `${((performance.now() - t0) / 3000).toFixed(2)} ms/frame (update + render + 1 plane composite)`);
