// Tests for zig3d_fixed's integer helpers that replace a 64-bit loop or divide
// on the rv32 cart CPU (zig3d_fixed_math.isqrt, pow2Over, and
// zig3d_fixed_poly.sortFarToNear): each against the plain operation it stands
// for, exactly.
const std = @import("std");
const zf = @import("zig3d_fixed.zig");
const fm = zf.math;

test "isqrt is floor(sqrt) exactly: random, squares and their neighbours, both range ends" {
    var prng = std.Random.DefaultPrng.init(0x5c27);
    const r = prng.random();
    for (0..200_000) |i| {
        const x: u64 = switch (i % 4) {
            0 => r.intRangeLessThan(u64, 1 << 58, 1 << 62),
            1 => r.int(u64), // outside the fast range too
            else => blk: { // a square, or one off it
                const q = r.intRangeLessThan(u64, 1 << 29, 1 << 31);
                break :blk q * q - (i % 4 - 2);
            },
        };
        try std.testing.expectEqual(std.math.sqrt(x), fm.isqrt(x));
    }
    for ([_]u64{ 0, 1, (1 << 58) - 1, 1 << 58, (1 << 62) - 1, 1 << 62, std.math.maxInt(u64) }) |x|
        try std.testing.expectEqual(std.math.sqrt(x), fm.isqrt(x));
}

test "pow2Over is floor(2^44 / d) exactly, inside and outside its fast range" {
    var prng = std.Random.DefaultPrng.init(0xd1f);
    const r = prng.random();
    for (0..200_000) |i| {
        const d: i64 = if (i % 2 == 0) r.intRangeLessThan(i64, 1 << 20, 1 << 31) else r.intRangeAtMost(i64, 1, 1 << 40);
        try std.testing.expectEqual(@divTrunc(@as(i64, 1) << 44, d), fm.pow2Over(44, d));
    }
    for ([_]i64{ 1, (1 << 20) - 1, 1 << 20, 1 << 22, 1 << 29, (1 << 31) - 1, 1 << 31 }) |d|
        try std.testing.expectEqual(@divTrunc(@as(i64, 1) << 44, d), fm.pow2Over(44, d));
}

fn fartherFirst(_: void, a: zf.Poly, b: zf.Poly) bool {
    return a.depth > b.depth;
}

test "sortFarToNear is the stable far-to-near insertion sort, ties in arrival order" {
    var prng = std.Random.DefaultPrng.init(0x50f7);
    const r = prng.random();
    var a: [1100]zf.Poly = undefined;
    var b: [1100]zf.Poly = undefined;
    for (0..400) |t| {
        // once past the index sort's 1024 (its fallback); few depths, so ties are common
        const n: usize = if (t == 0) 1100 else r.uintLessThan(usize, 200);
        for (a[0..n], 0..) |*p, i| {
            p.* = .{ .pts = undefined, .n = 3, .ink = 1, .depth = r.intRangeAtMost(i64, -9, 9) << 40 };
            p.pts[0] = .{ @intCast(i), 0 }; // the arrival index
        }
        @memcpy(b[0..n], a[0..n]);
        zf.sortFarToNear(a[0..n]);
        std.sort.insertion(zf.Poly, b[0..n], {}, fartherFirst);
        for (a[0..n], b[0..n]) |x, y| {
            try std.testing.expectEqual(y.depth, x.depth);
            try std.testing.expectEqual(y.pts[0][0], x.pts[0][0]);
        }
    }
}
