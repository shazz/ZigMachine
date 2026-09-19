// Headless AUTOMATION 442 driver — boots the sealed machine + demo-automation442.wasm
// the way docs/sealed-loader.js does, and dumps composited PPMs of the WHOLE
// physical screen (800x280): BOTH planes are overscan, so cropping to 320x200
// would hide half of what this port is about — including the scroller running
// out through the side borders.
//
// hwRenderPlane(p) OVERWRITES the shared physical framebuffer (the host blits one
// plane per canvas), so this snapshots the PFB after EACH plane and alpha-blends
// the snapshots itself, bottom plane first. Rendering both and reading the PFB
// once would show only the near-empty text plane.
//
//   node apps/automation442_headless.mjs [outdir]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 2; // 0 = panned overscan skull, 1 = overscan scrolltext

async function boot(cart = "docs/demo-automation442.wasm") {
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
        const px = this.w * this.h;
        const acc = new Uint8Array(px * 3);
        // Same order as the host: background fill first, then the planes bottom-up.
        // Both planes here cover all 800x280 opaquely, so the fill never shows —
        // but without it a plane that left a pixel untouched would snapshot the
        // PREVIOUS shot's pixel instead of the machine background.
        this.machine.hwClear();
        for (let p = 0; p < PLANES; p++) {
            this.machine.hwRenderPlane(p);
            const snap = this.pfb.slice(); // the next plane overwrites the PFB
            for (let i = 0; i < px; i++) {
                const a = snap[i * 4 + 3];
                if (a === 0) continue;
                for (let c = 0; c < 3; c++) {
                    acc[i * 3 + c] = a === 255
                        ? snap[i * 4 + c]
                        : (snap[i * 4 + c] * a + acc[i * 3 + c] * (255 - a)) / 255 | 0;
                }
            }
        }
        const hdr = new TextEncoder().encode(`P6\n${this.w} ${this.h}\n255\n`);
        const out = new Uint8Array(hdr.length + acc.length);
        out.set(hdr);
        out.set(acc, hdr.length);
        await writeFile(path, out);
        console.log(`  shot: ${path} (frame ${this.frames})`);
    }
}

// piracy_move()'s cycle, in frames: 1..40 pan left, 41..187 scroll down,
// 188..227 pan back, 228..374 scroll down, 376 resets bgcount. The vertical legs
// wrap on the artwork's own 187-row period, so 04 must show no seam.
const out = process.argv[2] || "/tmp/automation442";
await mkdir(out, { recursive: true });
const screen = await boot();
await screen.shot(`${out}/00-boot.ppm`);
screen.run(40);
await screen.shot(`${out}/01-panned-left.ppm`); // one full tile width travelled
screen.run(60);
await screen.shot(`${out}/02-scrolling-down.ppm`);
screen.run(128); // to frame 228: pan-back finished
await screen.shot(`${out}/03-panned-back.ppm`);
screen.run(148); // to frame 376: bgcount wraps
await screen.shot(`${out}/04-cycle-end.ppm`);
