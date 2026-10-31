// Headless MIND REWIND (docs/demo-mindwind.wasm): boots the sealed machine + the cart the way
// sealed-loader.js does, runs the demo and checks each part on the composited 800x280 raster
// (every border open: the demo's lines are 416 px on the ST, 400 here).
//   bars    -- the chrome bars are colour 0 a line: the SAME colour across the whole line, the
//              left and right borders included (a real raster), and the gradient's values
//   stripes -- part A's flat effect: every field line shows the same stripe row, many colours
//   picture -- part B: the girl picture on the field lines, wrapping (more than 8 colours a line)
//   rainbow -- part C: the bitmap stays, the colours cycle (a line changes, frame to frame)
//   bands   -- part D: the "<<<<" bands on white
//   vhs     -- the reversed half: whole field lines of $FFF white
//   end     -- the end screen: the logo in the middle, colour-0 borders
// --break copper drops the plane's copper list (no LBASE, no raster): the checks must fail.
//   node apps/mindwind_headless.mjs [outdir] [--break copper]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const REG_FB_COPPER = 0x78;
const BREAK = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;

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
    const hw = {};
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) hw[k] = machine[k];
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            memory, ...hw, ...rom,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop, consoleLogJS: noop,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop,
            diskReadBlock: noop, hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
            hostMicros: () => 0,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo };
}

const { memory, machine, demo } = await boot("docs/demo-mindwind.wasm");
const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const base = machine.hwVideoBase();
let frames = 0;

function run(n) {
    for (let i = 0; i < n; i++) demo.frame(20);
    frames += n;
}
function raster() {
    if (BREAK === "copper") new DataView(memory.buffer).setUint16(base + REG_FB_COPPER, 0, true);
    machine.hwClear();
    machine.hwRenderPlane(0);
    return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4).slice();
}
const px = (r, x, y) => [r[(y * W + x) * 4], r[(y * W + x) * 4 + 1], r[(y * W + x) * 4 + 2]].join(",");
const lineColours = (r, y) => new Set(Array.from({ length: W }, (_, x) => px(r, x, y)));
const ste = (w) => [8, 4, 0].map((s) => (((w >> s) & 7) << 1 | (w >> (s + 3)) & 1) * 16).join(",");

const out = process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "/tmp/mindwind";
await mkdir(out, { recursive: true });
async function shot(name, r) {
    const hdr = new TextEncoder().encode(`P6\n${W} ${H}\n255\n`);
    const buf = new Uint8Array(hdr.length + W * H * 3);
    buf.set(hdr);
    for (let i = 0; i < W * H; i++) for (let c = 0; c < 3; c++) buf[hdr.length + i * 3 + c] = r[i * 4 + c];
    await writeFile(`${out}/${name}.ppm`, buf);
}

const errors = [];
const check = (ok, what) => { if (!ok) errors.push(`${what} (frame ${frames})`); console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); };

run(1000); // part A, flat stripes, bars in
let r = raster();
await shot("a_flat", r);
const BAR = [0x0001, 0x0002, 0x0113, 0x0224, 0x0335, 0x0446, 0x0556, 0x0667, 0x0777, 0x0666, 0x0444, 0x0333, 0x0111, 0x0000];
check(BAR.every((c, k) => lineColours(r, k).size === 1 && px(r, 0, k) === ste(c) && px(r, W - 1, k) === ste(c)),
    "bars: one colour 0 a line, the gradient, across both borders");
check(lineColours(r, 60).size >= 3 && px(r, 0, 60) !== px(r, 400, 60), "stripes: the field shows stripes");
check(Array.from({ length: W }, (_, x) => px(r, x, 30) === px(r, x, 180)).every(Boolean), "stripes: flat, every line the same row");

run(3700 - frames); // part B, the wobble
r = raster();
await shot("b_picture", r);
check(lineColours(r, 100).size > 8, "picture: the girl on the field lines");

run(6000 - frames); // part C
r = raster();
await shot("c_rainbow", r);
const before = Array.from({ length: W }, (_, x) => px(r, x, 100)).join(";");
run(1);
const after = Array.from({ length: W }, (_, x) => px(raster(), x, 100)).join(";");
check(before !== after && lineColours(r, 100).size >= 8, "rainbow: many colours, cycling every frame");

run(7340 - frames); // part D
r = raster();
await shot("d_bands", r);
check(px(r, 0, 5) === "240,240,240" && lineColours(r, 30).size >= 3, "bands: the <<<< bands on white");

run(8400 - frames); // part A reversed (8259..8927), VHS lines
let vhs = false;
for (let i = 0; i < 40 && !vhs; i++) {
    r = raster();
    for (let y = 20; y < 190 && !vhs; y++) vhs = lineColours(r, y).size === 1 && px(r, 10, y) === "240,240,240";
    run(1);
}
await shot("e_vhs", r);
check(vhs, "vhs: a whole field line of $FFF in the rewound half");

run(9100 - frames); // the end screen (from about 8963)
r = raster();
await shot("f_end", r);
check(lineColours(r, 140).size > 4 && lineColours(r, 10).size === 1, "end: the logo, colour-0 borders");

if (machine.hwRamAllocFailures()) errors.push(`${machine.hwRamAllocFailures()} zg.mem allocation(s) refused`);
const ok = BREAK ? errors.length > 0 : errors.length === 0;
console.log(ok ? `=> PASS ✅ ${BREAK ? `--break ${BREAK} is caught` : "every part"}` : `=> FAIL ❌\n  ${errors.join("\n  ")}`);
process.exit(ok ? 0 : 1);
