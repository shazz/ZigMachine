// What a frame actually changed: the VRAM pool against its frame-start copy (per 256-byte
// bucket), each enabled plane's rows, the composed picture's lines, and rows whose new
// content is the old one shifted sideways (a scroller rewritten instead of panned).
import { VRAM_BYTES, BUCKET_SHIFT } from "./hooks.mjs";
import { OFF_VRAM } from "./run_cart.mjs";

const REG_FB_STRIDE = 0x34, REG_FB_BASE = 0x44, REG_FB_MODE = 0x54; // machine/sdk/memmap.zig
export const PFB_OFF = OFF_VRAM + VRAM_BYTES, PFB_W = 800, PFB_H = 280;
const MAX_SHIFT = 16;

// Enabled planes: where their visible rows sit in the VRAM pool (offsets into it).
export function planes(run, base) {
    const v = new DataView(run.memory.buffer), out = [];
    for (let p = 0; p < run.machine.hwPlanesNumber(); p++) {
        if (!run.demo.isPlaneEnabled(p)) continue;
        const mode = v.getUint8(base + REG_FB_MODE + p), stride = v.getUint16(base + REG_FB_STRIDE + 2 * p, true);
        const big = mode === 1 || mode === 4;
        const off = v.getUint32(base + REG_FB_BASE + 4 * p, true) - OFF_VRAM;
        const rows = big ? 280 : 200, width = mode === 3 ? 640 : big ? 400 : 320;
        if (off < 0 || off + stride * rows > VRAM_BYTES || stride < width) continue; // not in the pool
        out.push({ p, off, stride, rows, width });
    }
    return out;
}

// changed bytes per bucket, VRAM now against its frame-start copy (both Uint8Array)
export function diffBuckets(now, snap) {
    const a = new Uint32Array(now.buffer, now.byteOffset, now.length >> 2);
    const b = new Uint32Array(snap.buffer, snap.byteOffset, snap.length >> 2);
    const out = new Uint32Array(VRAM_BYTES >> BUCKET_SHIFT);
    for (let i = 0; i < a.length; i++) {
        const x = a[i] ^ b[i];
        if (x) out[i >> (BUCKET_SHIFT - 2)] += ((x & 0xff) !== 0) + ((x & 0xff00) !== 0) + ((x & 0xff0000) !== 0) + ((x >>> 24) !== 0);
    }
    return out;
}

export const sumBuckets = (b, off, len) => {
    let s = 0;
    for (let i = off >> BUCKET_SHIFT; i <= (off + len - 1) >> BUCKET_SHIFT; i++) s += b[i];
    return s;
};

// composed-picture lines that differ from the previous frame's (prev updated in place)
export function changedLines(memory, base, prev) {
    const now = new Uint32Array(memory.buffer, base + PFB_OFF, PFB_W * PFB_H);
    let n = 0;
    for (let y = 0; y < PFB_H; y++) {
        const o = y * PFB_W;
        for (let x = 0; x < PFB_W; x++) if (now[o + x] !== prev[o + x]) { n++; break; }
    }
    prev.set(now);
    return n;
}

// k (1..16, signed: content moved left < 0) if row `now` is row `old` shifted by k,
// all but the k new pixels matching; 0 if not, or if the row is flat (anything matches).
export function rowShift(now, old) {
    const w = now.length;
    let flat = true;
    for (let x = 1; x < w && flat; x++) if (now[x] !== now[0]) flat = false;
    if (flat) return 0;
    for (let k = 1; k <= MAX_SHIFT; k++) {
        for (const dir of [-1, 1]) {
            let ok = true;
            for (let x = 0; x < w - k && ok; x++) ok = dir < 0 ? now[x] === old[x + k] : now[x + k] === old[x];
            if (ok) return dir * k;
        }
    }
    return 0;
}

// rows of plane pl that changed and are their frame-start content shifted sideways
export function shiftedRows(now, snap, pl) {
    const rows = [];
    for (let y = 0; y < pl.rows; y++) {
        const o = pl.off + y * pl.stride;
        const a = now.subarray(o, o + pl.width), b = snap.subarray(o, o + pl.width);
        if (!a.some((v, i) => v !== b[i])) continue;
        const k = rowShift(a, b);
        if (k) rows.push({ y, k });
    }
    return rows;
}
