// Headless DYNO PARADIS3 driver: boots the sealed machine + the cart the way
// sealed-loader.js does, runs frames and writes the whole 400x280 physical
// screen (a fullscreen overscan plane, so the borders ARE content).
//
// hwRenderPlane(p) OVERWRITES the shared physical framebuffer, so each plane is
// snapshotted right after it renders and alpha-blended here, bottom first. The
// scene uses only plane 0 (PLANES = 1).
//
//   node apps/dyno_paradis3_headless.mjs [outdir] [dt_ms] [frame,frame,...]
// Shots are named by frame number (1 = the first frame after the cart starts).
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1;

async function boot(cart) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
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
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit,
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop,
            hwRamSize: machine.hwRamSize, hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
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
    return { memory, machine, demo };
}

const { memory, machine, demo } = await boot("docs/demo-dyno_paradis3.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const XS = W / 400; // physical pixels per logical column (2 on the 800-wide raster)
const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);

function composite() {
    const out = new Float32Array(W * H * 3);
    for (let p = 0; p < PLANES; p++) {
        machine.hwRenderPlane(p);
        const px = pfb();
        for (let i = 0; i < W * H; i++) {
            const a = px[i * 4 + 3] / 255;
            for (let c = 0; c < 3; c++) out[i * 3 + c] = out[i * 3 + c] * (1 - a) + px[i * 4 + c] * a;
        }
    }
    return out;
}

async function shot(path, frame) {
    const img = composite();
    const hdr = new TextEncoder().encode(`P6\n400 ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + 400 * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < 400; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * 400 + x) * 3 + c] = img[(y * W + x * XS) * 3 + c];
    await writeFile(path, buf);
    console.log(`  shot: ${path} (frame ${frame})`);
}

const out = process.argv[2] || "/tmp/dyno_paradis3";
const dt = Number(process.argv[3] || 1000 / 60);
// intro: frames 1..2228, splash 2229..2318 (90 black frames), main from 2319
const wanted = (process.argv[4] || "1,200,1000,2228,2229,2318,2319,2500,3200,6000,12000")
    .split(",").map(Number).sort((a, b) => a - b);
await mkdir(out, { recursive: true });
if (W !== 800 && W !== 400) console.log(`  note: physical width ${W}`);

let frame = 0;
for (const target of wanted) {
    while (frame < target) { demo.frame(dt); frame++; }
    await shot(`${out}/${String(target).padStart(5, "0")}.ppm`, target);
}

// Warm frame cost, best of 5 runs of 600 main-part frames: the cart's frame()
// plus the machine composite of its plane (HBLs included).
let bestCart = Infinity, bestComp = Infinity;
for (let r = 0; r < 5; r++) {
    let t0 = performance.now();
    for (let i = 0; i < 600; i++) demo.frame(dt);
    bestCart = Math.min(bestCart, (performance.now() - t0) / 600);
    t0 = performance.now();
    for (let i = 0; i < 600; i++) for (let p = 0; p < PLANES; p++) machine.hwRenderPlane(p);
    bestComp = Math.min(bestComp, (performance.now() - t0) / 600);
}
console.log(`  frame cost (best of 5x600): cart ${bestCart.toFixed(3)} ms + planes ${bestComp.toFixed(3)} ms`);
