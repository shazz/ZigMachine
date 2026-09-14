// The sealed machine for apps/union_superscroller_headless.mjs: boot a cart over
// the real video + ROM modules (optionally with the Union Demo hub's return note
// planted in the ROM scratch first), composite its planes, write PNGs, and play
// an SNDH on the real audio modules the way the worklet does.
import { readFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112, AUDIO_PAGES = 48; // machine/sdk/memmap.zig, machine/sdk/audio.zig
const TOP = 40, LEFT = 80; // the 320x200 window in the physical frame (x doubled)
const SR = 44100, BLOCK = 882;

/// The hub's record (apps/zig/scenes/union_demo/return_note.zig write()):
/// "UNI1", payload length 14, XOR of the payload, then door u8, flags u8,
/// x f32, y f32, scroll u32, little-endian.
export function noteBytes({ door, x, y, scroll }) {
    const b = new Uint8Array(20), dv = new DataView(b.buffer);
    b[6] = door; dv.setFloat32(8, x, true); dv.setFloat32(12, y, true); dv.setUint32(16, scroll, true);
    b.set([85, 78, 73, 49], 0); b[4] = 14; b[5] = b.subarray(6).reduce((c, v) => c ^ v, 0);
    return b;
}

/// Boot `cart`; `note` (or null) is planted in the ROM scratch before the cart runs.
export async function boot(cart, note) {
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
    if (!rom.romScratchPtr || !rom.romScratchLen()) throw new Error("docs/rom.wasm has no scratch bytes (romScratchPtr)");
    const scratch = () => new Uint8Array(memory.buffer, rom.romScratchPtr(), rom.romScratchLen());
    if (note) scratch().set(noteBytes(note));
    const cartBytes = await readFile(cart);
    const env = { memory, ...rom };
    for (const k of Object.keys(machine)) if (k.startsWith("hw")) env[k] = machine[k];
    for (const imp of WebAssembly.Module.imports(new WebAssembly.Module(cartBytes)))
        if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => {};
    demo = (await WebAssembly.instantiate(cartBytes, { env })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    const planted = scratch().slice();
    demo.boot();
    demo.skipBoot();
    return { memory, machine, demo, scratch, planted };
}

/// The 320x200 window as the host composites it, over black. The line palette
/// is replayed by the plane's HBL, so this renders every enabled plane.
export function capture({ memory, machine, demo }) {
    const W = machine.hwPhysWidth(), H = machine.hwPhysHeight(), img = new Uint8Array(320 * 200 * 3);
    machine.hwClear();
    let planes = 0;
    for (let p = 0; p < machine.hwPlanesNumber(); p++) {
        if (!demo.isPlaneEnabled(p)) continue;
        planes++;
        machine.hwRenderPlane(p);
        const px = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), W * H * 4);
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
            const i = ((TOP + y) * W + LEFT + x * 2) * 4, a = px[i + 3] / 255, o = (y * 320 + x) * 3;
            for (let c = 0; c < 3; c++) img[o + c] = Math.round(img[o + c] * (1 - a) + px[i + c] * a);
        }
    }
    return { img, planes };
}

export function png(w, h, rgb) {
    const t = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
    const crc = (b) => { let c = 0xffffffff; for (const v of b) c = t[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const raw = Buffer.alloc((w * 3 + 1) * h);
    for (let y = 0; y < h; y++) Buffer.from(rgb.buffer, rgb.byteOffset + y * w * 3, w * 3).copy(raw, y * (w * 3 + 1) + 1);
    const chunk = (type, data) => {
        const b = Buffer.alloc(12 + data.length);
        b.writeUInt32BE(data.length, 0); b.write(type, 4, "latin1"); data.copy(b, 8);
        b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
        return b;
    };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr.set([8, 2, 0, 0, 0], 8);
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

/// The requested tune on the real audio modules, fed the way the worklet feeds a .sndh.
export async function sndhPlay(name, tune, seconds) {
    const memory = new WebAssembly.Memory({ initial: AUDIO_PAGES, maximum: AUDIO_PAGES });
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-audio.wasm"), { env: { memory } })).instance.exports;
    const env = { memory };
    for (const n of Object.keys(machine)) if (n.startsWith("machine")) env[n] = machine[n];
    const audio = (await WebAssembly.instantiate(await readFile("docs/demo-audio.wasm"), { env })).instance.exports;
    audio.audioInit();
    const bytes = new Uint8Array(await readFile(`docs/music/${name}`));
    if (bytes.length > audio.audioSongCapacity()) return { loaded: false, why: "over song capacity" };
    new Uint8Array(memory.buffer, audio.audioSongPtr(), bytes.length).set(bytes);
    if (!audio.audioLoadSndh(bytes.length)) return { loaded: false, why: "audioLoadSndh refused it" };
    audio.audioSndhPlay(tune);
    let peak = 0, secPeak = 0, silent = 0;
    for (let done = 0; done < seconds * SR; done += BLOCK) {
        audio.audioRender(BLOCK);
        for (const v of new Float32Array(memory.buffer, machine.audioLeftPtr(), BLOCK)) { const a = Math.abs(v); peak = Math.max(peak, a); secPeak = Math.max(secPeak, a); }
        if ((done / BLOCK + 1) % 50 === 0) { if (secPeak <= 0.01) silent++; secPeak = 0; }
    }
    return { loaded: true, peak, silent, mode: audio.audioMode(), stuckPc: audio.audioSndhStuckPc() };
}
