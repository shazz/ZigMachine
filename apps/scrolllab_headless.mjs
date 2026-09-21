// Headless SCROLLTEXT LAB driver. The lab is a comparison bench, not a shipped
// screen, so the checks are minimal: every mode renders text, every distortion
// actually differs from FLAT, and Escape still leaves.
//
//   node apps/scrolllab_headless.mjs [outdir]
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, MODES = 10, K_ESC = 0xe012;
let failures = 0;
function check(name, got, want) {
    const ok = got === want;
    if (!ok) failures++;
    console.log(`  ${ok ? "ok  " : "FAIL"}  ${name}: got ${got}, want ${want}`);
}

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
const cartBytes = await readFile("docs/demo-scrolllab.wasm"), env = { memory, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();

const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
const VB = machine.hwVideoBase();
const regs = new DataView(memory.buffer, VB, 0x100);
const indices = () => new Uint8Array(memory.buffer, VB + regs.getUint32(0x44, true), regs.getUint16(0x34, true) * H);

/// The band only: rows below the two label lines, so the label does not count.
function band() {
    const lfb = indices(), stride = regs.getUint16(0x34, true), out = [];
    for (let y = 0; y < 160; y++) for (let x = 0; x < 320; x++) if (lfb[y * stride + x] > 1) out.push(y * 320 + x);
    return out;
}

async function shot(out, name) {
    machine.hwClear();
    machine.hwRenderPlane(0);
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const hdr = new TextEncoder().encode(`P6\n320 200\n255\n`);
    const buf = new Uint8Array(hdr.length + 320 * 200 * 3);
    buf.set(hdr);
    for (let y = 0; y < 200; y++)
        for (let x = 0; x < 320; x++)
            for (let c = 0; c < 3; c++) buf[hdr.length + (y * 320 + x) * 3 + c] = px[((y + 40) * W + 80 + x * 2) * 4 + c];
    await writeFile(`${out}/${name}.ppm`, buf);
}

const out = process.argv[2] || "/tmp/scrolllab";
await mkdir(out, { recursive: true });
for (let i = 0; i < 200; i++) demo.frame(16.6); // let the text reach the screen
const shapes = [];
for (let m = 1; m <= MODES; m++) {
    demo.key(m === 10 ? 0x30 : 48 + m); // 1..9 then 0 for the tenth
    for (let i = 0; i < 90; i++) demo.frame(16.6);
    const px = band();
    shapes.push(px.join(","));
    await shot(out, `mode${m}`);
    check(`mode ${m} draws text`, px.length > 500, true);
}
for (let m = 2; m <= MODES; m++) check(`mode ${m} is not FLAT`, shapes[m - 1] !== shapes[0], true);
demo.key(K_ESC);
check("Escape leaves for the menu", demo.pollCartRequest(), -1);
console.log(failures ? `\nscrolllab: ${failures} FAILED` : `\nscrolllab: PASS (${MODES} modes, frames in ${out})`);
process.exit(failures ? 1 : 0);
