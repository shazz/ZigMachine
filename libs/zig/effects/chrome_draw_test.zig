// Tests for effects/chrome_draw.zig: the cases measured on the Union Demo TCB2
// scroller in Chrome (screens/superscroller, back.png at Y1 = -3.35k), L16's
// glyph sheet, and a 4-row test image (red, green, blue, white) over black.
const std = @import("std");
const cd = @import("chrome_draw.zig");
const expectEqual = std.testing.expectEqual;

fn expectTaps(want: cd.Taps, got: ?cd.Taps) !void {
    const t = got orelse return error.TestExpectedTaps;
    try expectEqual(want.top, t.top);
    try expectEqual(want.bottom, t.bottom);
    try expectEqual(want.w, t.w);
}

const IMG = [4][3]u8{ .{ 255, 0, 0 }, .{ 0, 255, 0 }, .{ 0, 0, 255 }, .{ 255, 255, 255 } };

/// The 4-row image drawn whole at y: canvas row `row` as 0x00BBGGRR.
fn chrome(row: i32, y: f64) ?u32 {
    const t = cd.taps(y, 4, row) orelse return null;
    return cd.mixRgb(IMG[t.top], IMG[t.bottom], t.w);
}

fn rgb(r: u8, g: u8, b: u8) u32 {
    return @as(u32, r) | @as(u32, g) << 8 | @as(u32, b) << 16;
}

test "a fractional y blends the two rows under the row, in 16ths" {
    try expectTaps(.{ .top = 3, .bottom = 4, .w = 5 }, cd.taps(-3.35, 400, 0)); // frame 1
    try expectTaps(.{ .top = 6, .bottom = 7, .w = 11 }, cd.taps(-6.7, 400, 0)); // frame 2
}

test "a fraction under 1/16 snaps" {
    try expectTaps(.{ .top = 10, .bottom = 11, .w = 0 }, cd.taps(-10.05, 400, 0)); // frame 3
    try expectTaps(.{ .top = 0, .bottom = 1, .w = 0 }, cd.taps(0, 400, 0));
}

test "the top edge is exclusive: a row whose centre is above the image is not drawn" {
    try expectEqual(@as(?cd.Taps, null), cd.taps(394.65, 400, 394)); // frame 1, the second copy
    try expectTaps(.{ .top = 0, .bottom = 1, .w = 5 }, cd.taps(394.65, 400, 395));
    try expectEqual(@as(?cd.Taps, null), cd.taps(-3.35, 400, 400));
}

test "rows past an edge clamp to the edge row" {
    try expectTaps(.{ .top = 399, .bottom = 399, .w = 5 }, cd.taps(-3.35, 400, 396)); // centre 396.5 <= 396.65
    try expectEqual(@as(?cd.Taps, null), cd.taps(-3.35, 400, 397));
    try expectTaps(.{ .top = 0, .bottom = 0, .w = 12 }, cd.taps(0.25, 400, 0)); // v = -0.25
    try expectEqual(@as(?cd.Taps, null), cd.taps(0.5, 400, 0)); // centre 0.5 is not below 0.5
}

test "y is a float32 first: 364.4999999999999 is 364.5" {
    const y1: f64 = -33.50000000000001; // frame 10 accumulates this
    try expectEqual(@as(?cd.Taps, null), cd.taps(y1 + 398, 400, 364));
    try std.testing.expect(cd.taps(y1, 400, 366) != null); // bottom edge 366.5 is inclusive
}

test "y is a float32 first: a double just past a whole row is that row, not a 15/16 blend" {
    // an L16 letter accumulates 563.0000000000011; double precision would blend sheet rows 31/32 at 15/16
    try expectTaps(.{ .top = 32, .bottom = 33, .w = 0 }, cd.partTaps(563.0000000000011, 32, 32, 128, 563));
}

test "empty images and far rows draw nothing" {
    try expectEqual(@as(?cd.Taps, null), cd.taps(0, 0, 0));
    try expectEqual(@as(?cd.Taps, null), cd.partTaps(0, 0, 0, 4, 0));
    try expectEqual(@as(?cd.Taps, null), cd.taps(1000, 400, 10));
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

test "y = 10.5 is not drawn on row 10 and y = 10.8 clamps the bottom edge" {
    try expectEqual(@as(?u32, null), chrome(10, 10.5));
    try expectEqual(@as(?u32, rgb(127, 127, 0)), chrome(11, 10.5));
    try expectEqual(@as(?u32, rgb(255, 255, 255)), chrome(14, 10.5));
    try expectEqual(@as(?u32, rgb(207, 47, 0)), chrome(11, 10.8));
    try expectEqual(@as(?u32, rgb(47, 47, 255)), chrome(13, 10.8));
    try expectEqual(@as(?u32, rgb(255, 255, 255)), chrome(14, 10.8));
}

test "a part samples its neighbours in the image, clamped to the image" {
    // rows 1..2 of the image drawn at 0.5: row 1 blends part rows 0/1 = image 1/2
    const t = cd.partTaps(0.5, 1, 2, 4, 1).?;
    try expectEqual(@as(u16, 1), t.top);
    try expectEqual(@as(u16, 2), t.bottom);
    // row 2 of the part at 0.5: v = 1.5 -> image rows 2 and 3 (past the part)
    try expectEqual(@as(u16, 3), cd.partTaps(0.5, 1, 2, 4, 2).?.bottom);
    // the last image row clamps to itself
    try expectTaps(.{ .top = 3, .bottom = 3, .w = 8 }, cd.partTaps(0.5, 2, 2, 4, 2));
    // above the part's first row: the row before it in the sheet, not the part's own
    try expectTaps(.{ .top = 31, .bottom = 32, .w = 12 }, cd.partTaps(570.2, 32, 32, 128, 570));
}

test "y = -3.6 covers rows -4..-1 only: Chrome drew nothing on the canvas" {
    try expectEqual(@as(?u32, null), chrome(-5, -3.6));
    // row -1: v = 2.6, rows 2/3 weighted 9/16 -> (blue*7 + white*9) >> 4
    try expectEqual(@as(?u32, rgb(143, 143, 255)), chrome(-1, -3.6));
    try expectEqual(@as(?u32, null), chrome(0, -3.6));
}

test "mix and srcOver are Skia's integer forms" {
    try expectEqual(@as(u8, 70), cd.mix(0, 224, 5));
    try expectEqual(@as(u8, 224), cd.mix(224, 224, 15));
    try expectEqual(@as(u8, 96), cd.mix(96, 0, 0));
    try expectEqual(@as(u8, 160), cd.srcOver(0, 0, 160)); // transparent keeps the destination
    try expectEqual(@as(u8, 64), cd.srcOver(64, 255, 200)); // opaque replaces it
    try expectEqual(@as(u8, 128 + 127), cd.srcOver(128, 128, 255)); // never past 255
}
