// A PNG of a frame for scene_hash.mjs's SCENE_PNG=F:path (the picture the page shows: the enabled
// planes stacked as its canvases are). For docs and reviews; nothing is checked by it.
import { writeFileSync } from "node:fs";
import zlib from "node:zlib";

const TABLE = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
});

function crc(b) {
    let c = 0xffffffff;
    for (const x of b) c = TABLE[(c ^ x) & 255] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
    const len = Buffer.alloc(4), sum = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    sum.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, sum]);
}

/** RGBA bytes (alpha 0 shown black, as the page's tube) of w x h -> path. */
export function writePng(path, rgba, w, h) {
    const raw = Buffer.alloc((w * 4 + 1) * h);
    for (let y = 0; y < h; y++)
        for (let x = 0; x < w * 4; x += 4) {
            const s = (y * w) * 4 + x, d = y * (w * 4 + 1) + 1 + x, a = rgba[s + 3];
            raw[d] = a ? rgba[s] : 0; raw[d + 1] = a ? rgba[s + 1] : 0; raw[d + 2] = a ? rgba[s + 2] : 0; raw[d + 3] = 255;
        }
    const ih = Buffer.alloc(13);
    ih.writeUInt32BE(w, 0);
    ih.writeUInt32BE(h, 4);
    ih[8] = 8;
    ih[9] = 6;
    const png = [Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ih), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))];
    writeFileSync(path, Buffer.concat(png));
}
