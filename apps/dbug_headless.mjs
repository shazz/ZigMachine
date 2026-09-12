// Headless D-BUG driver — boots the sealed machine + demo-dbug.wasm the way
// docs/sealed-loader.js does, runs it for a given number of frames and dumps the
// composited screen as a PPM.
//
// Why this exists: the credit panel writes itself one cell per frame over ~10
// seconds, so "does it still animate?" is otherwise a question you can only
// answer by watching a browser. Here a moment in the animation is just a frame
// count, and the PPMs are diffable.
//
//   node apps/dbug_headless.mjs [outdir]
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 2; // the screen composites the overscan scroller + the credit panel

async function boot(cart = "docs/demo-dbug.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;

    // machine -> rom -> cart, each importing only from the ones before it, the
    // same chain sealed-loader.js builds.
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
            ...rom, // the ROM chip's flat ABI
            // The screen touches none of these, but the import list must match.
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);

    machine.hwInit();
    demo.boot();
    demo.skipBoot(); // otherwise the boot ROM owns the first 180 frames
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

    // Composite every plane and write the WHOLE physical screen, borders and all
    // — the opened borders are half the point of this screen.
    async shot(path) {
        for (let p = 0; p < PLANES; p++) this.machine.hwRenderPlane(p);
        const hdr = new TextEncoder().encode(`P6\n${this.w} ${this.h}\n255\n`);
        const out = new Uint8Array(hdr.length + this.w * this.h * 3);
        out.set(hdr);
        for (let i = 0; i < this.w * this.h; i++) {
            out[hdr.length + i * 3] = this.pfb[i * 4];
            out[hdr.length + i * 3 + 1] = this.pfb[i * 4 + 1];
            out[hdr.length + i * 3 + 2] = this.pfb[i * 4 + 2];
        }
        await writeFile(path, out);
        console.log(`  shot: ${path} (frame ${this.frames})`);
    }
}

// The credit panel's own clock: 240 cells at one per frame, then a 100-frame
// hold, then 240 more to erase it (see libs/zig/effects/charpanel.zig).
const WRITE = 241, HOLD = 100, ERASE = 241;

const out = process.argv[2] || "/tmp/dbug";
const screen = await boot();
await screen.shot(`${out}/00-boot.ppm`);
screen.run(60);
await screen.shot(`${out}/01-writing.ppm`); // "PRESENTS" part-written
screen.run(WRITE - 60);
await screen.shot(`${out}/02-written.ppm`); // whole panel standing
screen.run(HOLD + 60);
await screen.shot(`${out}/03-erasing.ppm`); // part-erased, next pattern
screen.run(ERASE - 60 + 120);
await screen.shot(`${out}/04-second-text.ppm`); // "PRINCE OF PERSIA" arriving
