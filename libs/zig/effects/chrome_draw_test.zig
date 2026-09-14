// Tests for effects/chrome_draw.zig, with the cases measured on the Union Demo
// TCB2 scroller in Chrome (screens/superscroller, back.png at Y1 = -3.35k).
const std = @import("std");
const cd = @import("chrome_draw.zig");
const expectEqual = std.testing.expectEqual;

fn expectTaps(want: cd.Taps, got: ?cd.Taps) !void {
    const t = got orelse return error.TestExpectedTaps;
    try expectEqual(want.top, t.top);
    try expectEqual(want.bottom, t.bottom);
    try expectEqual(want.w, t.w);
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

test "empty images and far rows draw nothing" {
    try expectEqual(@as(?cd.Taps, null), cd.taps(0, 0, 0));
    try expectEqual(@as(?cd.Taps, null), cd.taps(1000, 400, 10));
}

test "mix and srcOver are Skia's integer forms" {
    try expectEqual(@as(u8, 70), cd.mix(0, 224, 5));
    try expectEqual(@as(u8, 224), cd.mix(224, 224, 15));
    try expectEqual(@as(u8, 96), cd.mix(96, 0, 0));
    try expectEqual(@as(u8, 160), cd.srcOver(0, 0, 160)); // transparent keeps the destination
    try expectEqual(@as(u8, 64), cd.srcOver(64, 255, 200)); // opaque replaces it
    try expectEqual(@as(u8, 128 + 127), cd.srcOver(128, 128, 255)); // never past 255
}
