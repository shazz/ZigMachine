// Headless TLB / Twiddle Demo driver — boots the sealed machine +
// demo-tlb_spoon.wasm the way docs/sealed-loader.js does and dumps PPMs of the
// 320x200 screen, one per phase.
//
// The screen has ONE plane and no open borders, so this crops the physical
// 800x280 framebuffer back to the visible window: it sits at (80, 40) with x
// DOUBLED, hence the /2 below. hwRenderPlane OVERWRITES the shared physical
// framebuffer, so the plane is rendered and read in the same breath.
//
//   node apps/tlb_spoon_headless.mjs [outdir]
import { readFile, writeFile, mkdir } from "node:fs/promises";
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
const out = process.argv[2] || "/tmp/tlb_spoon";
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
