// Headless GEM driver — boots the sealed machine + demo-gem.wasm exactly the way
// docs/sealed-loader.js does (one shared 79-page memory, machine exports wired
// into the demo's imports), then drives the pointer frame by frame and dumps the
// composited screen as a PPM.
//
// Why this exists: claude-in-chrome collapses a drag into ~1 frame, so the
// multi-frame gestures GEM is built on (icon drags, window moves, rubber-band)
// could only ever be spot-checked by hand in a foreground browser. Here a drag is
// just N pointer() calls, so drag-driven regressions are reproducible and cheap.
//
//   node apps/gem_headless.mjs [outdir]   # runs the scenarios below
//
// Coordinates are PHYSICAL-VISIBLE (0..639 x, 0..199 y), the same frame the loader
// sends; GEM halves x itself for its 320-wide low-res logical screen.
import { readFile, writeFile } from "node:fs/promises";
import { cartRam } from "../docs/wasm_hiwater.js";

const PAGES = 79; // must match SHARED_PAGES in machine/sdk/memmap.zig
const DBLCLICK = 2; // pointer buttons bit 1 = the loader's synthesised double-click

export async function bootGem() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let demo;
    const machineImports = {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    };
    const machine = (await WebAssembly.instantiate(
        await readFile("docs/machine-video.wasm"), machineImports)).instance.exports;

    const noop = () => {};
    const demoImports = {
        env: {
            memory,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
            consoleLogJS: (p, l) => console.log("[wasm]", dec.decode(new Uint8Array(memory.buffer, p, l))),
            hwVideoBase: machine.hwVideoBase,
            hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed,
            hwRamFree: machine.hwRamFree,
            // GEM touches none of these headlessly, but the import list must match.
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    };
    const cart = await readFile("docs/demo-gem.wasm");
    demo = (await WebAssembly.instantiate(cart, demoImports)).instance.exports;
    // Same declaration the browser loader makes, so hwRamFree() reports the real
    // numbers headlessly too (this harness is how a cart overrunning the window
    // gets caught before it reaches a browser).
    machine.hwSetCartHigh(cartRam(cart).high ?? 0);

    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    demo.insertDisk(1);
    return new Gem(memory, machine, demo);
}

// A booted GEM: pointer gestures in, screenshots out.
class Gem {
    constructor(memory, machine, demo) {
        this.memory = memory;
        this.machine = machine;
        this.demo = demo;
        this.w = machine.hwPhysWidth();
        this.h = machine.hwPhysHeight();
        this.bx = machine.hwBorderX();
        this.by = machine.hwBorderY();
        this.vw = 640; // physical-visible screen inside the overscan borders
        this.vh = 200;
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        for (let i = 0; i < 30; i++) this.frame(); // let the desktop settle
    }

    frame() { this.demo.frame(16.6); }
    point(x, y, buttons) { this.demo.pointer(x, y, buttons); this.frame(); }
    click(x, y) { this.point(x, y, 0); this.point(x, y, 1); this.point(x, y, 0); }
    open(x, y) { this.point(x, y, 0); this.point(x, y, DBLCLICK); this.point(x, y, 0); }

    // A REAL multi-frame drag: press, N intermediate moves, release. This is the
    // gesture a browser automation harness cannot produce.
    drag(x0, y0, x1, y1, steps = 8) {
        this.point(x0, y0, 0);
        this.point(x0, y0, 1);
        for (let i = 1; i <= steps; i++)
            this.point(Math.round(x0 + (x1 - x0) * i / steps), Math.round(y0 + (y1 - y0) * i / steps), 1);
        this.point(x1, y1, 0);
    }

    // Hand GEM a FAT so its FLOPPY window has contents (mirrors sealed-loader.js).
    mount(files) {
        const ENT = 25; // 16 name + 1 type + 4 size + 4 date — must match FILE_ENT
        const enc = new TextEncoder();
        const dir = new Uint8Array(this.memory.buffer, this.demo.diskDirPtr(), files.length * ENT);
        dir.fill(0);
        const dv = new DataView(dir.buffer, dir.byteOffset, dir.byteLength);
        files.forEach(({ name, type, size, date }, i) => {
            dir.set(enc.encode(name).subarray(0, 16), i * ENT);
            dir[i * ENT + 16] = type;
            dv.setUint32(i * ENT + 17, size >>> 0, true);
            dv.setUint32(i * ENT + 21, (date || 0) >>> 0, true);
        });
        this.demo.setDiskFileCount(files.length);
        for (let i = 0; i < 5; i++) this.frame();
    }

    // Composite plane 0 and write the VISIBLE screen (borders cropped) as a PPM.
    async shot(path) {
        this.machine.hwRenderPlane(0);
        const hdr = new TextEncoder().encode(`P6\n${this.vw} ${this.vh}\n255\n`);
        const out = new Uint8Array(hdr.length + this.vw * this.vh * 3);
        out.set(hdr);
        for (let y = 0; y < this.vh; y++) {
            for (let x = 0; x < this.vw; x++) {
                const s = ((y + this.by) * this.w + x + this.bx) * 4;
                const d = hdr.length + (y * this.vw + x) * 3;
                out[d] = this.pfb[s];
                out[d + 1] = this.pfb[s + 1];
                out[d + 2] = this.pfb[s + 2];
            }
        }
        await writeFile(path, out);
        console.log("  shot:", path);
    }
}

// --- regression scenarios (each one guards a fixed bug) -------------------
const DISK = [
    { name: "ALPHA.PRG", type: 0, size: 12345, date: 20260912 },
    { name: "BETA.TXT", type: 1, size: 512, date: 20260912 },
    { name: "GAMMA.DAT", type: 1, size: 40960, date: 20260912 },
];
const FLOPPY = [70, 40]; // the FLOPPY desktop icon, physical-visible coords

const SCENARIOS = {
    // Dragging a desktop icon must leave the original in place and show a dotted
    // ghost whose label box is the full LABEL FIELD width, not the icon's width.
    "icon-drag-ghost": async (gem, out) => {
        gem.point(...FLOPPY, 0);
        gem.point(...FLOPPY, 1);
        gem.point(200, 80, 1);
        gem.point(380, 120, 1);
        await gem.shot(`${out}/icon-drag-ghost.ppm`);
        gem.point(380, 120, 0);
        gem.frame();
        await gem.shot(`${out}/icon-drag-dropped.ppm`);
    },
    // A window dragged off the right edge must be CUT: unclipped text used to wrap
    // onto the next scanline, spraying the title + icon labels across the desktop.
    "window-off-right": async (gem, out) => {
        gem.open(...FLOPPY);
        for (let i = 0; i < 10; i++) gem.frame();
        gem.drag(300, 30, 780, 30, 6);
        await gem.shot(`${out}/window-off-right.ppm`);
    },
    // Both INFORMATION dialogs must fit inside the 320-wide low-res screen.
    "show-info": async (gem, out) => {
        gem.click(...FLOPPY);
        gem.click(145, 8); // File
        gem.click(200, 23); // Show Info...
        for (let i = 0; i < 3; i++) gem.frame();
        await gem.shot(`${out}/disk-info.ppm`);
    },
};

if (import.meta.url === `file://${process.argv[1]}`) {
    const out = process.argv[2] || ".";
    for (const [name, run] of Object.entries(SCENARIOS)) {
        console.log(name);
        const gem = await bootGem();
        gem.mount(DISK);
        await run(gem, out);
    }
}
