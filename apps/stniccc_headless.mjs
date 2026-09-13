// Headless STNICCC 2000 driver: boots the sealed machine + demo-stniccc.wasm the
// way sealed-loader.js does, runs host frames and writes the visible 320x200
// screen as PPM at chosen STREAM frames. It also times every host frame, so a
// frame that blows the 16.6 ms budget (the busiest has 164 polygons) shows up.
//
//   node apps/stniccc_headless.mjs [outdir] [streamframe,streamframe,...]
//
// One stream frame is drawn every VBL_PER_FRAME host frames (2, see stniccc.zig),
// so stream frame n is on screen after host frame 2n + 1.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const VBL_PER_FRAME = 2; // stniccc.zig
const STREAM_FRAMES = 1800;

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

const out = process.argv[2] || ".";
const wanted = new Set((process.argv[3] || "0,120,600,1100,1799").split(",").map(Number));
await mkdir(out, { recursive: true });
const { memory, machine, demo } = await boot("docs/demo-stniccc.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const BX = machine.hwBorderX(), BY = machine.hwBorderY();
const XS = W / 400; // physical pixels per logical column

async function shot(path) {
    machine.hwRenderPlane(0);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const hdr = new TextEncoder().encode(`P6\n320 200\n255\n`);
    const buf = new Uint8Array(hdr.length + 320 * 200 * 3);
    buf.set(hdr);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++)
            for (let c = 0; c < 3; c++)
                buf[hdr.length + (y * 320 + x) * 3 + c] = px[((y + BY) * W + BX + x * XS) * 4 + c];
    await writeFile(path, buf);
}

let worst = 0, worstAt = 0, total = 0;
const hostFrames = STREAM_FRAMES * VBL_PER_FRAME + 2; // one full loop of the flight
for (let f = 0; f < hostFrames; f++) {
    machine.hwClear();
    const t0 = performance.now();
    demo.frame(16.6);
    const dt = performance.now() - t0;
    total += dt;
    if (dt > worst) { worst = dt; worstAt = f; }
    const stream = (f - 1) / VBL_PER_FRAME; // host frame 2n+1 shows stream frame n
    if (Number.isInteger(stream) && wanted.has(stream)) {
        await shot(`${out}/stniccc-${String(stream).padStart(4, "0")}.ppm`);
        console.log(`  shot: stream frame ${stream}`);
    }
}
console.log(`host frames: ${hostFrames}, mean ${(total / hostFrames).toFixed(3)} ms, ` +
            `worst ${worst.toFixed(3)} ms at host frame ${worstAt} (budget 16.6 ms)`);
