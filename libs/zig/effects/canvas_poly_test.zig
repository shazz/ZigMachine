// Tests for effects/canvas_poly.zig: the (2X + 0.5, 2Y + 0.5) sample rule, its
// half-open edges, nonzero winding, clipping and refusals.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const Dst = @import("blit.zig").Dst;
const poly = @import("canvas_poly.zig");

fn count(buf: []const u8, v: u8) usize {
    var n: usize = 0;
    for (buf) |b| n += @intFromBool(b == v);
    return n;
}

test "a canvas rectangle keeps the ST pixels whose samples it covers" {
    var buf = [_]u8{0} ** (8 * 8);
    // canvas x 1..7 covers samples 2.5, 4.5, 6.5 (X 1..3); y 0.5..4.5 covers 0.5, 2.5 (Y 0..1)
    poly.fill(Dst.buffer(&buf, 8), &.{ .{ 1, 0.5 }, .{ 7, 0.5 }, .{ 7, 4.5 }, .{ 1, 4.5 } }, 5);
    try expectEqual(@as(usize, 6), count(&buf, 5));
    for (0..2) |y| for (1..4) |x| try expectEqual(@as(u8, 5), buf[y * 8 + x]);
}

test "edges are half-open: a sample on the top or left edge is in, on the bottom or right it is out" {
    var buf = [_]u8{0} ** (4 * 4);
    poly.fill(Dst.buffer(&buf, 4), &.{ .{ 0.5, 0.5 }, .{ 2.5, 0.5 }, .{ 2.5, 2.5 }, .{ 0.5, 2.5 } }, 1);
    try expectEqual(@as(usize, 1), count(&buf, 1));
    try expectEqual(@as(u8, 1), buf[0]);
}

test "winding is nonzero: a doubly wound square fills once, a bowtie fills both lobes" {
    var buf = [_]u8{0} ** (10 * 10);
    poly.fill(Dst.buffer(&buf, 10), &.{ .{ 0, 0 }, .{ 20, 0 }, .{ 20, 20 }, .{ 0, 20 }, .{ 20, 0 }, .{ 20, 20 } }, 3);
    try expectEqual(@as(usize, 100), count(&buf, 3));
    @memset(&buf, 0);
    poly.fill(Dst.buffer(&buf, 10), &.{ .{ 0, 0 }, .{ 20, 20 }, .{ 20, 0 }, .{ 0, 20 } }, 4);
    try expectEqual(@as(u8, 4), buf[5 * 10 + 1]); // left lobe
    try expectEqual(@as(u8, 4), buf[5 * 10 + 8]); // right lobe
    try expectEqual(@as(u8, 0), buf[1 * 10 + 5]); // above the crossing
}

test "a path far off the canvas clips, and degenerate input draws nothing" {
    var buf = [_]u8{0} ** (6 * 6);
    const d = Dst.buffer(&buf, 6);
    poly.fill(d, &.{ .{ -1e9, -1e9 }, .{ 1e9, -1e9 }, .{ 1e9, 1e9 }, .{ -1e9, 1e9 } }, 2);
    try expectEqual(@as(usize, 36), count(&buf, 2));
    @memset(&buf, 0);
    poly.fill(d, &.{ .{ 0, 0 }, .{ 10, 10 } }, 2); // two points
    poly.fill(d, &.{ .{ 0, 5 }, .{ 10, 5 }, .{ 5, 5 } }, 2); // flat
    poly.fill(d, &.{ .{ -30, -30 }, .{ -20, -30 }, .{ -20, -20 } }, 2); // above and left
    poly.fill(d, &.{ .{ std.math.nan(f64), 0 }, .{ 10, 0 }, .{ 10, 10 } }, 2);
    try expectEqual(@as(usize, 0), count(&buf, 2));
}
