// Run demo-klystrack.wasm headless on the sealed machine (docs/machine-video.wasm + docs/rom.wasm, the floppy
// docs/demo-klystrack.zmd in the drive) and write PNGs of the physical frame (first, every SNAP frames, last).
//   cd <repo> && node apps/ports/klystrack/run.mjs [frames=60] [out=apps/ports/klystrack/build/frame]
//   CLICKS="frame,x,y;..." clicks the left button at klystrack 320x240 coordinates; KEYS="frame,code;..." presses
//   a key (codepoint or 0xE0xx code, see kestrel_input.c) for 3 frames. AUDIO=1 counts the samples fed and
//   writes build/audio.wav (signed 8-bit mono as fed). SNAP=n also writes every n-th frame.
import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../../../docs/wasm_hiwater.js";

const FRAMES = +(process.argv[2] ?? 60), OUT = process.argv[3] ?? "apps/ports/klystrack/build/frame";
const CART = "apps/ports/klystrack/build/demo-klystrack.wasm";
const DISK = await readFile("docs/demo-klystrack.zmd").catch(() => null); // the drive's floppy
const CLICKS = (process.env.CLICKS ?? "").split(";").filter(Boolean).map((c) => c.split(",").map(Number)); // frame,x,y (klystrack 320x240 coords)
const memory = new WebAssembly.Memory({ initial: 144, maximum: 144 });
const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), { env: { memory, hblDispatch() {} } })).instance.exports;
const romBytes = await readFile("docs/rom.wasm");
const rom = (await WebAssembly.instantiate(romBytes, { env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit } })).instance.exports;
machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
const cartBytes = await readFile(CART);
const text = (p, n) => new TextDecoder().decode(new Uint8Array(memory.buffer, p, n));
const KEYS = (process.env.KEYS ?? "").split(";").filter(Boolean).map((c) => c.split(",").map(Number)); // frame,code
const SNAP = +(process.env.SNAP ?? 0);
const audio = { rate: 0, chunks: [], n: 0, peak: 0 };
const env = { memory, ...rom, consoleLogJS: (p, n) => console.log("cart:", text(p, n)),
    hostAudioStreamStart: (rate) => { audio.rate = rate; console.log("audio stream start", rate, "Hz"); },
    hostAudioFeed: (p, n) => { const b = new Int8Array(memory.buffer, p, n); audio.n += n; for (const v of b) audio.peak = Math.max(audio.peak, Math.abs(v)); if (process.env.AUDIO) audio.chunks.push(Buffer.from(new Uint8Array(memory.buffer, p, n))); },
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
let worst = 0, total = 0;
for (let f = 1; f <= FRAMES; f++) {
    for (const [kf, code] of KEYS) { if (kf === f) demo.key(code); if (kf + 3 === f) demo.keyUp(code); }
    for (const [cf, x, y] of CLICKS) if (cf - 1 === f) { demo.pointer(x * 2, y - 20, 0); } else if (cf === f) { demo.pointer(x * 2, y - 20, 1); } else if (cf + 6 === f) { demo.pointer(x * 2, y - 20, 0); }
    const t = performance.now();
    machine.hwClear(); demo.frame(1000 / 60); machine.hwRenderPlane(0);
    const dt = performance.now() - t; worst = Math.max(worst, dt); total += dt;
    if (f === FRAMES || f === 1 || (SNAP && f % SNAP === 0)) { await png(`${OUT}${f}.png`); console.log(`wrote ${OUT}${f}.png`); }
}
console.log(`${FRAMES} frames, ${(total / FRAMES).toFixed(2)} ms a frame on average, worst ${worst.toFixed(1)} ms; audio: ${audio.n} samples at ${audio.rate} Hz fed (${(audio.n / Math.max(1, FRAMES)).toFixed(1)} a frame), peak |s8| ${audio.peak}`);
if (process.env.AUDIO && audio.n) {
    const pcm = Buffer.concat(audio.chunks).map((v) => (v + 128) & 255);   // WAV 8-bit is unsigned
    const h = Buffer.alloc(44); h.write("RIFF", 0); h.writeUInt32LE(36 + pcm.length, 4); h.write("WAVEfmt ", 8); h.writeUInt32LE(16, 16);
    h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(audio.rate, 24); h.writeUInt32LE(audio.rate, 28); h.writeUInt16LE(1, 32); h.writeUInt16LE(8, 34);
    h.write("data", 36); h.writeUInt32LE(pcm.length, 40);
    await writeFile("apps/ports/klystrack/build/audio.wav", Buffer.concat([h, pcm])); console.log("wrote apps/ports/klystrack/build/audio.wav");
}
