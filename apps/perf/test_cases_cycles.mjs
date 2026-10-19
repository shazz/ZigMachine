// The cycle-waste detectors' planted patterns (probe_hooks.mjs, cycle_report.mjs): each
// pattern in frame(), against a twin doing the same work without the waste. Locals
// (fixture.mjs): 1-4 i32, 5-6 i64, 7-8 f64, 9-10 f32; fn(0) is the first helper.
import { I, loop, fn, BUF, BUF2 } from "./fixture.mjs";

const N = 20000;
const seven = [...I.i32(0), ...I.i32(7), ...I.store(BUF2), ...I.i32(0), ...I.load(BUF2), ...I.set(3)]; // 7, not a constant
const ADD1 = { extra: [{ name: "add1", type: "i32i32", body: [...I.get(0), ...I.i32(1), ...I.add] }] };
const f64cvt = [0xb7];  // f64.convert_i32_s
const extend = [0xac];  // i64.extend_i32_s
const branchy = (cond) => loop(1, N, [...cond, 0x04, 0x40, ...I.get(1), ...I.get(1), ...I.store8(BUF), 0x05,
    ...I.get(1), ...I.i32(1), ...I.store8(BUF), 0x0b]);

export const CYCLE_CASES = [
    { pattern: "div_loop", // a divide by a value that never changes, vs the multiply it could be
        with: [...seven, ...loop(1, N, [...I.get(1), ...I.get(1), ...I.get(3), ...I.divu, ...I.store8(BUF)])],
        without: [...seven, ...loop(1, N, [...I.get(1), ...I.get(1), ...I.get(3), ...I.mul, ...I.store8(BUF)])] },
    { pattern: "recompute", // a*b with a and b fixed for the whole loop, vs a*i
        with: [...I.f64(1.5), ...I.set(7), ...I.f64(2.5), ...I.set(8),
            ...loop(1, N, [...I.i32(0), ...I.get(7), ...I.get(8), ...I.f64mul, ...I.f64store(BUF)])],
        without: [...I.f64(1.5), ...I.set(7),
            ...loop(1, N, [...I.i32(0), ...I.get(7), ...I.get(1), ...f64cvt, ...I.f64mul, ...I.f64store(BUF)])] },
    { pattern: "cache_hostile", // bytes 256 apart over 256 KB (a column walk), vs consecutive bytes
        with: loop(1, N, [...I.get(2), ...I.get(1), ...I.i32(8), ...I.shl, ...I.i32(0x3ffff), ...I.and, ...I.load8(BUF), ...I.add, ...I.set(2)]),
        without: loop(1, N, [...I.get(2), ...I.get(1), ...I.load8(BUF), ...I.add, ...I.set(2)]) },
    { pattern: "call_in_loop", opts: ADD1, // add1(i) called per iteration, vs i + 1 in the loop
        with: loop(1, N, [...I.get(1), ...I.get(1), ...I.call(fn(0)), ...I.store8(BUF)]),
        without: loop(1, N, [...I.get(1), ...I.get(1), ...I.i32(1), ...I.add, ...I.store8(BUF)]) },
    { pattern: "i64_fits_i32", // i * 3 in i64 that always fits, vs (i << 40) * 3 that never does
        with: loop(1, N, [...I.get(5), ...I.get(1), ...extend, ...I.i64(3), ...I.i64mul, ...I.i64add, ...I.set(5)]),
        without: loop(1, N, [...I.get(1), ...extend, ...I.i64(40), 0x86, ...I.i64(3), ...I.i64mul, ...I.set(5)]) },
    { pattern: "misaligned", // i32 loads 4 apart from an odd address, vs the same loads from an aligned one
        with: loop(1, N, [...I.get(2), ...I.get(1), ...I.i32(2), ...I.shl, ...I.load1(BUF + 1), ...I.add, ...I.set(2)]),
        without: loop(1, N, [...I.get(2), ...I.get(1), ...I.i32(2), ...I.shl, ...I.load1(BUF), ...I.add, ...I.set(2)]) },
    { pattern: "invariant_branch", // a flag fixed for the frame tested per pixel, vs a test that alternates
        with: [...I.i32(0), ...I.load(BUF2 + 128), ...I.set(4), ...branchy(I.get(4))],
        without: branchy([...I.get(1), ...I.i32(1), ...I.and]) },
].map((c) => ({ dynamicOnly: true, waste: true, ...c }));
