// libm_f32.zig against f64 libm: the ulp bound over the range carts use,
// the edge cases (0, -0, tiny, multiples of pi/2, huge, NaN, inf), and the
// sincos pair agreeing with sin and cos. An exhaustive sweep of every f32 in
// 2^-12..1.6e6 (offline, 80 s) measured 1.013 ulp for sin, 1.017 for cos.
const std = @import("std");
const m = @import("libm_f32.zig");

const BOUND_ULP: f64 = 1.1;

fn ulpErr(got: f32, want: f64) f64 {
    const w32: f32 = @floatCast(want);
    const up = std.math.nextAfter(f32, w32, std.math.inf(f32));
    const ulp: f64 = @floatCast(@abs(up - w32));
    return @abs(@as(f64, got) - want) / ulp;
}

// Walk the f32 bit patterns of [lo, hi) in both signs, `step` patterns apart.
fn worstOver(lo: f32, hi: f32, step: u32) [2]f64 {
    var w = [2]f64{ 0, 0 };
    var b: u32 = @bitCast(lo);
    const top: u32 = @bitCast(hi);
    while (b < top) : (b += step) {
        for ([_]f32{ 1, -1 }) |sg| {
            const x = @as(f32, @bitCast(b)) * sg;
            w[0] = @max(w[0], ulpErr(m.sin(x), @sin(@as(f64, x))));
            w[1] = @max(w[1], ulpErr(m.cos(x), @cos(@as(f64, x))));
        }
    }
    return w;
}

test "sin and cos stay within 1.1 ulp of f64 from 2^-12 to the f32 path's end" {
    const w = worstOver(0x1p-12, m.REDUCE_MAX, 61);
    try std.testing.expect(w[0] <= BOUND_ULP);
    try std.testing.expect(w[1] <= BOUND_ULP);
}

test "the f64 fallback above REDUCE_MAX holds the same bound up to 1.6e6" {
    const w = worstOver(m.REDUCE_MAX, 1.6e6, 1009);
    try std.testing.expect(w[0] <= BOUND_ULP);
    try std.testing.expect(w[1] <= BOUND_ULP);
}

test "a dense linear sweep of 0..8*pi, the angles a demo spins through" {
    var i: u32 = 0;
    while (i < 200_000) : (i += 1) {
        const x: f32 = @as(f32, @floatFromInt(i)) * (8.0 * std.math.pi / 200_000.0);
        try std.testing.expect(ulpErr(m.sin(x), @sin(@as(f64, x))) <= BOUND_ULP);
        try std.testing.expect(ulpErr(m.cos(x), @cos(@as(f64, x))) <= BOUND_ULP);
    }
}

test "multiples of pi/2 land on the right zero, one and sign" {
    var k: i32 = -64;
    while (k <= 64) : (k += 1) {
        const x: f32 = @as(f32, @floatFromInt(k)) * @as(f32, std.math.pi / 2.0);
        const xd: f64 = x;
        try std.testing.expect(ulpErr(m.sin(x), @sin(xd)) <= BOUND_ULP or @abs(m.sin(x) - @sin(xd)) < 1e-12);
        try std.testing.expect(ulpErr(m.cos(x), @cos(xd)) <= BOUND_ULP or @abs(m.cos(x) - @cos(xd)) < 1e-12);
    }
}

test "zero, negative zero and tiny arguments" {
    try std.testing.expectEqual(@as(u32, 0), @as(u32, @bitCast(m.sin(0.0))));
    try std.testing.expectEqual(@as(u32, 0x80000000), @as(u32, @bitCast(m.sin(-0.0))));
    try std.testing.expectEqual(@as(f32, 1.0), m.cos(0.0));
    try std.testing.expectEqual(@as(f32, 1.0), m.cos(-0.0));
    try std.testing.expectEqual(@as(f32, 1e-5), m.sin(1e-5));
    try std.testing.expectEqual(@as(f32, 1.0), m.cos(1e-5));
    try std.testing.expectEqual(@as(f32, 0x1p-140), m.sin(0x1p-140)); // subnormal
}

test "NaN and infinities give NaN" {
    for ([_]f32{ std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32) }) |x| {
        try std.testing.expect(std.math.isNan(m.sin(x)));
        try std.testing.expect(std.math.isNan(m.cos(x)));
        var s: f32 = 0;
        var c: f32 = 0;
        m.sincos(x, &s, &c);
        try std.testing.expect(std.math.isNan(s) and std.math.isNan(c));
    }
}

test "huge arguments stay bounded in [-1, 1]" {
    for ([_]f32{ 1e7, -3e9, 1.234e20, std.math.floatMax(f32), -std.math.floatMax(f32) }) |x| {
        try std.testing.expect(@abs(m.sin(x)) <= 1.0);
        try std.testing.expect(@abs(m.cos(x)) <= 1.0);
    }
}

test "sincos returns exactly sin and cos" {
    var i: i32 = -5000;
    while (i <= 5000) : (i += 1) {
        const x: f32 = @as(f32, @floatFromInt(i)) * 0.0137;
        var s: f32 = undefined;
        var c: f32 = undefined;
        m.sincos(x, &s, &c);
        try std.testing.expectEqual(m.sin(x), s);
        try std.testing.expectEqual(m.cos(x), c);
    }
}

test "the C entry points are the Zig ones" {
    try std.testing.expectEqual(m.sin(1.25), m.sinf(1.25));
    try std.testing.expectEqual(m.cos(-7.5), m.cosf(-7.5));
}
