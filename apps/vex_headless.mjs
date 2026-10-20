// Headless VEX 2025 driver — boots the sealed machine + demo-vex the way
// docs/sealed-loader.js does and dumps composited frames as PPMs.
//
// Why this exists: the screen is ONE plane whose lower 150 rows are recomposed
// every frame out of four bit layers, with a per-row palette installed from an
// HBL. "Is the scroller still on its wave, are the cubes still rolling, did the
// credits page wipe and come back?" are questions about frame N, which here is
// just a number. It also times the frame, since the recompose is per pixel.
//
// Two copies of the cart run in lockstep. The first stays in ORIGINAL mode and
// its shots are pinned by hash: that mode is the ST's screen and must not move.
// The second is switched into ZIG MODE with Z (both scrollers through the open
// side borders) and back, and is checked against the first on every frame.
//
//   node apps/vex_headless.mjs [outdir]
import { createHash } from "node:crypto";
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
        const hash = createHash("sha256").update(out).digest("hex").slice(0, 16);
        console.log(`  shot: ${path} (frame ${this.frames}, ${pct.toFixed(2)}% lit, ${hash})`);
        return hash;
    }
}


const out = process.argv[2] || "/tmp/vex";
await mkdir(out, { recursive: true });
const screen = await boot(); // ORIGINAL throughout: the pinned run
const zig = await boot();    // the same cart, switched with Z along the way

// ORIGINAL's frames, by hash. Taken before ZIG MODE existed (the plane was a
// plain 320x200 one then) and unchanged by it: if one of these moves, the
// faithful screen changed. Re-pin only for a deliberate change to the port.
const PINS = {
    "00-pretitle": "c15f6a4806e84681", "01-pretitle-lit": "a4ab479ec97e410b",
    "02-title-white": "a84c9f5272b5c652", "03-title": "e7241566737cc94f",
    "04-first": "f49ca607c5f85f33", "05-faded": "1d1f33e07cfd0362",
    "06-running": "c6fe3fc8ad93cee3", "07-mid-page": "75fca4c2853452c5",
    "08-wiping": "5a7624f71ab250d9", "09-page1": "152e89f3c34636b7",
    "10-page2": "288cd83b2ba5f0b0",
};
const fails = [];
async function shot(name, floor) {
    const hash = await screen.shot(`${out}/${name}.ppm`, floor);
    if (hash !== PINS[name]) fails.push(`${name}: ORIGINAL frame hash ${hash}, pinned ${PINS[name]}`);
}

// The rows ZIG MODE opens, derived the way the cart derives them: the big
// scroller's ink rows from wave.dat's range (scroller.zig INK_TOP/INK_END) and
// Metallinos' eight (planes.zig SMALL_TOP).
const wave = await readFile("apps/zig/assets/screens/vex/wave.dat");
const INK_TOP = 12 + Math.min(...wave), INK_END = 12 + Math.max(...wave) + 32;
const SMALL_TOP = 191, SMALL_END = 199;
const opened = (y) => (y >= INK_TOP && y < INK_END) || (y >= SMALL_TOP && y < SMALL_END);

// The PFB is the 800x280 raster (x doubled): the window is x 80..720, y 40..240.
const PW = 800, BX = 80, BY = 40;
const px = (s, x, y) => s.readUInt32LE((y * PW + x) * 4);
const ink = { big: [0, 0], small: [0, 0], edge: [0, 0] }; // [left, right] pixel counts
let requested = false; // Z pressed an odd number of times

