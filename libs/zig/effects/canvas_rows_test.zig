// Tests for effects/canvas_rows.zig, against the values Chrome returned for a
// 4-row image (red, green, blue, white) drawn at a fractional y over black.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const rows = @import("canvas_rows.zig");

const IMG = [4][3]u8{ .{ 255, 0, 0 }, .{ 0, 255, 0 }, .{ 0, 0, 255 }, .{ 255, 255, 255 } };

fn chrome(row: i32, y: f64) ?u32 {
    const t = rows.tap(row, y, 0, 4, 4) orelse return null;
    return rows.mixRgb(IMG[t.a], IMG[t.b], t.w16);
}

fn rgb(r: u8, g: u8, b: u8) u32 {
    return @as(u32, r) | @as(u32, g) << 8 | @as(u32, b) << 16;
}

test "an integer y copies the rows" {
    try expectEqual(@as(?u32, null), chrome(9, 10));
    try expectEqual(@as(?u32, rgb(255, 0, 0)), chrome(10, 10));
    try expectEqual(@as(?u32, rgb(255, 255, 255)), chrome(13, 10));
    try expectEqual(@as(?u32, null), chrome(14, 10));
}

test "y = 10.2: the top edge clamps, the weights truncate to sixteenths" {
    try expectEqual(@as(?u32, rgb(255, 0, 0)), chrome(10, 10.2));
    try expectEqual(@as(?u32, rgb(63, 191, 0)), chrome(11, 10.2));
    try expectEqual(@as(?u32, rgb(0, 63, 191)), chrome(12, 10.2));
    try expectEqual(@as(?u32, rgb(191, 191, 255)), chrome(13, 10.2));
    try expectEqual(@as(?u32, null), chrome(14, 10.2));
}

test "y = 10.5 rounds up and y = 10.8 clamps the bottom edge" {
    try expectEqual(@as(?u32, null), chrome(10, 10.5));
    try expectEqual(@as(?u32, rgb(127, 127, 0)), chrome(11, 10.5));
    try expectEqual(@as(?u32, rgb(255, 255, 255)), chrome(14, 10.5));
    try expectEqual(@as(?u32, rgb(207, 47, 0)), chrome(11, 10.8));
    try expectEqual(@as(?u32, rgb(47, 47, 255)), chrome(13, 10.8));
    try expectEqual(@as(?u32, rgb(255, 255, 255)), chrome(14, 10.8));
}

test "a sub-rectangle samples its neighbours in the image, clamped to the image" {
    // rows 1..2 of the image drawn at 0.5: row 1 blends part rows 0/1 = image 1/2
    const t = rows.tap(1, 0.5, 1, 2, 4).?;
    try expectEqual(@as(usize, 1), t.a);
    try expectEqual(@as(usize, 2), t.b);
    // row 2 of the part at 0.5: v = 1.5 -> image rows 2 and 3 (past the part)
    const u = rows.tap(2, 0.5, 1, 2, 4).?;
    try expectEqual(@as(usize, 3), u.b);
    // the last image row clamps to itself
    const e = rows.tap(2, 0.5, 2, 2, 4).?;
    try expectEqual(@as(usize, 3), e.a);
    try expectEqual(@as(usize, 3), e.b);
}

test "y = -3.6 covers rows -4..-1 only: Chrome drew nothing on the canvas" {
    try expectEqual(@as(?u32, null), chrome(-5, -3.6));
    // row -1: v = 2.6, rows 2/3 weighted 9/16 -> (blue*7 + white*9) >> 4
    try expectEqual(@as(?u32, rgb(143, 143, 255)), chrome(-1, -3.6));
    try expectEqual(@as(?u32, null), chrome(0, -3.6));
}
