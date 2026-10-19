// Tests for effects/canvas_poly_fixed.zig: the integer fill against the f64
// canvas_poly on the same paths (fixed-point values are exact doubles), and the rule's
// edge cases.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const Dst = @import("blit.zig").Dst;
const f64fill = @import("canvas_poly.zig");
const qfill = @import("canvas_poly_fixed.zig");
const PX = @import("zig3d_fixed_math.zig").PX;
const P: i32 = 1 << PX; // one canvas pixel

fn count(buf: []const u8, v: u8) usize {
    var n: usize = 0;
    for (buf) |b| n += @intFromBool(b == v);
    return n;
}

test "half-open edges, as canvas_poly: a sample on the top or left edge is in" {
    var buf = [_]u8{0} ** (4 * 4);
    const h = P / 2; // 0.5 canvas px
    qfill.fill(Dst.buffer(&buf, 4), &.{ .{ h, h }, .{ 5 * h, h }, .{ 5 * h, 5 * h }, .{ h, 5 * h } }, 1);
    try expectEqual(@as(usize, 1), count(&buf, 1));
    try expectEqual(@as(u8, 1), buf[0]);
}

test "a path far off the canvas is clipped, not wrapped" {
    var buf = [_]u8{0} ** (8 * 8);
    const big = 1 << 28; // within the +-2^30 a path may span
    qfill.fill(Dst.buffer(&buf, 8), &.{ .{ -big, -big }, .{ big, -big }, .{ big, big }, .{ -big, big } }, 3);
    try expectEqual(@as(usize, 64), count(&buf, 3));
}

test "random quads and triangles: pixel for pixel the f64 fill" {
    var prng = std.Random.DefaultPrng.init(0x5eed);
    const r = prng.random();
    var a = [_]u8{0} ** (64 * 40);
    var b = [_]u8{0} ** (64 * 40);
    for (0..4000) |i| {
        const n: usize = if (i % 2 == 0) 3 else 4;
        var q: [4][2]i32 = undefined;
        var f: [4][2]f64 = undefined;
        for (0..n) |k| {
            // -20..150 canvas px, at 1/P px; every 7th path snapped to sample rows
            var x = r.intRangeAtMost(i32, -20 * P, 150 * P);
            var y = r.intRangeAtMost(i32, -20 * P, 100 * P);
            if (i % 7 == 0) {
                x = (x >> (PX + 1) << (PX + 1)) + P / 2;
                y = (y >> (PX + 1) << (PX + 1)) + P / 2;
            }
            q[k] = .{ x, y };
            f[k] = .{ @as(f64, @floatFromInt(x)) / P, @as(f64, @floatFromInt(y)) / P };
        }
        const ink: u8 = @intCast(1 + i % 200);
        f64fill.fill(Dst.buffer(&a, 64), f[0..n], ink);
        qfill.fill(Dst.buffer(&b, 64), q[0..n], ink);
        try std.testing.expectEqualSlices(u8, &a, &b);
    }
}

test "paths reaching far past every edge: the stepped edges still land as the f64 fill" {
    var prng = std.Random.DefaultPrng.init(0xfa7);
    const r = prng.random();
    var a = [_]u8{0} ** (64 * 40);
    var b = [_]u8{0} ** (64 * 40);
    for (0..2000) |i| {
        const n: usize = 3 + i % 3;
        var q: [5][2]i32 = undefined;
        var f: [5][2]f64 = undefined;
        for (0..n) |k| {
            const x = r.intRangeAtMost(i32, -3000 * P, 3000 * P);
            const y = r.intRangeAtMost(i32, -3000 * P, 3000 * P);
            q[k] = .{ x, y };
            f[k] = .{ @as(f64, @floatFromInt(x)) / P, @as(f64, @floatFromInt(y)) / P };
        }
        f64fill.fill(Dst.buffer(&a, 64), f[0..n], @intCast(1 + i % 200));
        qfill.fill(Dst.buffer(&b, 64), q[0..n], @intCast(1 + i % 200));
        try std.testing.expectEqualSlices(u8, &a, &b);
    }
}

/// One random path of n points, its fixed and f64 twins; `snap` puts the
/// points on a coarse grid so horizontal edges, repeated points and samples
/// exactly on an edge come up often.
fn randomPath(r: std.Random, n: usize, span: i32, snap: bool, q: *[16][2]i32, f: *[16][2]f64) void {
    for (0..n) |k| {
        var x = r.intRangeAtMost(i32, -@divTrunc(span * P, 8), span * P);
        var y = r.intRangeAtMost(i32, -@divTrunc(span * P, 8), @divTrunc(span * P * 2, 3));
        if (snap) {
            x = (x >> (PX + 2) << (PX + 2)) + P / 2;
            y = (y >> (PX + 2) << (PX + 2)) + P / 2;
        }
        q[k] = .{ x, y };
        f[k] = .{ @as(f64, @floatFromInt(x)) / P, @as(f64, @floatFromInt(y)) / P };
    }
}

test "random paths of 3..16 points, monotone or not, self-crossing: pixel for pixel the f64 fill" {
    var prng = std.Random.DefaultPrng.init(0xc0ffee);
    const r = prng.random();
    // odd width and an offset start: the spans' word stores meet every alignment
    var a = [_]u8{0} ** (61 * 40 + 3);
    var b = [_]u8{0} ** (61 * 40 + 3);
    for (0..20000) |i| {
        const n: usize = 3 + i % 14;
        var q: [16][2]i32 = undefined;
        var f: [16][2]f64 = undefined;
        randomPath(r, n, if (i % 5 == 0) 2000 else 140, i % 3 == 0, &q, &f);
        const ink: u8 = @intCast(1 + i % 250);
        const off = i % 4;
        f64fill.fill(Dst.buffer(a[off .. off + 61 * 40], 61), f[0..n], ink);
        qfill.fill(Dst.buffer(b[off .. off + 61 * 40], 61), q[0..n], ink);
        try std.testing.expectEqualSlices(u8, &a, &b);
    }
}

test "projected-face shapes (convex, any size, on and off the screen): pixel for pixel the f64 fill" {
    var prng = std.Random.DefaultPrng.init(0xba11);
    const r = prng.random();
    var a = [_]u8{0} ** (320 * 200);
    var b = [_]u8{0} ** (320 * 200);
    for (0..5000) |i| {
        // a triangle or quad around a centre: always y-monotone
        const n: usize = 3 + i % 2;
        const cx = r.intRangeAtMost(i32, -40 * P, 680 * P);
        const cy = r.intRangeAtMost(i32, -40 * P, 440 * P);
        const rad: f64 = @floatFromInt(r.intRangeAtMost(i32, 1 * P, 120 * P));
        var q: [4][2]i32 = undefined;
        var f: [4][2]f64 = undefined;
        const turn = r.float(f64) * std.math.tau;
        for (0..n) |k| {
            const t = turn + std.math.tau * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(n));
            q[k] = .{ cx + @as(i32, @intFromFloat(rad * @cos(t))), cy + @as(i32, @intFromFloat(rad * @sin(t))) };
            f[k] = .{ @as(f64, @floatFromInt(q[k][0])) / P, @as(f64, @floatFromInt(q[k][1])) / P };
        }
        const ink: u8 = @intCast(1 + i % 250);
        f64fill.fill(Dst.buffer(&a, 320), f[0..n], ink);
        qfill.fill(Dst.buffer(&b, 320), q[0..n], ink);
        try std.testing.expectEqualSlices(u8, &a, &b);
    }
}
