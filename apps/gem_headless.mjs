// Headless GEM driver — boots the sealed machine + demo-gem.wasm exactly the way
// docs/sealed-loader.js does (one shared SHARED_PAGES-page memory, machine exports wired
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
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const DBLCLICK = 2; // pointer buttons bit 1 = the loader's synthesised double-click

export async function bootGem() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    // A HOLDER, not a plain `let`: the machine's hblDispatch import is wired once at
    // instantiation and lives for the whole session, but the cart underneath it is
    // replaced on every launch (step 2.3b). Closing over a variable the swap
    // reassigns would keep routing raster interrupts into the cart that just left.
    const live = { demo: null };
    const machineImports = {
        env: { memory, hblDispatch: (id, p, l, x) => live.demo.hblDispatch(id, p, l, x) },
    };
    let demo;
    const machine = (await WebAssembly.instantiate(
        await readFile("docs/machine-video.wasm"), machineImports)).instance.exports;

    // The ROM chip, wired exactly as sealed-loader.js does it: machine -> rom ->
    // cart, each importing only from the ones before it.
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);

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
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree,
            ...rom, // the ROM chip's flat ABI
            // GEM touches none of these headlessly, but the import list must match.
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop,
            hostAudioStreamStop: noop,
        },
    };
    const gemBytes = await readFile("docs/demo-gem.wasm");
    const cart = gemBytes;
    demo = (await WebAssembly.instantiate(cart, demoImports)).instance.exports;
    live.demo = demo;
    // Same declaration the browser loader makes, so hwRamFree() reports the real
    // numbers headlessly too (this harness is how a cart overrunning the window
    // gets caught before it reaches a browser).
    machine.hwSetCartHigh(cartRam(cart).high ?? 0);

    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    demo.insertDisk(1);
    return new Gem(memory, machine, demo, demoImports, gemBytes, live, rom);
}

// A booted GEM: pointer gestures in, screenshots out.
class Gem {
    constructor(memory, machine, demo, demoImports, gemBytes, live, rom) {
        this.memory = memory;
        this.machine = machine;
        this.demo = demo;
        this.demoImports = demoImports;
        this.gemBytes = gemBytes;
        this.live = live;     // the holder the machine's hblDispatch reads through
        this.rom = rom;
        this.programs = {};   // FAT name -> cart bytes, for the launch swap
        this.swaps = 0;       // how many times a program was actually run
        this.w = machine.hwPhysWidth();
        this.h = machine.hwPhysHeight();
        this.bx = machine.hwBorderX();
        this.by = machine.hwBorderY();
        this.vw = 640; // physical-visible screen inside the overscan borders
        this.vh = 200;
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        for (let i = 0; i < 30; i++) this.frame(); // let the desktop settle
    }

    // One frame, then SERVICE THE CART-SWAP PROTOCOL exactly as sealed-loader.js
    // does. Without this the harness cannot launch anything: since step 2.3b a
    // program is a file on the disk that the HOST instantiates, so a harness that
    // only calls frame() tests a desktop that can never start an app.
    frame() {
        this.demo.frame(16.6);
        if (!this.demo.pollCartRequest) return;
        const req = this.demo.pollCartRequest();
        if (req === 3) this.runProgram();
        else if (req === 4) this.backToOs();
    }

    // req 3: run the named program off the "disk".
    runProgram() {
        const name = new TextDecoder().decode(new Uint8Array(
            this.memory.buffer, this.demo.getCartTagPtr(), this.demo.getCartTagLen()));
        const bytes = this.programs[name];
        if (!bytes) throw new Error(`GEM asked to run "${name}", which this harness has no bytes for`);
        this.swap(bytes);
        this.swaps++;
    }

    // req 4: back to the OS, disk still mounted.
    backToOs() {
        this.swap(this.gemBytes);
        this.demo.insertDisk(1);
        this.diskCache && this.mount(this.diskCache);
    }

    swap(bytes) {
        const mod = new WebAssembly.Module(bytes);
        this.demo = new WebAssembly.Instance(mod, this.demoImports).exports;
        this.live.demo = this.demo; // route the machine's HBL calls at the NEW cart
        this.rom.romReset();        // the outgoing program cannot free its own handles
        this.machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
        this.machine.hwInit();
        this.demo.boot();
        this.demo.skipBoot();
        for (let i = 0; i < 4; i++) this.demo.frame(16.6); // let it settle
    }
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
        this.diskCache = files;
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

    // A cheap fingerprint of the visible screen, for scenarios that assert
    // "something changed" rather than eyeballing a PPM.
    hash() {
        this.machine.hwRenderPlane(0);
        let h = 0x811c9dc5;
        for (let y = 0; y < this.vh; y++) {
            for (let x = 0; x < this.vw; x += 3) {
                const s = ((y + this.by) * this.w + x + this.bx) * 4;
                h = Math.imul(h ^ this.pfb[s], 0x01000193) >>> 0;
            }
        }
        return h;
    }

