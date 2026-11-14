// ASTROLABE's kernels and the machine's hwAstro, natively (build.sh NATIVE_TESTS).
const std = @import("std");
const abi = @import("sdk/astro.zig");
const ops = @import("astro_ops.zig");
const astro = @import("astro.zig");
const t = std.testing;

const SIZE = 1 << 20;
var buf: [SIZE]u8 align(8) = undefined;
const mem = ops.Mem{ .ptr = &buf, .size = SIZE };
const DESC: u32 = 0x100;
const A: u32 = 0x1000;
const B: u32 = 0x60000;
const C: u32 = 0x80000;

fn desc(at: u32, op: u32, n: u32, m: u32, lda: u32, a: u32, b: u32, c: u32, s: [3]f64) void {
    const w = [_]u32{ op, n, m, lda, a, b, c, 0, 0xEEEE, 0xEEEE };
    for (w, 0..) |v, i| mem.st32(at + 4 * @as(u32, @intCast(i)), v);
    for (s, 0..) |v, i| mem.st64(at + 4 * (abi.W_S0 + 2 * @as(u32, @intCast(i))), v);
    mem.st64(at + 4 * abi.W_R, -7);
}

fn r(at: u32) f64 {
    return mem.ld64(at + 4 * abi.W_R);
}

fn scalar1(op: u32, a: f64, b: f64, c: f64) !f64 {
    desc(DESC, op, 0, 0, 0, 0, 0, 0, .{ a, b, c });
    try t.expectEqual(abi.ST_OK, astro.run(mem, DESC, 1));
    try t.expectEqual(@as(u32, 0), mem.ld32(DESC + 4 * abi.W_CYCLES));
    return r(DESC);
}

test "scalar ops answer the IEEE result, FMA rounds once" {
    try t.expectEqual(@as(f64, 0.30000000000000004), try scalar1(abi.OP_ADD, 0.1, 0.2, 0));
    try t.expectEqual(@as(f64, -1.5), try scalar1(abi.OP_SUB, 1, 2.5, 0));
    try t.expectEqual(@as(f64, 1.0 / 3.0), try scalar1(abi.OP_DIV, 1, 3, 0));
    try t.expectEqual(@sqrt(@as(f64, 2)), try scalar1(abi.OP_SQRT, 2, 0, 0));
    // (1 + 2^-30)^2 - 1 - 2^-29 = 2^-60 exactly with one rounding; a mul then an add loses it.
    const e = 1.0 + std.math.pow(f64, 2, -30);
    try t.expectEqual(std.math.pow(f64, 2, -60), try scalar1(abi.OP_FMA, e, e, -1.0 - std.math.pow(f64, 2, -29)));
    try t.expectApproxEqAbs(@as(f64, 1), try scalar1(abi.OP_SIN, std.math.pi / 2.0, 0, 0), 1e-15);
    try t.expectApproxEqAbs(@as(f64, 3) * std.math.pi / 4.0, try scalar1(abi.OP_ATAN2, 1, -1, 0), 1e-15);
    try t.expectEqual(@as(f64, 1024), try scalar1(abi.OP_POW, 2, 10, 0));
    try t.expectEqual(@as(f64, 0), try scalar1(abi.OP_NOP, 5, 5, 5));
}

test "vector ops: VADD f64, AXPY in place, DOT, MAP sin into f32" {
    for (0..100) |i| {
        mem.st64(A + 8 * @as(u32, @intCast(i)), @floatFromInt(i));
        mem.st64(B + 8 * @as(u32, @intCast(i)), 0.5);
    }
    desc(DESC, abi.OP_VADD, 100, 0, 0, A, B, C, .{ 0, 0, 0 });
    desc(DESC + abi.DESC_BYTES, abi.OP_DOT, 100, 0, 0, A, B, 0, .{ 0, 0, 0 });
    desc(DESC + 2 * abi.DESC_BYTES, abi.OP_AXPY, 100, 0, 0, A, B, 0, .{ 2, 0, 0 });
    try t.expectEqual(abi.ST_OK, astro.run(mem, DESC, 3));
    try t.expectEqual(@as(f64, 99.5), mem.ld64(C + 8 * 99));
    try t.expectEqual(@as(f64, 2475), r(DESC + abi.DESC_BYTES)); // 0.5 * (0 + ... + 99)
    try t.expectEqual(@as(f64, 2 * 7 + 0.5), mem.ld64(B + 8 * 7));
    desc(DESC, abi.OP_MAP | abi.TYPE_F32_OUT, 100, abi.FN_SIN, 0, A, 0, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_OK, astro.run(mem, DESC, 1));
    try t.expectEqual(@as(f32, @floatCast(@sin(@as(f64, 42)))), @as(f32, @bitCast(mem.ld32(C + 4 * 42))));
}

