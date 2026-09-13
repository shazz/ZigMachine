// Headless STNICCC 2000 driver: boots the sealed machine + demo-stniccc.wasm the
// way sealed-loader.js does, with ITS DISK in the drive (docs/demo-stniccc.zmd,
// which carries SCENE1.BIN), runs host frames and writes the visible screen as
// PPM at chosen HOST frames. It also times every frame against the 16.6 ms
// budget. The rewind replays up to ~100 frames from a keyframe in one VBL, and
// that is the frame worth watching.
//
//   node apps/stniccc_headless.mjs [outdir] [hostframe,hostframe,...] [frames]
//
// The choreography (stniccc.zig): host frames 1-600 small, then slow down,
// rewind, message, fullscreen. Shots before the fullscreen switch are 320x200;
// from then on 400x280 (the whole overscan screen).
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig

async function boot(cart, disk) {
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
    // The drive, as sealed-loader.js's diskReadBlock: one 512-byte block into shared RAM.
    const diskReadBlock = (block, dstOff) => {
        const src = disk.subarray(block * 512, block * 512 + 512);
        if (src.length === 0) return 0;
        new Uint8Array(memory.buffer, dstOff, src.length).set(src);
        return src.length;
    };
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
            diskReadBlock, hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const out = process.argv[2] || ".";
const wanted = new Set((process.argv[3] || "300,650,800,880,950,1300,2000").split(",").map(Number));
const FRAMES = Number(process.argv[4] || 3000);
await mkdir(out, { recursive: true });
const disk = new Uint8Array(await readFile("docs/demo-stniccc.zmd"));
const { memory, machine, demo } = await boot("docs/demo-stniccc.wasm", disk);
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const XS = W / 400; // physical pixels per logical column

// The whole 400x280 physical screen (borders included), so the fullscreen
// switch is visible: before it the borders are black.
async function shot(path) {
    machine.hwRenderPlane(0);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const hdr = new TextEncoder().encode(`P6\n400 ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + 400 * H * 3);
    buf.set(hdr);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < 400; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * 400 + x) * 3 + c] = px[(y * W + x * XS) * 4 + c];
    await writeFile(path, buf);
}

let worst = 0, worstAt = 0, total = 0;
for (let f = 1; f <= FRAMES; f++) {
    machine.hwClear();
    const t0 = performance.now();
    demo.frame(16.6);
    const dt = performance.now() - t0;
    total += dt;
    if (dt > worst && f > 1) { worst = dt; worstAt = f; } // frame 1 includes JIT warm-up
    if (wanted.has(f)) {
        await shot(`${out}/stniccc-host${String(f).padStart(4, "0")}.ppm`);
        console.log(`  shot: host frame ${f}`);
    }
}
console.log(`host frames: ${FRAMES}, mean ${(total / FRAMES).toFixed(3)} ms, ` +
            `worst ${worst.toFixed(3)} ms at host frame ${worstAt} (budget 16.6 ms)`);