    key(cp) { this.demo.key(cp); this.frame(); }

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
// The first file icon inside an opened FLOPPY window (measured off a headless
// shot: the icon box is x 48..104, y 54..84).
const FIRST_FILE = [75, 66];
// A folder made with New Folder lands in the 4th cell of the root window's row.
const COPY_FOLDER = [507, 66];

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
    // A modal dialog owns the menu bar. The COPY box (a file dropped on a folder)
    // was missing from the menu bar's copy of the modal list, so hovering a menu
    // title dropped the menu down OVER the open dialog.
    "copy-locks-menu": async (gem, out) => {
        gem.open(...FLOPPY);
        for (let i = 0; i < 10; i++) gem.frame();
        gem.click(145, 8);  // File
        gem.click(200, 39); // New Folder...
        gem.key(13);        // OK with the default name
        for (let i = 0; i < 4; i++) gem.frame();
        const noDialog = gem.hash();
        gem.drag(...FIRST_FILE, ...COPY_FOLDER); // ALPHA.PRG onto the new folder
        for (let i = 0; i < 4; i++) gem.frame();
        const copyUp = gem.hash();
        await gem.shot(`${out}/copy-dialog.ppm`);
        if (copyUp === noDialog)
            throw new Error("dropping a file on a folder did not open the COPY box");
        gem.point(145, 8, 0); // hover File: an unlocked bar drops the menu down
        for (let i = 0; i < 3; i++) gem.frame();
        await gem.shot(`${out}/copy-menu-hover.ppm`);
        if (gem.hash() !== copyUp)
            throw new Error("the menu bar reacted while the COPY box was open");
    },
    // The ROM's handle tables must survive an app being launched over and over.
    // ST Replay opens a Gui, a Dialog and a FileSel from the ROM on EVERY init;
    // when it leaked them (Phase 2 step 2.1) the tables were exhausted after two
    // launches and every ROM call silently became a no-op — the app still drew,
    // but the ITEM SELECTOR stopped opening. So: launch it repeatedly, then check
    // the selector still responds to its key.
    "rom-handle-reuse": async (gem, out) => {
        // Since step 2.3b this is a REAL launch: GEM asks the host to run a program
        // off the disk and the harness instantiates it as the next cart, exactly as
        // sealed-loader.js does. So this covers the swap protocol as well as the
        // handle tables — and it is the only test that does.
        gem.programs["ALPHA.PRG"] = await readFile("docs/demo-st_replay.wasm");
        const LAUNCHES = 4; // > MAX_FSEL in rom/sdk/rom.zig, so a leak runs out
        for (let i = 0; i < LAUNCHES; i++) {
            gem.open(...FLOPPY);                 // open the FLOPPY window
            for (let f = 0; f < 6; f++) gem.frame();
            gem.open(...FIRST_FILE);             // double-click ALPHA.PRG (type 0)
            for (let f = 0; f < 6; f++) gem.frame();
            if (i < LAUNCHES - 1) {
                gem.key(0x78);                   // 'x' — eXit programme, back to GEM
                for (let f = 0; f < 8; f++) gem.frame();
            }
        }
        if (gem.swaps !== LAUNCHES)
            throw new Error(`GEM ran ${gem.swaps} program(s), expected ${LAUNCHES} — ` +
                            `the launch request never reached the host`);
        const before = gem.hash();
        gem.key(0x6c); // 'l' — Load from disc: opens the ITEM SELECTOR
        for (let f = 0; f < 4; f++) gem.frame();
        const after = gem.hash();
        await gem.shot(`${out}/rom-handle-reuse.ppm`);
        if (before === after)
            throw new Error(`ITEM SELECTOR did not open after ${LAUNCHES} launches ` +
                            `— the ROM's handles were leaked (screen unchanged)`);
        console.log(`  ${LAUNCHES} real launches off the disk; selector still opens`);
    },
};

if (import.meta.url === `file://${process.argv[1]}`) {
    const out = process.argv[2] || ".";
    let failed = 0;
    for (const [name, run] of Object.entries(SCENARIOS)) {
        console.log(name);
        const gem = await bootGem();
        gem.mount(DISK);
        try {
            await run(gem, out);
        } catch (e) {
            console.log(`  FAIL: ${e.message}`);
            failed++;
        }
    }
    if (failed) {
        console.log(`\n${failed} scenario(s) FAILED ❌`);
        process.exit(1);
    }
    console.log("\nall scenarios pass ✅");
}
