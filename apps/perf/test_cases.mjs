// The planted patterns of perf_audit_test.mjs: frame() bodies WITH each bad pattern and
// a clean twin doing the same work the right way. Locals (fixture.mjs): 0 dt (f32),
// 1-4 i32, 5-6 i64, 7-8 f64, 9-10 f32. Function 5 is "sinf" where a case declares it.
import { I, loop, BUF, BUF2, PAL } from "./fixture.mjs";

const fill = (dst, v, n) => [...I.i32(dst), ...I.i32(v), ...I.i32(n), ...I.fill];
// compiler-rt's sinf works in f64: promote, a polynomial, demote
const SINF = { extra: [{ name: "sinf", type: "f32f32", body: [...I.get(0), 0xbb, ...I.f64(1.5), ...I.f64mul,
    ...I.f64(0.25), ...I.f64add, ...I.f64(0.75), ...I.f64mul, ...I.f64(0.125), ...I.f64add, 0xb6] }] };
const i32Loop = [...loop(1, 2000, [...I.get(2), ...I.i32(3), ...I.mul, ...I.i32(1), ...I.add, ...I.set(2)]),
    ...I.i32(0), ...I.get(2), ...I.store(BUF)];
const counter = [...I.i32(0), ...I.i32(0), ...I.load(BUF2 + 64), ...I.i32(1), ...I.add, ...I.tee(4), ...I.store(BUF2 + 64)];

export const CASES = [
    { pattern: "byte_fill", dynamic: "byte_fill", first: true, mc: [1.5, 2.5], // 64,000 byte stores: empire's clear
        with: loop(1, 64000, [...I.get(1), ...I.i32(0), ...I.store8(BUF)]),
        without: fill(BUF, 0, 64000) },
    { pattern: "byte_copy", dynamic: "byte_copy",
        with: loop(1, 32000, [...I.get(1), ...I.get(1), ...I.load8(BUF2), ...I.store8(BUF)]),
        without: [...I.i32(BUF), ...I.i32(BUF2), ...I.i32(32000), ...I.copy] },
    { pattern: "f64_loop", dynamic: "f64_loop", first: true, cause: "f64",
        with: [...loop(1, 20000, [...I.get(7), ...I.f64(1.0001), ...I.f64mul, ...I.f64(0.5), ...I.f64add, ...I.set(7)]),
            ...I.i32(0), ...I.get(7), ...I.f64store(BUF)],
        without: i32Loop },
    { pattern: "libm_loop", opts: SINF, dynamic: "table_rebuild_per_frame", lintAs: "libm_loop",
        with: loop(1, 1024, [...I.get(1), ...I.i32(2), ...I.shl, ...I.get(1), ...I.f32cvt, ...I.call(5), ...I.f32store(BUF)]),
        without: [...loop(1, 1024, [...I.get(1), ...I.i32(2), ...I.shl, ...I.get(1), ...I.f32cvt, ...I.f32store(BUF)]),
            ...I.f32(1), ...I.call(5), ...I.drop] },
    { pattern: "table_rebuild", opts: SINF,
        with: loop(1, 256, [...I.get(1), ...I.i32(2), ...I.shl, ...I.get(1), ...I.f32cvt, ...I.call(5), ...I.f32store(BUF)]),
        without: [...I.f32(1), ...I.call(5), ...I.drop] },
    { pattern: "div_loop", dynamic: "div_loop",
        with: [...I.i32(0), ...I.i32(7), ...I.store(BUF2), ...I.i32(0), ...I.load(BUF2), ...I.set(3),
            ...loop(1, 20000, [...I.get(1), ...I.get(1), ...I.get(3), ...I.divu, ...I.store8(BUF)])],
        without: loop(1, 20000, [...I.get(1), ...I.get(1), ...I.i32(7), ...I.divu, ...I.store8(BUF)]) },
    { pattern: "i64_loop", dynamic: "i64_loop",
        with: [...loop(1, 20000, [...I.get(5), ...I.i64(3), ...I.i64mul, ...I.get(1), ...I.i64ext, ...I.i64add, ...I.set(5)]),
            ...I.i32(0), ...I.get(5), ...I.i64store(BUF)],
        without: i32Loop },
    { pattern: "float_phase",
        with: [...I.i32(BUF), ...I.set(2), ...I.get(2), ...I.get(2), ...I.f32load(0), ...I.f32(0.01), ...I.f32add, ...I.f32store(0)],
        without: [...I.i32(BUF), ...I.set(2), ...I.get(2), ...I.get(2), ...I.load(0), ...I.i32(1), ...I.add, ...I.store(0)] },
    { pattern: "pixel_call", dynamic: "pixel_call", // setPixel(x, c) called per pixel, vs the store in the loop
        opts: { extra: [{ name: "setPixel", type: "i32i32v", body: [...I.get(0), ...I.get(1), ...I.store8(BUF)] }] },
        with: loop(1, 20000, [...I.get(1), ...I.get(1), ...I.call(5)]),
        without: loop(1, 20000, [...I.get(1), ...I.get(1), ...I.store8(BUF)]) },
    { pattern: "palette_rewrite", dynamicOnly: true, dynamic: "palette_rewrite", // 600 colour writes a frame...
        with: loop(1, 600, [...I.get(1), ...I.i32(255), 0x71, ...I.i32(2), ...I.shl, ...I.i32(0x00112233), ...I.store(PAL)]),
        without: [...counter, ...loop(1, 600, [...I.get(1), ...I.i32(255), 0x71, ...I.i32(2), ...I.shl, // ...each a new colour
            ...I.get(4), ...I.i32(1000), ...I.mul, ...I.get(1), ...I.add, ...I.store(PAL)])] },
    { pattern: "cleared_redrawn", dynamicOnly: true, dynamic: "cleared_redrawn", // the plane cleared, then all of it drawn
        with: [...fill(BUF, 0, 64000), ...loop(1, 16000, [...I.get(1), ...I.i32(2), ...I.shl, ...I.i32(0x01010101), ...I.store(BUF)])],
        without: [...fill(BUF, 0, 64000), ...loop(1, 100, [...I.get(1), ...I.i32(2), ...I.shl, ...I.i32(0x01010101), ...I.store(BUF)])] },
];
