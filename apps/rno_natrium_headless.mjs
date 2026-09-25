// Headless RNO / NATRIUM driver: boots the sealed machine the way
// docs/sealed-loader.js does, runs the intro at one 20 ms VBL per host frame
// (the scene paces its timeline by real 50 Hz VBLs), and checks what the
// MACHINE shows -- after the planar expansion, the palette and the choice of
// shown buffer -- against Hatari's own RAM:
//   snapshots  at six timeline counters the 320x200 frame hashes to the
//              snapshot's shown buffer through the palette set at that point
//              (tools/private_tools/rno_natrium_screens.py)
//   part 1     the dot tunnel's two tones above and below line 100, and the
//              NATRIUM logo in rows 72..127, at counter $435
//   loop       the intro ends at $1E00 and starts over: frame $150 of the
//              second run is the first run's, pixel for pixel
// The effect maths is checked byte for byte by the native test
// (apps/zig/scenes/rno_natrium/verify_test.zig); this checks the cart end to end.
//   node apps/rno_natrium_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const VBL_MS = 20; // one ST VBL per frame
const END = 0x1e00;

const SNAPSHOTS = [
    [0xa00, "fb5a66cf8d7855bb8d56737b09c23b3d6accdaeb54a1a723fb3bf92ee301acb2"], // face wobble
    [0xd00, "72745113d4b3066551d6477a97f7f8ffbe0385737e73a5f5d739176232b4da0c"], // env cube
    [0x1100, "9bde6a89fb6d84a6ae8431afd65c569fa69716e8625889e7b2f808652622ca6b"], // credits, row 1
    [0x1500, "8086dd3fd19129dee2b472642637699217d5167334e7d4d05f5c99ac1df393ee"], // twister f 767
    [0x1900, "2f8eaaab7e1a96af9226f6aac9701096a43d224f75cf09fd4efac84177423722"], // env prism
    [0x1c00, "59b9f6e6dea92c4dfea4986b1aaf44b874edc57c94890737c3141fdf255b8d88"], // rotozoom
];

const st = (v) => [(v >> 8) & 7, (v >> 4) & 7, v & 7].map((c) => Math.floor((c * 255) / 7));

async function boot(cart = "docs/demo-rno_natrium.wasm") {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
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
    const env = {
        ...env0,
        hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
        hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
        hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
        hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
        hwRomRamFree: machine.hwRomRamFree, ...rom,
    };
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = noop;
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

class Screen {
    constructor({ memory, machine, demo }) {
        this.machine = machine;
        this.demo = demo;
        this.w = machine.hwPhysWidth(); // 800: x-DOUBLED
        this.h = machine.hwPhysHeight();
        this.bx = machine.hwBorderX(); // the 320x200 window, in physical pixels
        this.by = machine.hwBorderY();
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * this.h * 4);
        this.vbls = 0; // = the timeline counter $144AC
        this.rgb = null;
    }

    // Advance to timeline counter `c`, rendering every frame as the host does.
    runTo(c) {
        while (this.vbls < c) {
            this.machine.hwClear();
            this.demo.frame(VBL_MS);
            this.machine.hwRenderPlane(0);
            this.vbls++;
        }
        this.rgb = this.window();
    }

    // The visible 320x200, un-doubled, 3 bytes a pixel.
    window() {
        const out = new Uint8Array(320 * 200 * 3);
        for (let y = 0; y < 200; y++) {
            for (let x = 0; x < 320; x++) {
                const i = ((this.by + y) * this.w + this.bx + x * 2) * 4;
                out.set(this.pfb.subarray(i, i + 3), (y * 320 + x) * 3);
            }
        }
        return out;
    }

    px(x, y) {
        const o = (y * 320 + x) * 3;
        return [this.rgb[o], this.rgb[o + 1], this.rgb[o + 2]];
    }
    hash() {
        return createHash("sha256").update(this.rgb).digest("hex");
    }
    async shot(path) {
        const hdr = new TextEncoder().encode("P6\n320 200\n255\n");
        await writeFile(path, Buffer.concat([hdr, this.rgb]));
        console.log(`  shot: ${path} (counter $${this.vbls.toString(16)})`);
    }
}

const key = (c) => c.join(",");

// Counter $435: the tunnel field is $012 with $024 dots above line 100, and
// inverted below; the logo band 72..127 carries NATRIUM's white.
function checkPart1(s) {
    const count = (y0, y1) => {
        const seen = new Map();
        for (let y = y0; y < y1; y++) for (let x = 0; x < 320; x++) {
            const k = key(s.px(x, y));
            seen.set(k, (seen.get(k) || 0) + 1);
        }
        return seen;
    };
    const top = count(0, 72), bottom = count(128, 200), logo = count(72, 128);
    const dark = key(st(0x012)), light = key(st(0x024)), white = key(st(0x777));
    if (!(top.get(dark) > top.get(light))) throw new Error("part 1: the top half is not a $012 field with $024 dots");
    if (!(bottom.get(light) > bottom.get(dark))) throw new Error("part 1: the bottom half is not the inverted tunnel");
    if (!logo.get(white)) throw new Error("part 1: no NATRIUM logo in rows 72..127");
    console.log("  part 1: two-tone tunnel split at line 100, logo band up");
}

const out = process.argv[2] || "/tmp/rno_natrium";
await mkdir(out, { recursive: true });
const s = new Screen(await boot());

s.runTo(0x150);
const early = s.hash();
await s.shot(`${out}/00-tunnel.ppm`);
s.runTo(0x435);
await s.shot(`${out}/01-natrium.ppm`);
checkPart1(s);

for (const [counter, want] of SNAPSHOTS) {
    s.runTo(counter);
    await s.shot(`${out}/snap-${counter.toString(16)}.ppm`);
    const got = s.hash();
    if (got !== want) throw new Error(`counter $${counter.toString(16)}: frame ${got} is not Hatari's ${want}`);
    console.log(`  $${counter.toString(16)}: the frame is the RAM snapshot's, byte for byte`);
}

const t0 = performance.now();
const from = s.vbls;
s.runTo(END + 0x150);
const ms = (performance.now() - t0) / (s.vbls - from);
if (s.hash() !== early) throw new Error("after $1E00 the intro did not start over identically");
console.log(`  loop: $1E00 restarts the intro, frame $150 identical on the second run`);
console.log(`  soak: ${s.vbls} frames clean, ${ms.toFixed(3)} ms/frame (update + render + plane composite)`);
