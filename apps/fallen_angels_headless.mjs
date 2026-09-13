// Headless FALLEN ANGELS check: the scroller's rasters cover all 200 visible
// lines, the top ones included.
//
// The scroller ink (plane 0, entry 1) takes rasters.dat[line] on visible line
// `line`. Its per-plane HBL handler once tested PHYSICAL lines 40..239, but a
// normal plane's handler receives LOGICAL lines 0..199: the top 40 lines kept a
// stale (black) ink and the last five bands never showed. Nothing errors when
// that happens, so this asserts it on plane 0 alone:
//   - every opaque pixel on visible line L has rasters.dat[L]'s colour,
//   - the top 40 lines carry ink at all (a blank top would pass the first test),
//   - row 7 of each 8-row text line is empty (it once read past the 7-row strip).
//
//   node apps/fallen_angels_headless.mjs [outdir] [cart.wasm]
import { readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const TOP = 40; // first visible physical row
const FRAME = 1200; // text fills the top lines and the 3D grid is up

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

const { memory, machine, demo } = await boot(process.argv[3] || "docs/demo-fallen_angels.wasm");
const rasters = await readFile("apps/zig/assets/screens/fallen_angels/rasters.dat");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
for (let f = 0; f < FRAME; f++) demo.frame(1000 / 60);

machine.hwRenderPlane(0); // the scroller alone
const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
const errors = [];
let topInk = 0;
for (let line = 0; line < 200; line++) {
    const want = rasters.subarray(line * 4, line * 4 + 3);
    let wrong = 0, ink = 0;
    for (let x = 0; x < W; x++) {
        const i = ((line + TOP) * W + x) * 4;
        if (px[i + 3] === 0) continue;
        ink++;
        if (px[i] !== want[0] || px[i + 1] !== want[1] || px[i + 2] !== want[2]) wrong++;
    }
    if (wrong) errors.push(`line ${line}: ${wrong} px not rasters[${line}]`);
    if (line % 8 === 7 && ink) errors.push(`line ${line}: gap row carries ${ink} px`);
    if (line < TOP) topInk += ink;
}
if (topInk < 1000) errors.push(`top ${TOP} lines carry only ${topInk} ink px`);

if (process.argv[2]) {
    const hdr = new TextEncoder().encode(`P6\n${W} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + W * H * 3);
    buf.set(hdr);
    for (let i = 0; i < W * H; i++) for (let c = 0; c < 3; c++) buf[hdr.length + i * 3 + c] = px[i * 4 + c];
    await writeFile(`${process.argv[2]}/fallen_angels-plane0.ppm`, buf);
}

if (errors.length) {
    console.error(`fallen_angels: rasters WRONG at frame ${FRAME}\n  ${errors.slice(0, 12).join("\n  ")}`);
    process.exit(1);
}
console.log(`fallen_angels: rasters on all 200 lines (top ${TOP} lines: ${topInk} ink px)`);
