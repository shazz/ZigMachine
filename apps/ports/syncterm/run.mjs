// Run the SyncTERM cart headless on the sealed machine, its floppy mounted, and write PNGs of the desk
// (640x480, from hwRenderDesk's two halves). For experiments; the gate's harness is apps/ports_headless.mjs.
//   cd <repo> && node apps/ports/syncterm/run.mjs [frames=120] [out=apps/ports/syncterm/build/frame]
//   KEYS="frame:text;..."   type text at a frame (\r = Enter)        DISK=<zmd>  another floppy
//   CODES="frame:code;..."  a raw key code at a frame (0xE013 = Alt, a toggle; decimal or 0x)
import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../../../docs/wasm_hiwater.js";

const FRAMES = +(process.argv[2] ?? 120), OUT = process.argv[3] ?? "apps/ports/syncterm/build/frame";
const CART = process.env.CART ?? "apps/ports/syncterm/build/demo-syncterm.wasm";
const DISK = await readFile(process.env.DISK ?? "docs/demo-syncterm.zmd").catch(() => null);
const KEYS = (process.env.KEYS ?? "").split(";").filter(Boolean).map((k) => { const i = k.indexOf(":"); return [+k.slice(0, i), k.slice(i + 1).replace(/\\r/g, "\r")]; });
const CODES = (process.env.CODES ?? "").split(";").filter(Boolean).map((k) => k.split(":").map(Number));
const memory = new WebAssembly.Memory({ initial: 128, maximum: 128 });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile(CART);
const text = (p, n) => new TextDecoder().decode(new Uint8Array(memory.buffer, p, n));
const env = { memory, ...rom, pollCartRequest: () => 0, consoleLogJS: (p, n) => console.log("cart:", text(p, n)),
    diskReadBlock: (b, dst) => { if (!DISK) return 0; const s = DISK.subarray(b * 512, b * 512 + 512); new Uint8Array(memory.buffer, dst, s.length).set(s); return s.length; } };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
    if (imp.module === "env" && !(imp.name in env)) { env[imp.name] = () => 0; console.log("stubbed: env." + imp.name); }
const demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
let t0 = Date.now(); demo.boot(); console.log(`boot ${Date.now() - t0} ms, cart RAM free ${machine.hwRamFree()} bytes`);

function desk() { // the 640x480 RGBA picture, as scene_hash reads it
    const W = 640, out = Buffer.alloc(W * 480 * 4);
    for (const h of [0, 1]) { machine.hwRenderDesk(h); out.set(new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * 240 * 4), h * W * 240 * 4); }
    return out;
}
function png(path, px, W = 640, H = 480) {
    const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcT[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => { const b = Buffer.alloc(12 + data.length); b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8); b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length); return b; };
    const raw = Buffer.alloc(H * (W * 3 + 1));
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const i = (y * W + x) * 4, o = y * (W * 3 + 1) + 1 + x * 3; raw[o] = px[i]; raw[o + 1] = px[i + 1]; raw[o + 2] = px[i + 2]; }
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
t0 = Date.now();
for (let f = 1; f <= FRAMES; f++) {
    for (const [kf, s] of KEYS) if (kf === f) for (const ch of s) demo.key(ch.charCodeAt(0));
    for (const [kf, c] of CODES) if (kf === f) demo.key(c);
    machine.hwClear(); demo.frame(1000 / 60);
    if (f === FRAMES || f % 30 === 0) { await png(`${OUT}${f}.png`, desk()); console.log(`wrote ${OUT}${f}.png (desk ${machine.hwDeskActive()})`); }
}
console.log(`${FRAMES} frames in ${Date.now() - t0} ms`);
