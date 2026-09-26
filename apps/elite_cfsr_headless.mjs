// Headless ELITE / Challenge Foot Senior driver — boots the sealed machine the
// way docs/sealed-loader.js does, dumps composited frames as PPMs and checks the
// three things this screen is made of. Nothing here needs motion: the band is
// the SAME 16-row pattern ten times, inked by a per-scanline palette, with two
// colour-0 bars bracketing it — and the lower bar falls in the BOTTOM BORDER, so
// "did the border open" and "did the raster reach it" are one question.
//   bars     the LEFT BORDER on the five lines above the band and the five below
//            is BEAM_RASTERS1 / BEAM_RASTERS2, exactly
//   rasters  every visible band line carries RASTERS' word for its 8-line group
//   repeat   band line y and line y+16 are identical, all ten copies
//   node apps/elite_cfsr_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1; // one overscan plane: the ST drew this on one screen

// The scene's geometry, from apps/zig/scenes/elite_cfsr/ (which took it from the
// .PRG's own symbols). Physical row = 40 + line.
const TOP = 40, BAND_TOP = 44, BAND_ROWS = 16, REPEATS = 10, GROUP = 8;
// 38 and 201 MEASURED on real hardware (Hatari via shirazmcp, 2026-09-20),
// anchored on the logo's first scanline and read off the LEFT BORDER where
// colour 0 is unobstructed. 38 corrects a reconstruction of 39: the bar does
// NOT abut the band, line 43 is background.
const BAR1_TOP = 38, BAR2_TOP = 201;
const BEAM_RASTERS1 = [0x100, 0x411, 0x732, 0x765, 0x000];
const BEAM_RASTERS2 = [0x765, 0x732, 0x411, 0x100, 0x000];
const RASTERS = [
    0x011, 0x122, 0x011, 0x122, 0x233, 0x122, 0x233, 0x344, 0x233,
    0x344, 0x455, 0x344, 0x455, 0x566, 0x455, 0x566, 0x677, 0x566,
    0x677, 0x777, 0x677, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777,
    0x777, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777, 0x777,
    0x777, 0x677, 0x777, 0x677, 0x566, 0x677, 0x566, 0x455, 0x566,
    0x455, 0x344, 0x455, 0x344, 0x233, 0x344, 0x233, 0x122, 0x233,
    0x122, 0x011, 0x122, 0x011, 0x700, 0x011,
];

// Truncated, as elite_cfsr/assets.zig's stColor does.
const st = (v) => [(v >> 8) & 7, (v >> 4) & 7, v & 7].map((c) => Math.floor((c * 255) / 7));
async function boot(cart = "docs/demo-elite_cfsr.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;

    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(cart);
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            ...env0,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
            consoleLogJS: (p, l) => console.log("[wasm]", dec.decode(new Uint8Array(memory.buffer, p, l))),
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
            hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree, ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
            hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
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
        this.w = machine.hwPhysWidth(); // 800: the window is x-DOUBLED
        this.h = machine.hwPhysHeight(); // 280, borders and all
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        this.frames = 0;
        this.rgb = null;
    }

    // One host frame, as docs/sealed-loader.js sequences it. The per-scanline
    // palette only exists DURING a render (an HBL side effect), so every frame
    // is rendered, not just the ones that get looked at.
    run(n) {
        for (let i = 0; i < n; i++, this.frames++) {
            this.machine.hwClear();
            this.demo.frame(16.6);
            for (let p = 0; p < PLANES; p++) this.machine.hwRenderPlane(p);
        }
        this.rgb = this.compose();
    }

    // The 400x280 physical frame, un-doubled, 3 bytes a pixel.
    compose() {
        const half = this.w / 2;
        const out = new Uint8Array(half * this.h * 3);
        for (let y = 0; y < this.h; y++) {
            for (let x = 0; x < half; x++) {
                const i = (y * this.w + x * 2) * 4;
                const a = this.pfb[i + 3] / 255;
                const o = (y * half + x) * 3;
                for (let c = 0; c < 3; c++) out[o + c] = Math.round(this.pfb[i + c] * a);
            }
        }
        return out;
    }

    px(x, y) {
        const o = (y * 400 + x) * 3;
        return [this.rgb[o], this.rgb[o + 1], this.rgb[o + 2]];
    }
    async shot(path) {
        const hdr = new TextEncoder().encode(`P6\n400 ${this.h}\n255\n`);
        const out = new Uint8Array(hdr.length + this.rgb.length);
        out.set(hdr);
        out.set(this.rgb, hdr.length);
        await writeFile(path, out);
        console.log(`  shot: ${path} (frame ${this.frames})`);
    }
}

