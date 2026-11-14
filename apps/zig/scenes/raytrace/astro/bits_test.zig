// Native tests for bits.zig against the FPU: zig test apps/zig/scenes/raytrace/astro/bits_test.zig
// (the gate: apps/zig/scene_tests.zig).
const std = @import("std");
const B = @import("bits.zig");

const vals = [_]f64{ 0.0, -0.0, 0.004, -0.004, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 3.999, -3.999, 30.0, -30.25, 255.9, 256.0, 256.5, 1e-300, -1e-300, 123456.75, -123456.75, 1e12, -1e12, std.math.inf(f64), -std.math.inf(f64) };

fn bits(x: f64) u64 {
    return @bitCast(x);
}

test "key orders as the f64s do" {
    for (vals) |a| for (vals) |b| {
        try std.testing.expectEqual(a < b, B.lt(bits(a), bits(b)));
    };
    try std.testing.expect(B.isZero(bits(-0.0)) and B.isZero(bits(0.0)) and !B.isZero(bits(1e-300)));
    try std.testing.expect(B.notPositive(bits(-0.0)) and B.notPositive(bits(-1e-300)) and !B.notPositive(bits(1e-300)));
}

test "trunc and floor match the FPU's below 2^30" {
    for (vals) |x| {
        if (!(@abs(x) < 1 << 30)) continue;
        try std.testing.expectEqual(@as(i32, @intFromFloat(@trunc(x))), B.trunc(bits(x)));
        try std.testing.expectEqual(@as(i32, @intFromFloat(@floor(x))), B.floor(bits(x)));
    }
    var x: f64 = -40.0;
    while (x < 40.0) : (x += 0.125) {
        try std.testing.expectEqual(@as(i32, @intFromFloat(@floor(x))), B.floor(bits(x)));
    }
    try std.testing.expectEqual(@as(i32, 1 << 30), B.trunc(bits(1e12)));
    try std.testing.expectEqual(@as(i32, -(1 << 30)), B.trunc(bits(-1e12)));
}

test "q8 clamps to 0..256 and floors" {
    try std.testing.expectEqual(@as(u16, 0), B.q8(bits(-5.0)));
    try std.testing.expectEqual(@as(u16, 0), B.q8(bits(0.9)));
    try std.testing.expectEqual(@as(u16, 31), B.q8(bits(31.95)));
    try std.testing.expectEqual(@as(u16, 256), B.q8(bits(256.0)));
    try std.testing.expectEqual(@as(u16, 256), B.q8(bits(1e9)));
}
