// fixtrig.zig against f64 libm: the error bound its header claims, the exact
// quarters, and wrap-around of the angle accumulator.
const std = @import("std");
const t = @import("fixtrig.zig");

fn rad(a: t.Angle) f64 {
    return @as(f64, @floatFromInt(a)) * (2.0 * std.math.pi / 4294967296.0);
}

test "sin and cos stay within 2 LSB (3e-5) of f64 over the whole turn" {
    var worst: f64 = 0;
    var a: u64 = 0;
    while (a < (1 << 32)) : (a += 9973 * 31) {
        const ang: t.Angle = @intCast(a);
        const s = @as(f64, @floatFromInt(t.sin(ang))) / 65536.0;
        const c = @as(f64, @floatFromInt(t.cos(ang))) / 65536.0;
        worst = @max(worst, @abs(s - @sin(rad(ang))));
        worst = @max(worst, @abs(c - @cos(rad(ang))));
    }
    try std.testing.expect(worst * 65536.0 < 2.0);
}

test "the quarters are exact" {
    try std.testing.expectEqual(@as(i32, 0), t.sin(0));
    try std.testing.expectEqual(t.ONE, t.cos(0));
    try std.testing.expectEqual(t.ONE, t.sin(1 << 30));
    try std.testing.expectEqual(-t.ONE, t.sin(3 << 30));
}

test "angle() wraps negative radians and an accumulator wraps a full turn" {
    try std.testing.expectEqual(t.angle(-0.04), 0 -% t.angle(0.04));
    var acc: t.Angle = t.angle(6.0);
    acc +%= t.angle(0.5);
    const want = 6.5 - 2.0 * std.math.pi;
    try std.testing.expect(@abs(rad(acc) - want) < 1e-8);
}

test "mul is a Q16 product, signs included" {
    try std.testing.expectEqual(@as(i32, -3 << 15), t.mul(3 << 16, -(1 << 15)));
}

test "toRadians/fromRadians: a round trip lands within f32's precision, any turn" {
    try std.testing.expectEqual(@as(f32, 0), t.toRadians(0));
    try std.testing.expectEqual(@as(t.Angle, 0), t.fromRadians(0));
    try std.testing.expectEqual(t.angle(-0.5), t.fromRadians(-0.5));
    // two turns on: f32 holds 4*pi + 0.25 to ~1e-6 rad, about 700 Angle steps
    const far: i32 = @bitCast(t.fromRadians(0.25 + 4.0 * std.math.pi) -% t.angle(0.25));
    try std.testing.expect(@abs(far) < 1 << 11);
    var a: u64 = 1;
    while (a < (1 << 32)) : (a += 77777 * 37) {
        const back = t.fromRadians(t.toRadians(@intCast(a)));
        const d: i32 = @bitCast(back -% @as(t.Angle, @intCast(a)));
        try std.testing.expect(@abs(d) <= 1 << 8); // f32 keeps 24 of the 32 bits
    }
}