test "GEMV: C = A x, column-major with lda" {
    // A = [[1 2], [3 4], [5 6]] (3 x 2), lda 4: columns at A and A + 32.
    const col0 = [_]f64{ 1, 3, 5 };
    const col1 = [_]f64{ 2, 4, 6 };
    for (0..3) |i| {
        mem.st64(A + 8 * @as(u32, @intCast(i)), col0[i]);
        mem.st64(A + 32 + 8 * @as(u32, @intCast(i)), col1[i]);
    }
    mem.st64(B, 10);
    mem.st64(B + 8, 1);
    desc(DESC, abi.OP_GEMV, 2, 3, 4, A, B, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_OK, astro.run(mem, DESC, 1));
    for ([_]f64{ 12, 34, 56 }, 0..) |want, i| try t.expectEqual(want, mem.ld64(C + 8 * @as(u32, @intCast(i))));
}

/// netlib linpack.c's matgen (n = 100, lda = 201: the Hatari build's 200 x 200 array plus one), b = row sums.
fn matgen(n: u32, lda: u32) void {
    var init: i32 = 1325;
    for (0..n) |j| for (0..n) |i| {
        init = @mod(3125 * init, 65536);
        mem.st64(A + 8 * (lda * @as(u32, @intCast(j)) + @as(u32, @intCast(i))), @as(f64, @floatFromInt(init - 32768)) / 16384.0);
    };
    for (0..n) |i| {
        var s: f64 = 0;
        for (0..n) |j| s += mem.ld64(A + 8 * (lda * @as(u32, @intCast(j)) + @as(u32, @intCast(i))));
        mem.st64(C + 8 * @as(u32, @intCast(i)), s);
    }
}

test "LINPACK 100: GEFA then GESL solves for all ones" {
    matgen(100, 201);
    desc(DESC, abi.OP_GEFA, 100, 0, 201, A, B, 0, .{ 0, 0, 0 });
    desc(DESC + abi.DESC_BYTES, abi.OP_GESL, 100, 0, 201, A, B, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_OK, astro.run(mem, DESC, 2));
    try t.expectEqual(@as(f64, 0), r(DESC)); // no zero pivot
    var worst: f64 = 0;
    for (0..100) |i| worst = @max(worst, @abs(mem.ld64(C + 8 * @as(u32, @intCast(i))) - 1));
    try t.expect(worst < 1e-12);
}

test "refusals: unknown op, out of memory, misaligned, bad pivots, bad list; nothing written" {
    desc(DESC, 0x7F, 1, 0, 0, A, B, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_BAD_OP, astro.run(mem, DESC, 1));
    try t.expectEqual(@as(f64, -7), r(DESC)); // a refused descriptor keeps its result word
    desc(DESC, abi.OP_MAP, 4, abi.FN_COUNT, 0, A, 0, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_BAD_OP, astro.run(mem, DESC, 1));
    mem.st64(C, 1234);
    desc(DESC, abi.OP_VADD, 4, 0, 0, A, SIZE - 16, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_RANGE, astro.run(mem, DESC, 1));
    try t.expectEqual(@as(f64, 1234), mem.ld64(C));
    desc(DESC, abi.OP_VADD, 4, 0, 0, A + 4, B, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_ALIGN, astro.run(mem, DESC, 1));
    desc(DESC, abi.OP_VADD | abi.TYPE_F32, 4, 0, 0, A + 4, B, C + 4, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_OK, astro.run(mem, DESC, 1)); // f32 arrays need only 4
    desc(DESC, abi.OP_GEMV, 2, 3, 2, A, B, C, .{ 0, 0, 0 }); // lda < rows
    try t.expectEqual(abi.ST_RANGE, astro.run(mem, DESC, 1));
    mem.st64(C, 1234);
    mem.st32(B, 7); // pivot 0 = 7 > n - 1
    desc(DESC, abi.OP_GESL, 3, 0, 3, A, B, C, .{ 0, 0, 0 });
    try t.expectEqual(abi.ST_RANGE, astro.run(mem, DESC, 1));
    try t.expectEqual(@as(f64, 1234), mem.ld64(C));
    try t.expectEqual(abi.ST_BAD_DESC, astro.run(mem, DESC + 4, 1));
    try t.expectEqual(abi.ST_BAD_DESC, astro.run(mem, DESC, abi.MAX_COUNT + 1));
    try t.expectEqual(abi.ST_BAD_DESC, astro.run(mem, SIZE - 40, 1));
}

test "a batch reports the first failure and still runs the rest" {
    desc(DESC, 0x7F, 0, 0, 0, 0, 0, 0, .{ 0, 0, 0 });
    desc(DESC + abi.DESC_BYTES, abi.OP_MUL, 0, 0, 0, 0, 0, 0, .{ 3, 4, 0 });
    try t.expectEqual(abi.ST_BAD_OP, astro.run(mem, DESC, 2));
    try t.expectEqual(abi.ST_OK, mem.ld32(DESC + abi.DESC_BYTES + 4 * abi.W_STATUS));
    try t.expectEqual(@as(f64, 12), r(DESC + abi.DESC_BYTES));
}