const same = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

// Colour 0 is the background AND the border, so the side border shows the raster
// register with nothing drawn over it. The bottom bar starts at line 201, past
// the 200-line screen: if the border never opened, those rows are black.
function checkBars(s) {
    for (const [top, table, name] of [[BAR1_TOP, BEAM_RASTERS1, "top"], [BAR2_TOP, BEAM_RASTERS2, "bottom"]]) {
        for (let i = 0; i < table.length; i++) {
            const want = st(table[i]), got = s.px(3, TOP + top + i);
            if (!same(got, want)) throw new Error(`${name} bar line ${top + i}: border ${got}, want ${want}`);
        }
    }
    console.log("  bars: BEAM_RASTERS1 and BEAM_RASTERS2 exact, bottom bar in the open border");
}

// Every visible band line's ink is its 8-line group's RASTERS word: base on
// lines 0..5 of the group, the accent on 6, base again on 7.
function checkRasterGroups(s) {
    let checked = 0;
    for (let line = BAND_TOP; line < 200; line++) {
        const off = line - BAND_TOP;
        const g = Math.floor(off / GROUP), rel = off % GROUP;
        const want = st(RASTERS[3 * g + (rel === 6 ? 1 : rel === 7 ? 2 : 0)]);
        // The ink only shows where the scroller set a pixel; find one.
        let found = false;
        for (let x = 0; x < 320 && !found; x++) {
            const got = s.px(40 + x, TOP + line);
            if (got[0] || got[1] || got[2]) {
                if (!same(got, want)) throw new Error(`band line ${line}: ink ${got}, RASTERS says ${want}`);
                found = true;
            }
        }
        if (found) checked++;
    }
    if (checked < 120) throw new Error(`only ${checked} band lines had ink — the scroller is not drawing`);
    console.log(`  rasters: ${checked} band lines carry their own RASTERS group value`);
}

// COPY_XOR_BUFFER writes the same 16 rows ten times, 16 lines apart.
function checkRepeat(s) {
    for (let r = 0; r < BAND_ROWS; r++) {
        for (let k = 1; k < REPEATS; k++) {
            const a = BAND_TOP + r, b = BAND_TOP + k * BAND_ROWS + r;
            if (b >= 200) continue;
            const lit = (x, y) => (s.px(40 + x, TOP + y).some((c) => c) ? 1 : 0);
            for (let x = 0; x < 320; x++) {
                if (lit(x, a) !== lit(x, b)) throw new Error(`repeat ${k}: line ${b} != line ${a} at x=${x}`);
            }
        }
    }
    console.log(`  repeat: all ${REPEATS} copies of the 16-row pattern agree`);
}

const out = process.argv[2] || "/tmp/elite_cfsr";
await mkdir(out, { recursive: true });
const screen = await boot();
screen.run(1);
await screen.shot(`${out}/00-first.ppm`); // logo + bars up, the text still empty
checkBars(screen);

screen.run(974); // the scrolltext reaches "Challenge Foot Senior!", the demozoo shot
await screen.shot(`${out}/01-challenge.ppm`);
checkBars(screen);
checkRasterGroups(screen);
checkRepeat(screen);

screen.run(2000);
await screen.shot(`${out}/02-soak.ppm`);
checkBars(screen);
checkRasterGroups(screen);

// Soak: 299 characters at 2 pixels a frame, and a 512-frame YSIN walk.
const t0 = performance.now();
screen.run(4000);
console.log(`  soak: ${screen.frames} frames clean, ` +
    `${((performance.now() - t0) / 4000).toFixed(2)} ms/frame (update + render + 1 plane composite)`);