// One frame of each. While ZIG MODE is off the two must be byte-identical, Z
// pending through the pre-title and title included (only the intro has
// scrollers). While it is on: the window is still identical, closed lines are
// identical, and an opened line's border shows only the ORIGINAL's border
// colour or ONE other (the scroller's ink) -- a missed flicker paints noise
// out of the whole palette, which this rejects.
function lockstep(n) {
    for (let i = 0; i < n; i++) {
        screen.run(1);
        zig.run(1);
        const a = Buffer.from(screen.snaps[0].buffer), b = Buffer.from(zig.snaps[0].buffer);
        const f = screen.frames;
        if (!requested) {
            if (!a.equals(b)) throw new Error(`frame ${f}: ORIGINAL mode differs from the never-switched run`);
            continue;
        }
        for (let y = 0; y < zig.h; y++) {
            const row = y * PW * 4;
            if (a.compare(b, row + BX * 4, row + (PW - BX) * 4, row + BX * 4, row + (PW - BX) * 4) !== 0)
                throw new Error(`frame ${f}: ZIG MODE changed the window on raster line ${y}`);
            const wy = y - BY, open = wy >= 0 && wy < 200 && opened(wy);
            let other = null;
            for (let x = 0; x < PW; x += 2) {
                if (x === BX) x = PW - BX;
                const pa = px(a, x, y), pb = px(b, x, y);
                if (pa === pb) continue;
                if (!open) throw new Error(`frame ${f}: raster line ${y} x ${x / 2} drawn in a border ZIG MODE never opens`);
                if (other !== null && pb !== other) throw new Error(`frame ${f}: raster line ${y} border shows garbage (a missed flicker): x ${x / 2} ${pb.toString(16)} vs ${other.toString(16)}, ORIGINAL ${pa.toString(16)}`);
                other = pb;
                const side = x < BX ? 0 : 1;
                (wy >= SMALL_TOP ? ink.small : ink.big)[side]++;
                if (x < 16 || x >= PW - 16) ink.edge[side]++;
            }
        }
    }
}
function press() {
    zig.demo.key("Z".charCodeAt(0));
    requested = !requested;
}

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

lockstep(1);
await shot("00-pretitle");    // page 1 up, white surround behind it
lockstep(9);
press();                      // Z during the pre-title: held until the intro
lockstep(111);
await shot("01-pretitle-lit"); // still page 1, ink faded up
lockstep(PRETITLE - 121 + 1); // one past the handover, inside the white
await shot("02-title-white"); // $80a's white, before the fade
lockstep(59);
await shot("03-title");       // 60: the V has resolved out of it
lockstep(TITLE - 60);
await shot("04-first");       // PRETITLE+TITLE: the handover, the intro's own first
lockstep(59);
await shot("05-faded");       // +60: the 21-word crossfade has landed
lockstep(240);
await shot("06-running");     // scroller on its wave, cubes rolling
await zig.shot(`${out}/zig-06-running.ppm`); // ...and through the open borders
lockstep(700);
await shot("07-mid-page");    // still page 0, deep into the 1000-frame hold
press();                      // back to ORIGINAL: identical from the next frame
lockstep(360);
await shot("08-wiping");      // intro 1060: the panel erases a line a frame
press();                      // ZIG again: the side words start from blank
lockstep(180);
await shot("09-page1");       // intro 1240: page 1 is back
await zig.shot(`${out}/zig-09-page1.ppm`);
press();
lockstep(1240);
await shot("10-page2");

const need = 50; // a few columns' worth: each side, each scroller, and the raster's very edge
for (const [what, [l, r]] of Object.entries(ink)) {
    console.log(`  zig: ${what} ink in the side borders: left ${l} px, right ${r} px`);
    if (l < need || r < need) fails.push(`ZIG MODE: the ${what} ink does not reach both side borders (${l} / ${r} px)`);
}

const t0 = performance.now();
screen.run(3000);
console.log(`  soak: ${screen.frames} frames clean, ` +
    `${((performance.now() - t0) / 3000).toFixed(2)} ms/frame (update + render + 1 plane composite)`);
press();
const t1 = performance.now();
zig.run(3000);
console.log(`  soak: ZIG MODE ${((performance.now() - t1) / 3000).toFixed(2)} ms/frame`);
// The layers and the credit pages come from zg.mem, once per cart load.
for (const s of [screen, zig]) {
    const refused = s.machine.hwRamAllocFailures();
    if (refused) fails.push(`${refused} zg.mem allocation(s) refused`);
}
if (fails.length) {
    for (const f of fails) console.log(`vex: FAILED -- ${f}`);
    process.exit(1);
}
console.log("vex: OK -- ORIGINAL pinned on 11 frames, ZIG MODE checked on every frame it ran");
