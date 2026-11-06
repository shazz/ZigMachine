// Frames of the falcon_ays cart at song times, for comparing with the original's capture
// (scripts/grab.py). Run from the checkout root:
//   node prototypes/falcon_ays_re/scripts/shots.mjs <outdir> t1 t2 ...     (seconds; PNG via python3 PIL)
import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { cartRam, romRam } from "../../../docs/wasm_hiwater.js";

// FULL=1: the whole 400x280 raster, borders included (where the flashes must show too).
const FULL = process.env.FULL === "1";
const RW = 800, W = FULL ? 400 : 320, H = FULL ? 280 : 200, X0 = FULL ? 0 : 40, Y0 = FULL ? 0 : 40;
const [outdir, ...times] = process.argv.slice(2);
const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
})).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile("docs/demo-falcon_ays.wasm");
const env = { memory, ...rom };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
demo.boot();
demo.skipBoot();
let frame = 0;
for (const t of times.map(Number).sort((a, b) => a - b)) {
    while (frame < Math.round(t * 60)) { machine.hwClear(); demo.frame(1000 / 60); frame++; }
    machine.hwClear();
    for (let p = 0; p < 8; p++) if (demo.isPlaneEnabled(p)) machine.hwRenderPlane(p);
    const px = new Uint32Array(memory.buffer, machine.hwPhysicalPtr(), RW * 280);
    const body = Buffer.alloc(W * H * 3);
    for (let i = 0; i < W * H; i++) {
        const v = px[(Y0 + Math.floor(i / W)) * RW + (X0 + (i % W)) * 2];
        body[i * 3] = v & 255; body[i * 3 + 1] = (v >> 8) & 255; body[i * 3 + 2] = (v >> 16) & 255;
    }
    const f = `${outdir}/port_s${t.toFixed(2).padStart(7, "0")}`;
    await writeFile(`${f}.ppm`, Buffer.concat([Buffer.from(`P6 ${W} ${H} 255\n`), body]));
    execFileSync("python3", ["-c", `from PIL import Image; Image.open('${f}.ppm').save('${f}.png')`]);
}
