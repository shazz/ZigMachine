// The sealed machine as apps/ports_headless.mjs drives a C program port (apps/ports): the real
// docs/machine-video.wasm + docs/rom.wasm on one shared memory, the cart instantiated as
// docs/sealed-loader.js does, its floppy in the drive (diskReadBlock), the PCM it feeds counted.
// Strict on purpose: a cart that imports anything but the host's env functions below fails to
// boot here, as it would in the browser (the run.mjs rigs stub unknown imports instead).
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 128; // SHARED_PAGES in machine/sdk/memmap.zig (the 3 MiB cart window)
export const DT = 1000 / 60;

// boot(cart, disk, usPerFrame, extraEnv): disk = the .zmd bytes in drive A, or null for an empty drive.
// usPerFrame: 0 = no host clock (hostMicros answers 0, as every harness: the ports pace their audio by
// dt); else hostMicros advances that much a frame while dt stays 16.6 ms, as on the board, where the
// frame takes longer than its dt (kestrel_audio.h). extraEnv: imports over the defaults (the Paula
// channels lent to the cart, apps/pt2_paula_headless.mjs).
export async function boot(cart, disk, usPerFrame = 0, extraEnv = {}) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo = null;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo?.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const bytes = await readFile(cart);
    const log = [], audio = { rate: 0, n: 0, peak: 0, keep: extraEnv.keepAudio ? [] : null }, clock = { us: 0, perFrame: usPerFrame };
    const text = (p, n) => new TextDecoder().decode(new Uint8Array(memory.buffer, p, n));
    const env = {
        memory, ...rom,
        consoleLogJS: (p, n) => log.push(text(p, n)),
        diskReadBlock: (b, dst) => {
            if (!disk) return 0;
            const s = disk.subarray(b * 512, b * 512 + 512);
            new Uint8Array(memory.buffer, dst, s.length).set(s);
            return s.length;
        },
        hostMicros: () => clock.us, // 0 unless usPerFrame: then the board's clock (step() advances it)
        hostAudioStreamStart: (rate) => { audio.rate = rate; },
        hostAudioFeed: (p, n) => {
            audio.n += n;
            for (const v of new Int8Array(memory.buffer, p, n)) audio.peak = Math.max(audio.peak, Math.abs(v));
            if (audio.keep) audio.keep.push(new Int8Array(memory.buffer, p, n).slice());
        },
        hostAudioStreamStop: () => { audio.stops = (audio.stops || 0) + 1; },
        // The Paula channels (HW 1.14.0): none here unless extraEnv lends them (claim 0: software mix).
        hostPaulaClaim: () => 0, hostPaulaUpload: () => {}, hostPaulaWrite: () => {}, hostPaulaRelease: () => {},
        ...extraEnv,
    };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    const unknown = WebAssembly.Module.imports(new WebAssembly.Module(bytes))
        .filter((i) => i.module !== "env" || !(i.name in env)).map((i) => `${i.module}.${i.name}`);
    if (unknown.length) throw new Error(`${cart} imports what no host provides: ${unknown.join(" ")}`);
    demo = (await WebAssembly.instantiate(bytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(bytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, log, audio, clock };
}

// One VBL as the host runs it: clear, frame(dt), composite every enabled plane.
export function step(m) {
    if (m.clock.perFrame) m.clock.us = (m.clock.us + m.clock.perFrame) >>> 0;
    m.machine.hwClear();
    m.demo.frame(DT);
    for (let p = 0; p < 4; p++) if (m.demo.isPlaneEnabled(p)) m.machine.hwRenderPlane(p);
}

// The physical frame (RGBA), a copy.
export function picture(m) {
    const W = m.machine.hwPhysWidth(), H = m.machine.hwPhysHeight();
    return { W, H, px: new Uint8Array(m.memory.buffer, m.machine.hwPhysicalPtr(), W * H * 4).slice() };
}

export const sha = (b) => createHash("sha256").update(b).digest("hex");

export function colours(pic) {
    const v = new Uint32Array(pic.px.buffer, pic.px.byteOffset, pic.px.length / 4);
    return new Set(v).size;
}

// The rows y0..y1 (inclusive) of the picture, for a region hash.
export function rows(pic, y0, y1) {
    return pic.px.subarray(y0 * pic.W * 4, (y1 + 1) * pic.W * 4);
}

export function png(pic, path) {
    const { W, H, px } = pic;
    const crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcT[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => { const b = Buffer.alloc(12 + data.length); b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8); b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length); return b; };
    const raw = Buffer.alloc(H * (W * 3 + 1));
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const i = (y * W + x) * 4, o = y * (W * 3 + 1) + 1 + x * 3; raw[o] = px[i]; raw[o + 1] = px[i + 1]; raw[o + 2] = px[i + 2]; }
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
