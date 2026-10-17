// Byte sequences the instrumenter splices into function bodies. Every counter lives in
// memory 1, a memory the rewriter ADDS to the module (multi-memory), so the cart's own
// memory, function indices and globals never move. Counters are u32 words.
import { encS32, encU32 } from "./wasm_bin.mjs";

// Counter memory layout (u32 word index):
export const LOG_MAX = 256;            // big fills logged per frame: [site, dest, len, value]
export const LOG_COUNT = 0;            // word 0: entries used this frame
export const LOG_BASE = 1;             // words 1 .. 1 + 4*LOG_MAX
export const FIRST_COUNTER = LOG_BASE + 4 * LOG_MAX;
export const LOG_MIN_BYTES = 4096;     // smaller fills are counted, not logged

const I32_CONST = (v) => [0x41, ...encS32(v | 0)];
const M1 = (op, wordIdx) => [op, 0x42, 0x01, ...encU32(4 * wordIdx)]; // align 4, memory 1
const M1AT = (op, byteOff) => [op, 0x42, 0x01, ...encU32(byteOff)];
const LGET = (l) => [0x20, ...encU32(l)];
const LSET = (l) => [0x21, ...encU32(l)];
const LTEE = (l) => [0x22, ...encU32(l)];

// counter[word] += <value code>
export const inc = (word, value = I32_CONST(1)) =>
    [...I32_CONST(0), ...I32_CONST(0), ...M1(0x28, word), ...value, 0x6a, ...M1(0x36, word)];

// memory.fill: [d v n] on the stack. Adds n to its byte counter, logs big fills, fills.
export function fillHook(word, site, t, original) {
    const logField = (off, val) => [...LGET(t.c), ...I32_CONST(4), 0x74, ...val, ...M1AT(0x36, 4 * LOG_BASE + off)];
    return [
        ...LSET(t.n), ...LSET(t.v), ...LSET(t.d),
        ...inc(word, LGET(t.n)),
        ...LGET(t.n), ...I32_CONST(LOG_MIN_BYTES), 0x4f, 0x04, 0x40,           // if n >= LOG_MIN_BYTES
        ...I32_CONST(0), ...M1(0x28, LOG_COUNT), ...LTEE(t.c), ...I32_CONST(LOG_MAX), 0x49, 0x04, 0x40,
        ...logField(0, I32_CONST(site)), ...logField(4, LGET(t.d)),
        ...logField(8, LGET(t.n)), ...logField(12, LGET(t.v)),
        ...I32_CONST(0), ...LGET(t.c), ...I32_CONST(1), 0x6a, ...M1(0x36, LOG_COUNT),
        0x0b, 0x0b,
        ...LGET(t.d), ...LGET(t.v), ...LGET(t.n), ...original,
    ];
}

// memory.copy: [d s n] on the stack. Adds n to its byte counter, copies.
export const copyHook = (word, t, original) =>
    [...LSET(t.n), ...inc(word, LGET(t.n)), ...LGET(t.n), ...original];

const CMP_LOAD = { 0x36: [0x28, 0x00], 0x3b: [0x2f, 0x00], 0x3a: [0x2d, 0x00] }; // load matching the store
const MASK = { 0x36: [], 0x3b: [...I32_CONST(0xffff), 0x71], 0x3a: [...I32_CONST(0xff), 0x71] };

// An i32 store (32/16/8) into the palette window [lo, hi): count it, and count it again
// when it writes the value already there (a raster coder never rewrites a register that
// already holds the right colour). [addr val] on the stack.
export function palHook(word, op, offset, lo, hi, t, original) {
    return [
        ...LSET(t.v), ...LTEE(t.a),
        ...I32_CONST(offset - lo), 0x6a, ...I32_CONST(hi - lo), 0x49, 0x04, 0x40,
        ...inc(word),
        ...inc(word + 1, [...LGET(t.a), ...CMP_LOAD[op], ...encU32(offset), ...LGET(t.v), ...MASK[op], 0x46]),
        0x0b,
        ...LGET(t.a), ...LGET(t.v), ...original,
    ];
}
export const PAL_STORES = new Set([0x36, 0x3b, 0x3a]);
