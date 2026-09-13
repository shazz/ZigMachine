// Tests for effects/palette.zig: rounding modes, alpha rule, clamping, range and
// entry-list writes, and that scaling always starts from the base colours.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const palette = @import("palette.zig");

const Color = struct { r: u8, g: u8, b: u8, a: u8 };

const FakeFB = struct {
    pal: [256]Color = [_]Color{.{ .r = 1, .g = 2, .b = 3, .a = 4 }} ** 256,
    writes: u32 = 0,

    pub fn setPaletteEntry(self: *FakeFB, entry: u8, value: Color) void {
        self.pal[entry] = value;
        self.writes += 1;
    }
};

test "trunc matches the ports' @intFromFloat(v * k)" {
    const c = Color{ .r = 255, .g = 101, .b = 3, .a = 200 };
    const k: f32 = 0.5;
    const s = palette.scale(c, k, .{});
    try expectEqual(@as(u8, @intFromFloat(@as(f32, 255) * k)), s.r); // 127
    try expectEqual(@as(u8, 50), s.g);
    try expectEqual(@as(u8, 1), s.b);
    try expectEqual(@as(u8, 200), s.a); // .keep
}

test "round and a fixed alpha, as cuddly_starwars does it" {
    const c = Color{ .r = 255, .g = 101, .b = 3, .a = 0 };
    const s = palette.scale(c, @as(f64, 0.5), .{ .rounding = .round, .alpha = .{ .set = 255 } });
    try expectEqual(@as(u8, 128), s.r);
    try expectEqual(@as(u8, 51), s.g);
    try expectEqual(@as(u8, 2), s.b);
    try expectEqual(@as(u8, 255), s.a);
}

test "k is clamped to [0, 1] instead of overflowing" {
    const c = Color{ .r = 200, .g = 100, .b = 0, .a = 9 };
    try expectEqual(c, palette.scale(c, @as(f32, 3.0), .{}));
    const z = palette.scale(c, @as(f32, -1.0), .{});
    try expectEqual(@as(u8, 0), z.r);
    try expectEqual(@as(u8, 9), z.a);
}

test "scaleRange writes exactly lo..=hi, including entry 255" {
    var fb = FakeFB{};
    var base: [256]Color = undefined;
    for (&base, 0..) |*b, i| b.* = .{ .r = @intCast(i), .g = 100, .b = 50, .a = 255 };
    palette.scaleRange(&fb, &base, 250, 255, @as(f32, 1.0), .{});
    try expectEqual(@as(u32, 6), fb.writes);
    try expectEqual(base[255], fb.pal[255]);
    try expectEqual(Color{ .r = 1, .g = 2, .b = 3, .a = 4 }, fb.pal[249]);
}

test "repeated fades scale from the base, never compound" {
    var fb = FakeFB{};
    const base = [_]Color{.{ .r = 200, .g = 200, .b = 200, .a = 255 }} ** 2;
    palette.scaleRange(&fb, &base, 0, 1, @as(f32, 0.5), .{});
    palette.scaleRange(&fb, &base, 0, 1, @as(f32, 0.5), .{});
    try expectEqual(@as(u8, 100), fb.pal[1].r);
}

test "scaleEntries touches only the listed entries" {
    var fb = FakeFB{};
    var base: [256]Color = undefined;
    @memset(&base, .{ .r = 10, .g = 20, .b = 30, .a = 40 });
    palette.scaleEntries(&fb, &base, &[_]u8{ 3, 7 }, @as(f64, 1.0), .{ .alpha = .{ .set = 255 } });
    try expectEqual(@as(u32, 2), fb.writes);
    try expectEqual(@as(u8, 255), fb.pal[7].a);
    try expectEqual(@as(u8, 4), fb.pal[4].a);
}
