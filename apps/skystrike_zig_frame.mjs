// SKYSTRIKE ZIG-mode harness, the displayed frame: the enabled planes
// composited as the host stacks their canvases (docs/sealed-loader.js: each
// plane rendered into the physical frame and drawn over the last, its
// transparent pixels showing what is under), and PNG screenshots of it.
import { writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";

export const RW = 800, RH = 280; // the physical frame, x doubled

/// The frame as the host would show it, 800 x 280 RGBA words.
export function grab(s) {
    const out = new Uint32Array(RW * RH);
    const pfb = new Uint32Array(s.memory.buffer, s.machine.hwPhysicalPtr(), RW * RH);
    s.machine.hwClear();
    let first = true;
    for (let p = 0; p < 4; p++) {
        if (!s.demo.isPlaneEnabled(p)) continue;
        s.machine.hwRenderPlane(p);
        for (let i = 0; i < out.length; i++) if (first || pfb[i] >>> 24) out[i] = pfb[i];
        first = false;
    }
    if (first) out.set(pfb);
    return out;
}

/// The 400 x 280 low-res pixels of a frame (every other physical pixel).
export function lowres(frame) {
    const out = new Uint32Array(400 * RH);
    for (let y = 0; y < RH; y++) for (let x = 0; x < 400; x++) out[y * 400 + x] = frame[y * RW + 2 * x];
    return out;
}

function crc32(buf) {
    let c, crc = 0xffffffff;
    for (let n = 0; n < buf.length; n++) {
        c = (crc ^ buf[n]) & 0xff;
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        crc = (crc >>> 8) ^ c;
    }
    return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
}

/// A w x h RGBA-word image (R in the low byte) as a PNG, scaled up `k` times.
export async function png(path, px, w, h, k = 2) {
    const W = w * k, H = h * k;
    const raw = Buffer.alloc((W * 3 + 1) * H);
    for (let y = 0; y < H; y++) {
        raw[y * (W * 3 + 1)] = 0;
        for (let x = 0; x < W; x++) {
            const p = px[((y / k) | 0) * w + ((x / k) | 0)];
            const o = y * (W * 3 + 1) + 1 + x * 3;
            raw[o] = p & 255; raw[o + 1] = (p >> 8) & 255; raw[o + 2] = (p >> 16) & 255;
        }
    }
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
    ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
    const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    await writeFile(path, Buffer.concat([sig, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
}
