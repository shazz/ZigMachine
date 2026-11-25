// --------------------------------------------------------------------------
// AURORA BOOT: points and lines into the 8-bit star plane (320 x 200, stride 320), integers only.
// A line's endpoints are Q4 pixels (the baker's projected vertices); it steps along its long axis
// in Q16 with the divide done once per line. Everything is clipped to the plane.
// No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const W: i32 = 320;
pub const H: i32 = 200;

pub fn put(plane: [*]u8, x: i32, y: i32, c: u8) void {
    if (x < 0 or y < 0 or x >= W or y >= H) return;
    plane[@intCast(y * W + x)] = c;
}

/// The lab's star glint: a 3-pixel cross (the centre is drawn by the caller).
pub fn cross(plane: [*]u8, x: i32, y: i32, c: u8) void {
    put(plane, x - 1, y, c);
    put(plane, x + 1, y, c);
    put(plane, x, y - 1, c);
    put(plane, x, y + 1, c);
}

/// A line from (x0, y0) to (x1, y1), Q4 pixels, colour `c`.
pub fn line(plane: [*]u8, x0: i32, y0: i32, x1: i32, y1: i32, c: u8) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const n = @max(@abs(dx), @abs(dy)) >> 4;
    if (n == 0) return put(plane, (x0 + 8) >> 4, (y0 + 8) >> 4, c);
    const sx = @divTrunc(dx << 12, @as(i32, @intCast(n)));
    const sy = @divTrunc(dy << 12, @as(i32, @intCast(n)));
    var x = (x0 << 12) + (1 << 15);
    var y = (y0 << 12) + (1 << 15);
    var i: i32 = 0;
    while (i <= n) : (i += 1) {
        put(plane, x >> 16, y >> 16, c);
        x += sx;
        y += sy;
    }
}

/// A filled rectangle, clipped.
pub fn rect(plane: [*]u8, x: i32, y: i32, w: i32, h: i32, c: u8) void {
    var j = @max(y, 0);
    while (j < @min(y + h, H)) : (j += 1) {
        const a = @max(x, 0);
        const b = @min(x + w, W);
        if (b > a) @memset(plane[@intCast(j * W + a)..][0..@intCast(b - a)], c);
    }
}

test "a horizontal line lights every pixel between its ends and nothing else" {
    var p = [_]u8{0} ** (320 * 200);
    line(&p, 10 << 4, 5 << 4, 20 << 4, 5 << 4, 7);
    var lit: u32 = 0;
    for (p) |v| lit += @intFromBool(v == 7);
    try std.testing.expectEqual(@as(u32, 11), lit);
    try std.testing.expectEqual(@as(u8, 7), p[5 * 320 + 10]);
    try std.testing.expectEqual(@as(u8, 7), p[5 * 320 + 20]);
}

test "a line off the plane draws nothing and never writes outside it" {
    var p = [_]u8{0} ** (320 * 200);
    line(&p, -500 << 4, -500 << 4, -400 << 4, -300 << 4, 9);
    line(&p, 300 << 4, 190 << 4, 700 << 4, 400 << 4, 9);
    var lit: u32 = 0;
    for (p) |v| lit += @intFromBool(v == 9);
    try std.testing.expect(lit < 25); // only the corner that is inside
    put(&p, -1, 0, 5);
    put(&p, 320, 0, 5);
    try std.testing.expectEqual(@as(u8, 0), p[0]);
}

test "a diagonal steps one pixel a row" {
    var p = [_]u8{0} ** (320 * 200);
    line(&p, 0, 0, 10 << 4, 10 << 4, 3);
    try std.testing.expectEqual(@as(u8, 3), p[5 * 320 + 5]);
    try std.testing.expectEqual(@as(u8, 0), p[5 * 320 + 6]);
}

test "a cross is four pixels around the centre; a rect is clipped" {
    var p = [_]u8{0} ** (320 * 200);
    cross(&p, 100, 100, 4);
    try std.testing.expectEqual(@as(u8, 4), p[100 * 320 + 99]);
    try std.testing.expectEqual(@as(u8, 0), p[100 * 320 + 100]);
    rect(&p, 318, 198, 10, 10, 6);
    try std.testing.expectEqual(@as(u8, 6), p[199 * 320 + 319]);
}
