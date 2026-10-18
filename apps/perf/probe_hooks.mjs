// Round-3 probes: what the CPU's cycles go to, measured on the real address and value
// streams. Each probe replaces one instruction with checks + the original instruction.
//   load:   a D$ model (4 KiB, direct-mapped, 32-byte lines: 128 tags in memory 1) ->
//           [misses, strided (|address - this site's last| >= a line), lastAddr]
//   value:  the operands of a costly op against its previous execution ->
//           [same operands, same 2nd operand, lastA lo/hi, lastB lo/hi]
//   fit:    an i64 result that fits in an i32 -> [fits]
//   branch: an in-loop condition that flips -> [changes, last]
import { I32, LGET, LSET, LTEE, inc, DTAGS } from "./hooks.mjs";
import { encU32 } from "./wasm_bin.mjs";

export const PROBE_WORDS = { load: 3, value: 6, fit: 1, branch: 2 };
export const PROBE_COUNTERS = { load: 2, value: 2, fit: 1, branch: 1 }; // the cumulative ones (first words)
const m1 = (op, align, byteOff) => [op, 0x40 | align, 0x01, ...encU32(byteOff)];
const ld32 = (w) => [...I32(0), ...m1(0x28, 2, 4 * w)];
const st32 = (w, v) => [...I32(0), ...v, ...m1(0x36, 2, 4 * w)];
const ld64 = (w) => [...I32(0), ...m1(0x29, 3, 4 * w)];
const st64 = (w, v) => [...I32(0), ...v, ...m1(0x37, 3, 4 * w)];

// [addr] on the stack -> D$ model, stride, the original load
export function loadProbe(word, offset, t, original) {
    return [
        ...LSET(t.p1),
        ...LGET(t.p1), ...I32(offset), 0x6a, ...LTEE(t.p2),
        ...I32(5), 0x76, ...LTEE(t.r), ...I32(127), 0x71, ...I32(2), 0x74, ...LTEE(t.b),
        ...m1(0x28, 2, 4 * DTAGS), ...LGET(t.r), ...I32(1), 0x6a, 0x47, 0x04, 0x40,
        ...inc(word), ...LGET(t.b), ...LGET(t.r), ...I32(1), 0x6a, ...m1(0x36, 2, 4 * DTAGS),
        0x0b,
        ...inc(word + 1, [...LGET(t.p2), ...ld32(word + 2), 0x6b, ...I32(31), 0x6a, ...I32(62), 0x4b]),
        ...st32(word + 2, LGET(t.p2)),
        ...LGET(t.p1), ...original,
    ];
}

// operand kinds: how to hold one in a temp and compare/store it as bits
const KIND = {
    i32: { a: "p1", b: "p2", bits: [], eq: 0x46, wide: false },
    f32: { a: "x1", b: "x2", bits: [0xbc], eq: 0x46, wide: false },
    i64: { a: "q1", b: "q2", bits: [], eq: 0x51, wide: true },
    f64: { a: "y1", b: "y2", bits: [0xbd], eq: 0x51, wide: true },
};
const same = (k, tmp, w) => [...LGET(tmp), ...k.bits, ...(k.wide ? ld64(w) : ld32(w)), k.eq];
const keep = (k, tmp, w) => (k.wide ? st64(w, [...LGET(tmp), ...k.bits]) : st32(w, [...LGET(tmp), ...k.bits]));

// [a b] (n = 2) or [a] (n = 1) of kind on the stack -> repeat counters, the original op
export function valueProbe(word, kind, n, t, original) {
    const k = KIND[kind], A = t[k.a], B = t[k.b];
    if (n === 1) return [...LSET(A), ...inc(word, same(k, A, word + 2)), ...keep(k, A, word + 2), ...LGET(A), ...original];
    return [
        ...LSET(B), ...LSET(A),
        ...inc(word, [...same(k, A, word + 2), ...same(k, B, word + 4), 0x71]),
        ...inc(word + 1, same(k, B, word + 4)),
        ...keep(k, A, word + 2), ...keep(k, B, word + 4),
        ...LGET(A), ...LGET(B), ...original,
    ];
}

// the original i64 op, then: does its result fit in an i32 (sign-extended)?
export const fitProbe = (word, t, original) => [
    ...original, ...LSET(t.q1),
    ...inc(word, [...LGET(t.q1), ...LGET(t.q1), 0xa7, 0xac, 0x51]),
    ...LGET(t.q1),
];

// [cond] on the stack -> count flips against the last value, the original br_if / if
export const branchProbe = (word, t, original) => [
    ...LSET(t.p1),
    ...inc(word, [...LGET(t.p1), 0x45, 0x45, ...ld32(word + 1), 0x47]),
    ...st32(word + 1, [...LGET(t.p1), 0x45, 0x45]),
    ...LGET(t.p1), ...original,
];
