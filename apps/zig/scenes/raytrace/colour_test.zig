// Native tests for colour.zig: zig test apps/zig/scenes/raytrace/colour_test.zig
// (the gate: apps/zig/scene_tests.zig).
const std = @import("std");
const C = @import("colour.zig");
const S = @import("shade.zig");

const expectEqual = std.testing.expectEqual;

test "the ramps' end points are the old palette's" {
    try expectEqual(C.Rgb{ 255, 168, 112 }, C.of(.{ .cls = S.CLS_SKY, .q = 0, .fog = 0 }));
    try expectEqual(C.Rgb{ 0, 0, 0 }, C.of(.{ .cls = S.CLS_MAT + 1, .q = 0, .fog = 0 }));
    try expectEqual(C.Rgb{ 255, 255, 255 }, C.of(.{ .cls = S.CLS_MAT + 3, .q = 256, .fog = 0 }));
    try expectEqual(C.Rgb{ 236, 226, 204 }, C.of(.{ .cls = S.CLS_FLOOR, .q = 256, .fog = 0 }));
    try expectEqual(C.Rgb{ 255, 168, 112 }, C.of(.{ .cls = S.CLS_FLOOR + 1, .q = 80, .fog = 256 }));
    // 78 % of full light is the sphere's own colour
    const q78: u16 = 78 * 256 / 100 + 1;
    const red = C.of(.{ .cls = S.CLS_MAT + 1, .q = q78, .fog = 0 });
    try std.testing.expect(red[0] >= 226 and red[1] < 50);
}

test "a ramp is continuous: one step of q moves a channel by at most a few levels" {
    for (0..8) |cls| {
        var q: u16 = 0;
        while (q < 256) : (q += 1) {
            const a = C.of(.{ .cls = @intCast(cls), .q = q, .fog = q });
            const b = C.of(.{ .cls = @intCast(cls), .q = q + 1, .fog = q + 1 });
            for (0..3) |i| try std.testing.expect(@abs(@as(i32, a[i]) - b[i]) <= 4);
        }
    }
}

test "16 white samples fit, and the order of the samples does not matter" {
    var a = C.first(.{ 255, 255, 255 });
    for (1..16) |_| C.add(&a, .{ 255, 255, 255 });
    try expectEqual(C.Lev{ 31 * 16, 63 * 16, 31 * 16 }, C.level(a, 16));
    try expectEqual(@as(u16, 0xFFFF), C.pixel(C.level(a, 16), 3, 2));
    const s = [_]C.Rgb{ .{ 1, 2, 3 }, .{ 200, 10, 90 }, .{ 7, 255, 0 }, .{ 33, 44, 55 } };
    var x = C.first(s[0]);
    for (s[1..]) |c| C.add(&x, c);
    var y = C.first(s[3]);
    for (0..3) |i| C.add(&y, s[2 - i]);
    try expectEqual(x, y);
}

test "one sample shows its own colour; an exact 565 level shows undithered" {
    const c = C.Rgb{ 8 * 10, 4 * 20, 8 * 30 }; // r5 10, g6 20, b5 30 by the top bits
    const l = C.level(C.first(c), 1);
    for (0..4) |y| for (0..4) |x| {
        const p = C.pixel(l, @intCast(x), @intCast(y));
        try std.testing.expect(p >> 11 == 10 or p >> 11 == 9); // 80 * 31 / 255 = 9.7 levels
        try std.testing.expect((p >> 5) & 63 == 20 or (p >> 5) & 63 == 19);
    };
    const exact = C.Lev{ 5 * 16, 7 * 16, 9 * 16 };
    for (0..4) |y| for (0..4) |x| try expectEqual(@as(u16, 5 << 11 | 7 << 5 | 9), C.pixel(exact, @intCast(x), @intCast(y)));
}

test "half a level dithers half the 4x4 cell up" {
    const l = C.Lev{ 3 * 16 + 8, 0, 0 };
    var up: u32 = 0;
    for (0..4) |y| for (0..4) |x| {
        up += @intFromBool(C.pixel(l, @intCast(x), @intCast(y)) >> 11 == 4);
    };
    try expectEqual(@as(u32, 8), up);
}
