// The sealed machine as union_l16_headless.mjs drives it: the video machine, ROM
// and a cart (optionally with the Union hub's return note already in the ROM
// scratch), the audio machine playing an SNDH, and a PNG writer.
import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // SHARED_PAGES in machine/sdk/memmap.zig
const AUDIO_PAGES = 48; // AUDIO_PAGES in machine/sdk/audio.zig

// The hub's return note (union_demo/return_note.zig): "UNI1", u8 length 14, u8 XOR,
// then door u8, flags u8, x f32, y f32, scroll u32, little-endian.
function writeNote(buf, { scroll, door }) {
    const p = new DataView(buf.buffer, buf.byteOffset + 6, 14);
    p.setUint8(0, door); p.setUint8(1, 0); p.setFloat32(2, 3984, true); p.setFloat32(6, 127, true); p.setUint32(10, scroll, true);
    buf[4] = 14;
    buf[5] = buf.subarray(6, 20).reduce((a, b) => a ^ b, 0);
    buf.set([0x55, 0x4e, 0x49, 0x31], 0);
}

export async function boot(cart, note = null) {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const rom = (await WebAssembly.instantiate(romBytes, {
        env: { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit },
    })).instance.exports;
    const scratch = () => new Uint8Array(memory.buffer, rom.romScratchPtr(), rom.romScratchLen());
    if (note !== null) writeNote(scratch(), note);
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight();
    // plane 1 over plane 0, each rendered on its own (hwRenderPlane overwrites the frame)
    const composite = () => {
        const planes = [0, 1].map((p) => { machine.hwRenderPlane(p); return new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4).slice(); });
        const px = planes[0];
        for (let i = 0; i < px.length; i += 4) if (planes[1][i + 3] === 255) px.set(planes[1].subarray(i, i + 4), i);
        return px;
    };
    return { memory, machine, demo, scratch, composite, W, H };
}

/// The SNDH on the audio machine, as the worklet would play it, for 4 seconds.
export async function songPeak(file) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const k of Object.keys(machine)) if (k.startsWith("machine")) env[k] = machine[k];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const tune = new Uint8Array(await readFile(file));
    new Uint8Array(memory.buffer, audio.audioSongPtr(), tune.length).set(tune);
    if (!audio.audioLoadSndh(tune.length)) return { error: "not an SNDH image" };
    audio.audioSndhPlay(1);
    const left = new Float32Array(memory.buffer, machine.audioLeftPtr(), 1024);
    const regs = new Uint8Array(memory.buffer, machine.audioYmRegsPtr(), 16);
    let peak = 0;
    const voices = new Set();
    for (let done = 0; done < 44100 * 4; done += 1024) {
        audio.audioRender(1024);
        for (const v of left) peak = Math.max(peak, Math.abs(v));
        for (let ch = 0; ch < 3; ch++) if (regs[8 + ch]) voices.add(ch);
    }
    return { subtunes: audio.audioSndhSubtunes(), stuck: audio.audioSndhStuckPc(), mode: audio.audioMode(), peak, voices: voices.size };
}

/// An RGB PNG of w x h, pixel (x, y) given by at(px, x, y).
export async function png(path, px, w, h, at) {
    const raw = Buffer.alloc(h * (1 + w * 3));
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) raw.set(at(px, x, y), y * (1 + w * 3) + 1 + x * 3);
    const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (buf) => { let c = 0xffffffff; for (const v of buf) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    await writeFile(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
