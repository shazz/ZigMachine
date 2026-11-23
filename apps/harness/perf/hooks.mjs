// Byte sequences the instrumenter splices into function bodies. Everything they write
// lives in memory 1, a memory the rewriter ADDS to the module (multi-memory), so the
// cart's own memory, function indices and globals never move.
//
// Memory 1 layout (bytes / u32 words):
//   [0, SNAP_BYTES)    a copy of the VRAM pool taken before each frame (the host writes
//                      it), so a store can be compared with what its byte held at frame start
//   LOG_COUNT, BLIT_SITE, STORE_TOTAL, PAL_TOTAL, DTAGS[128], MIS_LOADS, MIS_STORES, then LOG_MAX log entries [kind<<28 | site, dest, len, value|src]
//                      for big fills/copies and every fill/copy into VRAM, this frame
//   BUCKETS            bytes stored into VRAM this frame, per 256-byte bucket
//   FIRST_COUNTER ...  the per-segment and per-site counters (u32, cumulative)
import { encS32, encU32 } from "./wasm_bin.mjs";

export const VRAM_BYTES = 1024 * 1024;           // machine/sdk/memmap.zig VRAM_BYTES
export const SNAP_BYTES = VRAM_BYTES + 64;       // + slack: a wide store at the window's end
export const LOG_MAX = 4096;
export const LOG_COUNT = SNAP_BYTES / 4;
export const BLIT_SITE = LOG_COUNT + 1;          // the hwBlit call site about to run (-1: none)
export const STORE_TOTAL = LOG_COUNT + 2;        // every watched store, ever (HBL share: run_cart)
export const PAL_TOTAL = LOG_COUNT + 3;          // every palette store, ever (per-HBL snoop queue: run_cart)
export const DTAGS = LOG_COUNT + 4;               // the D$ model's 128 line tags (probe_hooks.mjs)
export const MIS_LOADS = DTAGS + 128;            // loads wider than a byte at an address not a multiple of their width, ever
export const MIS_STORES = DTAGS + 129;           // the same for integer stores (the board's `aligned` build traps each: trap.c)
export const LOG_BASE = DTAGS + 130;
export const BUCKET_SHIFT = 8;
export const BUCKETS = LOG_BASE + 4 * LOG_MAX;
export const FIRST_COUNTER = BUCKETS + (VRAM_BYTES >> BUCKET_SHIFT);
export const LOG_MIN_BYTES = 4096;               // a fill/copy outside VRAM is logged from this size
export const KIND_COPY = 1;

export const I32 = (v) => [0x41, ...encS32(v | 0)];
const M1 = (op, wordIdx) => [op, 0x42, 0x01, ...encU32(4 * wordIdx)]; // align 4, memory 1
const M1AT = (op, byteOff) => [op, 0x42, 0x01, ...encU32(byteOff)];
export const LGET = (l) => [0x20, ...encU32(l)];
export const LSET = (l) => [0x21, ...encU32(l)];
export const LTEE = (l) => [0x22, ...encU32(l)];

// counter[word] += <value code>
export const inc = (word, value = I32(1)) =>
    [...I32(0), ...I32(0), ...M1(0x28, word), ...value, 0x6a, ...M1(0x36, word)];

// if (dest in VRAM or n >= LOG_MIN_BYTES) and the log has room: append [tag, dest, n, x].
function logEntry(tag, t, vlo, x) {
    const field = (off, val) => [...LGET(t.c), ...I32(4), 0x74, ...val, ...M1AT(0x36, 4 * LOG_BASE + off)];
    return [
        ...LGET(t.d), ...I32(-vlo), 0x6a, ...I32(VRAM_BYTES), 0x49, ...LGET(t.n), ...I32(LOG_MIN_BYTES), 0x4f, 0x72,
        0x04, 0x40,
        ...I32(0), ...M1(0x28, LOG_COUNT), ...LTEE(t.c), ...I32(LOG_MAX), 0x49, 0x04, 0x40,
        ...field(0, I32(tag)), ...field(4, LGET(t.d)), ...field(8, LGET(t.n)), ...field(12, LGET(x)),
        ...I32(0), ...LGET(t.c), ...I32(1), 0x6a, ...M1(0x36, LOG_COUNT),
        0x0b, 0x0b,
    ];
}

// memory.fill: [d v n] on the stack. Adds n to its byte counter, logs, fills.
export const fillHook = (word, site, t, vlo, original) => [
    ...LSET(t.n), ...LSET(t.v), ...LSET(t.d), ...inc(word, LGET(t.n)), ...logEntry(site, t, vlo, t.v),
    ...LGET(t.d), ...LGET(t.v), ...LGET(t.n), ...original,
];

// memory.copy: [d s n] on the stack (t.v holds s). Adds n to its byte counter (`word`) and,
// when the source is misaligned against the destination ((d ^ s) & 3 != 0, n >= 8: the board's
// zm_string.c copy_fwd then builds every word from four byte loads), n to `word + 1`; logs, copies.
export const copyHook = (word, site, t, vlo, original) => [
    ...LSET(t.n), ...LSET(t.v), ...LSET(t.d), ...inc(word, LGET(t.n)),
    ...inc(word + 1, [...LGET(t.n), ...I32(0), ...LGET(t.d), ...LGET(t.v), 0x73, ...I32(3), 0x71, 0x45, 0x45,
        ...LGET(t.n), ...I32(8), 0x4f, 0x71, 0x1b]), // select(n, 0, misaligned && n >= 8)
    ...logEntry((KIND_COPY << 28) | site, t, vlo, t.v),
    ...LGET(t.d), ...LGET(t.v), ...LGET(t.n), ...original,
];

// A call to the hwBlit import: name the site for the host's wrapper, then clear it.
export const blitSiteHook = (site, original) =>
    [...I32(0), ...I32(site), ...M1(0x36, BLIT_SITE), ...original, ...I32(0), ...I32(-1), ...M1(0x36, BLIT_SITE)];
