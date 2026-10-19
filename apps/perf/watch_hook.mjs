// The store watch: spliced around every integer store of the cart and the ROM.
//   palette window: count the write, and count it again when it writes the colour already
//     there (a raster coder never rewrites a register that holds the right colour);
//   VRAM pool: count stores and bytes, those whose value equals the byte(s) at FRAME START
//     (the snapshot in memory 1: a static page redrawn, a clear undone by its redraw), and
//     add the bytes to the address's 256-byte bucket (per-plane / per-row accounting).
// Counters per site: [pal writes, pal unchanged, vram stores, vram bytes, same stores, same bytes].
import { I32, LGET, LSET, LTEE, inc, BUCKETS, BUCKET_SHIFT, VRAM_BYTES, STORE_TOTAL, PAL_TOTAL, MIS_STORES } from "./hooks.mjs";
import { encU32 } from "./wasm_bin.mjs";

export const WATCH_WORDS = 6;
// store op -> [width, value is i64, the matching unsigned load (i32 or i64 form)]
const STORES = {
    0x36: [4, false, 0x28], 0x3b: [2, false, 0x2f], 0x3a: [1, false, 0x2d],
    0x37: [8, true, 0x29], 0x3e: [4, true, 0x35], 0x3d: [2, true, 0x33], 0x3c: [1, true, 0x31],
};
export const WATCHED = new Set(Object.keys(STORES).map(Number));
function sleb64(v) {
    const o = [];
    for (let n = BigInt(v); ;) {
        const b = Number(n & 0x7fn);
        n >>= 7n;
        if ((n === 0n && !(b & 0x40)) || (n === -1n && b & 0x40)) { o.push(b); return o; }
        o.push(b | 0x80);
    }
}
const and64 = (m) => [0x42, ...sleb64(m), 0x83];
const MASK32 = { 4: [], 2: [...I32(0xffff), 0x71], 1: [...I32(0xff), 0x71] };
const MASK64 = { 8: [], 4: and64(0xffffffff), 2: and64(0xffff), 1: and64(0xff) };
const m0 = (op, off) => [op, 0x00, ...encU32(off)];           // memory 0, align 1
const m1 = (op, off) => [op, 0x40, 0x01, ...encU32(off)];     // memory 1, align 1

// value as compared: tv (i32) or tw (i64), masked to the store's width
const value = (w, wide, t) => (wide ? [...LGET(t.w), ...MASK64[w]] : [...LGET(t.v), ...MASK32[w]]);

function palBlock(word, op, offset, pal, t) {
    if (!pal || STORES[op][1]) return [];
    const [w, , load] = STORES[op];
    return [
        ...LGET(t.a), ...I32(offset - pal[0]), 0x6a, ...I32(pal[1] - pal[0]), 0x49, 0x04, 0x40,
        ...inc(word), ...inc(PAL_TOTAL),
        ...inc(word + 1, [...LGET(t.a), ...m0(load, offset), ...value(w, false, t), 0x46]),
        0x0b,
    ];
}

function vramBlock(word, op, offset, vlo, t) {
    const [w, wide, load] = STORES[op];
    const bucket = [...LGET(t.r), ...I32(BUCKET_SHIFT), 0x76, ...I32(2), 0x74, 0x22, ...encU32(t.b), ...LGET(t.b),
        0x28, 0x42, 0x01, ...encU32(4 * BUCKETS), ...I32(w), 0x6a, 0x36, 0x42, 0x01, ...encU32(4 * BUCKETS)];
    return [
        ...LGET(t.a), ...I32(offset - vlo), 0x6a, ...LTEE(t.r), ...I32(VRAM_BYTES), 0x49, 0x04, 0x40,
        ...inc(word + 2), ...inc(word + 3, I32(w)), ...bucket,
        ...LGET(t.r), ...m1(load, 0), ...value(w, wide, t), wide ? 0x51 : 0x46, 0x04, 0x40,
        ...inc(word + 4), ...inc(word + 5, I32(w)),
        0x0b, 0x0b,
    ];
}

// A wide store at an address that is not a multiple of its width traps on the board.
function misaligned(word, op, offset, t, site) {
    const w = STORES[op][0];
    if (w === 1) return [];
    return [...LGET(t.a), ...I32(offset), 0x6a, ...I32(Math.min(w, 4) - 1), 0x71, 0x04, 0x40, ...inc(word), ...inc(site), 0x0b];
}

// [addr val] on the stack -> the checks, then the original store
export function watchHook(word, op, offset, pal, vlo, t, original, misSite) {
    const wide = STORES[op][1];
    return [
        ...LSET(wide ? t.w : t.v), ...LSET(t.a), ...inc(STORE_TOTAL),
        ...misaligned(MIS_STORES, op, offset, t, misSite),
        ...palBlock(word, op, offset, pal, t), ...vramBlock(word, op, offset, vlo, t),
        ...LGET(t.a), ...LGET(wide ? t.w : t.v), ...original,
    ];
}
