// Headless TLB / Twiddle Demo driver — boots the sealed machine +
// demo-tlb_spoon.wasm the way docs/sealed-loader.js does and dumps PPMs of the
// 320x200 screen, one per phase.
//
// The screen has ONE plane and no open borders, so this crops the physical
// 800x280 framebuffer back to the visible window: it sits at (80, 40) with x
// DOUBLED, hence the /2 below. hwRenderPlane OVERWRITES the shared physical
// framebuffer, so the plane is rendered and read in the same breath.
//
//   node apps/tlb_spoon_headless.mjs [outdir] [--break]
//
// THE PIN: after the shots, a fresh boot runs to PIN_FRAMES and SHA-256es the
// composed 320x200 picture at each one (intro, the switch, early main, deep
// main), against the hashes of the fixed-point picture. Any change to what the
// screen shows fails it. `--break` runs ONE extra frame first and passes only
// if the pin catches it, so the pin itself is proved not blind.
//
// 2026-10-24: the letters are sampled in fixed point (no per-frame float on ZIGGY);
// edge pixels may differ by 1 px from the old f32 sampling. (The starballs are
// projected in fixed point too.) This driver pins no hash or pixel value, so
// nothing here needed re-pinning: it dumps the phase shots for a person to look at.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig

async function boot(cart = "docs/demo-tlb_spoon.wasm") {
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
        this.w = machine.hwPhysWidth();
        this.h = machine.hwPhysHeight();
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        this.frames = 0;
    }

    run(n) {
        for (let i = 0; i < n; i++) this.demo.frame(16.6);
        this.frames += n;
    }

    async shot(path) {
        this.machine.hwClear();
        this.machine.hwRenderPlane(0);
        const acc = new Uint8Array(320 * 200 * 3);
        for (let y = 0; y < 200; y++) {
            for (let x = 0; x < 320; x++) {
                const src = ((y + 40) * this.w + 80 + x * 2) * 4;
                const dst = (y * 320 + x) * 3;
                for (let c = 0; c < 3; c++) acc[dst + c] = this.pfb[src + c];
            }
        }
        const hdr = new TextEncoder().encode(`P6\n320 200\n255\n`);
        const out = new Uint8Array(hdr.length + acc.length);
        out.set(hdr);
        out.set(acc, hdr.length);
        await writeFile(path, out);
        console.log(`  shot: ${path} (screen.js counter ${this.frames - 1})`);
    }
}

// INTRO_TEXT is 125 chars, so the sine scroller runs counter 0..1329 and the
// starball/logo/scroller part starts at counter 1330 (screen.js:203). run(n)
// leaves the screen showing counter n-1, so each total below is one more than
// the CODEF frame it is checked against.
const args = process.argv.slice(2);
const BREAK = args.includes("--break");
const out = args.find((a) => !a.startsWith("--")) || "/tmp/tlb_spoon";
await mkdir(out, { recursive: true });
const screen = await boot();
screen.run(1);
await screen.shot(`${out}/00-intro-first.ppm`);
screen.run(200);
await screen.shot(`${out}/01-intro.ppm`); // frame 200: the wave well into the text
screen.run(1200);
await screen.shot(`${out}/02-main-open.ppm`); // frame 1400: 70 frames into the main part
screen.run(120);
await screen.shot(`${out}/03-main-early.ppm`);
screen.run(100);
await screen.shot(`${out}/04-main.ppm`);
screen.run(480);
await screen.shot(`${out}/05-main-late.ppm`);

// ---- the pin --------------------------------------------------------------
// run(n) leaves counter n-1 on screen: these are frames 599, 1299 (intro, 30
// before the switch), 1339 (just after), 2399, 9999 and 49999. Pinned 2026-10-24
// on the fixed-point picture (perf/tlb_spoon-fixed).
const PINS = [
    [600, "6afb71128df564c1"],
    [1300, "ea6d444f72d45d26"],
    [1340, "a822d94285fba1fa"],
    [2400, "97cb69f2b2679821"],
    [10000, "4799caf8fc21277e"],
    [50000, "bee528e6ecd326bb"],
];
function pictureHash(s) {
    s.machine.hwClear();
    s.machine.hwRenderPlane(0);
    const h = createHash("sha256");
    for (let y = 0; y < 200; y++) {
        const row = ((y + 40) * s.w + 80) * 4;
        for (let x = 0; x < 320; x++) h.update(s.pfb.subarray(row + x * 8, row + x * 8 + 3));
    }
    return h.digest("hex").slice(0, 16);
}
const pin = await boot();
if (BREAK) pin.demo.frame(16.6); // one uncounted extra frame: the perturbation the pin must catch
let bad = 0;
for (const [frame, want] of PINS) {
    pin.run(frame - pin.frames);
    const got = pictureHash(pin);
    const ok = got === want;
    if (!ok) bad++;
    console.log(`  pin ${ok ? "ok  " : "DIFF"} frame ${frame}: ${got}${ok ? "" : ` (want ${want})`}`);
}
if (BREAK) {
    if (bad === 0) { console.log("FAIL --break: one extra frame and the pin did not notice"); process.exit(1); }
    console.log(`PASS --break: the pin caught the extra frame (${bad} of ${PINS.length} differ, as they must)`);
} else {
    if (bad) { console.log(`FAIL: ${bad} of ${PINS.length} pinned pictures changed`); process.exit(1); }
    console.log(`PASS: all ${PINS.length} pinned pictures match`);
}
