// Dev aid, not a gate: runs docs/demo-c-bench.wasm on the real clock and writes the final screen as a PNG.
//   node apps/bench_shot.mjs out.png
import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
let demo;
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
    env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) } })).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const bytes = await readFile("docs/demo-c-bench.wasm");
const env = { memory, ...rom, hostMicros: () => Math.floor(performance.now() * 1000) >>> 0, consoleLogJS: () => {} };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
demo = (await WebAssembly.instantiate(bytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
machine.hwInit(); demo.boot(); demo.skipBoot();
demo.benchSetTargetUs(150000);
for (let i = 0; i < 2000; i++) { machine.hwClear(); demo.frame(16.6); if (i === 5) shot(process.argv[2].replace(".png", "_run.png")); }
shot(process.argv[2]);

function shot(path) {
    machine.hwRenderPlane(0);
    const pw = machine.hwPhysWidth(), pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), pw * machine.hwPhysHeight() * 4);
    const raw = Buffer.alloc(200 * (320 * 3 + 1));
    for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const s = ((40 + y) * pw + 80 + x * 2) * 4, d = y * (961) + 1 + x * 3;
        raw[d] = pfb[s]; raw[d + 1] = pfb[s + 1]; raw[d + 2] = pfb[s + 2];
    }
    const crc = (buf) => { let c, t = ~0; for (const b of buf) { c = (t ^ b) & 255; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t = (t >>> 8) ^ c; } return ~t >>> 0; };
    const chunk = (type, data) => { const b = Buffer.alloc(12 + data.length); b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8); b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length); return b; };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(320, 0); ihdr.writeUInt32BE(200, 4); ihdr[8] = 8; ihdr[9] = 2;
    writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
