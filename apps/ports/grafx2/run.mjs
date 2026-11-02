// Run demo-pt2.wasm headless on the sealed machine and write PNGs of the physical frame.
//   cd <repo> && node apps/ports/pt2/run.mjs [frames=3] [out=apps/ports/grafx2/build/frame]
// WASI imports are stubbed here (step 5 of README.md replaces them); consoleLogJS prints.
import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../../../docs/wasm_hiwater.js";

const FRAMES = +(process.argv[2] ?? 3), OUT = process.argv[3] ?? "apps/ports/grafx2/build/frame";
const CART = "apps/ports/grafx2/build/demo-grafx2.wasm";
const DISK = await readFile("docs/demo-grafx2.zmd").catch(() => null); // the drive's floppy
const CLICKS = (process.env.CLICKS ?? "").split(";").filter(Boolean).map((c) => c.split(",").map(Number)); // frame,x,y (pt2 coords)
const memory = new WebAssembly.Memory({ initial: 144, maximum: 144 });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile(CART);
const text = (p, n) => new TextDecoder().decode(new Uint8Array(memory.buffer, p, n));
const env = { memory, ...rom, consoleLogJS: (p, n) => console.log("cart:", text(p, n)),
    diskReadBlock: (b, dst) => { if (!DISK) return 0; const s = DISK.subarray(b * 512, b * 512 + 512); new Uint8Array(memory.buffer, dst, s.length).set(s); return s.length; } };
for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
const wasi = {}, missing = new Set();
for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes))) {
    if (imp.module === "env" && !(imp.name in env)) { env[imp.name] = () => 0; missing.add("env." + imp.name); }
    if (imp.module === "wasi_snapshot_preview1") wasi[imp.name] = (...a) => {
        if (imp.name === "proc_exit") throw new Error("proc_exit " + a[0]);
        if (imp.name === "fd_write") { // stdout/stderr: print iovecs
            const v = new DataView(memory.buffer); let n = 0, s = "";
            for (let i = 0; i < a[2]; i++) { const p = v.getUint32(a[1] + i * 8, true), l = v.getUint32(a[1] + i * 8 + 4, true); s += text(p, l); n += l; }
            process.stdout.write("cart fd" + a[0] + ": " + s); v.setUint32(a[3], n, true); return 0;
        }
        if (imp.name.endsWith("_sizes_get")) { const v = new DataView(memory.buffer); v.setUint32(a[0], 0, true); v.setUint32(a[1], 0, true); return 0; }
        return imp.name === "fd_prestat_get" ? 8 /* EBADF: no preopens */ : 52 /* ENOSYS */;
    };
}
if (missing.size) console.log("stubbed:", [...missing].join(" "));
const demo = (await WebAssembly.instantiate(cartBytes, { env, wasi_snapshot_preview1: wasi })).instance.exports;
machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
machine.hwInit();
const t0 = Date.now(); demo.boot(); console.log(`boot ${Date.now() - t0} ms`);
demo.skipBoot();

function png(path) {
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
    const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
    const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcT[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => { const b = Buffer.alloc(12 + data.length); b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8); b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length); return b; };
    const raw = Buffer.alloc(H * (W * 3 + 1));
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const i = (y * W + x) * 4, o = y * (W * 3 + 1) + 1 + x * 3; raw[o] = px[i]; raw[o + 1] = px[i + 1]; raw[o + 2] = px[i + 2]; }
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
for (let f = 1; f <= FRAMES; f++) {
    for (const [cf, x, y] of CLICKS) if (cf - 1 === f) { demo.pointer(x * 2, y, 0); } else if (cf === f) { demo.pointer(x * 2, y, 1); } else if (cf + 6 === f) { demo.pointer(x * 2, y, 0); }
    machine.hwClear(); demo.frame(1000 / 60); machine.hwRenderPlane(0);
    if (f === FRAMES || f === 1) { await png(`${OUT}${f}.png`); console.log(`wrote ${OUT}${f}.png`); }
}
