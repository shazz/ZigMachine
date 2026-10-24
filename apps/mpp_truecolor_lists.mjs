// mpp_truecolor's copper lists (apps/zig/scenes/mpp_truecolor/cop.zig), read back from the
// machine for apps/mpp_truecolor_headless.mjs: every plane the mode shows carries a list whose
// line y (raster line TOP + y) loads exactly the converter's record for that line, the
// palette words included, and no HBL handler stores them as well.
import { readFile } from "node:fs/promises";
import { copperRecords } from "./copper_lines.mjs";

const W = 320, H = 200, PLANES = 4, TOP = 40; // blob.zig, VERTICAL_BORDERS_HEIGHT
const REG_FB_HBL_ID = 0x20; // memmap.zig

// The converter's map and its palette widened to RGBA words (blob.zig's decode).
async function source(dir, picture, mode) {
    const b = await readFile(`${dir}/p${picture}_m${mode + 1}.bin`);
    const planes = mode < 2 ? 1 : PLANES;
    const head = PLANES * H * 8 + (planes === 1 ? W * H : 2 * W * H);
    const rgb = Uint8Array.from(b.subarray(head));
    for (let i = 3; i < rgb.length; i++) rgb[i] = (rgb[i] + rgb[i - 3]) & 255;
    const pal = new Uint32Array(rgb.length / 3);
    for (let j = 0; j < pal.length; j++) pal[j] = ((255 << 24) | (rgb[3 * j + 2] << 16) | (rgb[3 * j + 1] << 8) | rgb[3 * j]) >>> 0;
    const dv = new DataView(b.buffer, b.byteOffset);
    const map = (p, y) => ({ off: dv.getUint32((p * H + y) * 8, true), span: dv.getUint32((p * H + y) * 8 + 4, true) });
    return { planes, pal, map };
}

/** Errors (strings) for picture/mode's lists in the running machine. */
export async function checkLists(memory, vb, dir, picture, mode) {
    const { planes, pal, map } = await source(dir, picture, mode), errors = [], tag = `p${picture} mode ${mode + 1}`;
    const regs = new DataView(memory.buffer, vb);
    for (let p = 0; p < planes; p++) {
        if (regs.getUint16(REG_FB_HBL_ID + 2 * p, true)) errors.push(`${tag} plane ${p}: an HBL handler beside the list`);
        const recs = copperRecords(memory, vb, p);
        if (!recs) { errors.push(`${tag} plane ${p}: no copper list`); continue; }
        const at = new Map(recs.map((r) => [r.line, r]));
        let lines = 0;
        for (let y = 0; y < H; y++) {
            const { off, span } = map(p, y), first = span & 0xffff, n = span >>> 16;
            if (n === 0) continue;
            lines++;
            const r = at.get(TOP + y);
            const bad = !r || r.pal.size !== n || [...Array(n).keys()].some((j) => r.pal.get(first + j) !== pal[off / 4 + j]);
            if (bad) { errors.push(`${tag} plane ${p} line ${y}: the list does not load the record (${n} entries from ${first})`); break; }
        }
        if (recs.length !== lines) errors.push(`${tag} plane ${p}: ${recs.length} records for ${lines} record lines`);
    }
    return errors;
}

/** --break k1tail: a 256-entry line's second PALREF (entry 255) made a NOP, in every list. */
export function dropTails(memory, vb) {
    const dv = new DataView(memory.buffer, vb);
    for (let p = 0; p < PLANES; p++) {
        const v = dv.getUint16(0x78 + 2 * p, true);
        if (!v) continue;
        for (let at = 0x1100 + 16 * v; ; ) {
            const head = dv.getUint32(at, true), n = head & 0x3ff;
            if ((head >>> 19 & 0x1ff) === 511 || head >>> 28 !== 0xf) break;
            if (n === 4) dv.setUint32(at + 12, 0, true), dv.setUint32(at + 16, 0, true);
            at += 4 + 4 * n;
        }
    }
}
