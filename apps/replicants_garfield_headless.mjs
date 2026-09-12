// Headless REPLICANTS GARFIELD driver: boots the sealed machine + the cart the way
// sealed-loader.js does, runs N frames and writes the composited visible screen.
//
// hwRenderPlane(p) OVERWRITES the shared physical framebuffer, so each plane is
// snapshotted right after it renders and the snapshots are alpha-blended here,
// bottom plane first. The scene now uses only plane 0 (PLANES = 1); the blend
// stays so the harness still works if a plane is ever added back.
//
//   node apps/replicants_garfield_headless.mjs [outdir]
import { readFile, writeFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1; // the scene draws everything into plane 0

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

const { memory, machine, demo } = await boot("docs/demo-replicants_garfield.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const pfb = () => new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
let frames = 0;

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

async function shot(path) {
    const img = composite();
    // the visible window only: 640x200 physical at (80,40), halved back to 320x200
    const X0 = 80, Y0 = 40, VW = 320, VH = 200;
    const hdr = new TextEncoder().encode(`P6\n${VW} ${VH}\n255\n`);
    const buf = new Uint8Array(hdr.length + VW * VH * 3);
    buf.set(hdr);
    for (let y = 0; y < VH; y++)
        for (let x = 0; x < VW; x++)
            for (let c = 0; c < 3; c++)
                buf[hdr.length + (y * VW + x) * 3 + c] = img[((Y0 + y) * W + X0 + x * 2) * 3 + c];
    await writeFile(path, buf);
    console.log(`  shot: ${path} (frame ${frames})`);
}

function run(n) {
    for (let i = 0; i < n; i++) demo.frame(16.6);
    frames += n;
}

const out = process.argv[2] || "/tmp/replicants_garfield";
if (W !== 800 && W !== 400) console.log(`  note: physical width ${W}`);
for (const [n, name] of [[1, "01"], [60, "61"], [90, "151"], [150, "301"]]) {
    run(n);
    await shot(`${out}/${name}.ppm`);
}

// Frame cost: the cart's frame() plus the machine composite of its three planes
// (HBLs included), which is the CPU half of a real frame.
const N = 600;
let t = performance.now();
run(N);
const cart = (performance.now() - t) / N;
t = performance.now();
for (let i = 0; i < N; i++) for (let p = 0; p < PLANES; p++) machine.hwRenderPlane(p);
const comp = (performance.now() - t) / N;
console.log(`  frame cost: cart ${cart.toFixed(3)} ms + planes ${comp.toFixed(3)} ms`);
