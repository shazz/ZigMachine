// Tests for linelist.zig: the words a line list builds (machine/copper.zig's format), only the
// changes written, and the size check.
const std = @import("std");
const ll = @import("linelist.zig");
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const L = ll.LineList(0x3C);
const END: u32 = 0xF000_0000 | 511 << 19;
fn head(y: u32, n: u32) u32 {
    return 0xF000_0000 | y << 19 | n;
}

test "the first line writes everything, later ones only what changes" {
    var buf: [ll.words(4)]u32 = undefined;
    @memset(&buf, 0);
    const lines = [_]ll.Line{
        .{ .base = 0x2000, .hscroll = 3, .colour = 0xFF00_0001 },
        .{ .base = 0x2000 + 400, .hscroll = 3, .colour = 0xFF00_0001 }, // runs on: nothing
        .{ .base = 0x9000, .hscroll = 3, .colour = 0xFF00_0002 }, // new base, new colour
        .{ .base = 0x9000 + 400, .hscroll = 5, .colour = 0xFF00_0002 }, // a scroll
    };
    const n = try L.build(&buf, &lines, .{ .plane = 1, .stride = 400, .first_row = 10 });
    const want = [_]u32{
        head(10, 4),                  0x5000_2000, 0x2000_0000 | 0x3E << 20 | 3, 0x1000_1000, 0xFF00_0001,
        head(12, 3),                  0x5000_9000, 0x1000_1000,                  0xFF00_0002, head(13, 1),
        0x2000_0000 | 0x3E << 20 | 5, END,
    };
    try expectEqual(want.len, n);
    try expectEqualSlices(u32, &want, buf[0..n]);
}

test "flicker puts a FLICK on every line, and options drop HSCROLL and colour" {
    var buf: [ll.words(2)]u32 = undefined;
    @memset(&buf, 0);
    const lines = [_]ll.Line{ .{ .base = 0x2000 }, .{ .base = 0x2000 + 320 } };
    const n = try L.build(&buf, &lines, .{ .plane = 0, .stride = 320, .flicker = true, .hscroll = false, .colour_entry = null });
    const want = [_]u32{ head(0, 2), 0x3000_0000, 0x5000_2000, head(1, 1), 0x3000_0000, END };
    try expectEqualSlices(u32, &want, buf[0..n]);
}

test "a buffer too small, or rows past the raster, write nothing" {
    var buf: [ll.words(2) - 1]u32 = [_]u32{7} ** (ll.words(2) - 1);
    const lines = [_]ll.Line{ .{ .base = 0x2000 }, .{ .base = 0x3000 } };
    try std.testing.expectError(error.ListTooSmall, L.build(&buf, &lines, .{ .plane = 0, .stride = 320 }));
    var big: [ll.words(2)]u32 = undefined;
    try std.testing.expectError(error.ListTooSmall, L.build(&big, &lines, .{ .plane = 0, .stride = 320, .first_row = 279 }));
    try expectEqual(@as(u32, 7), buf[0]);
}

test "a base past 28 bits is refused on the machine, never aliased into VRAM" {
    var buf: [ll.words(1)]u32 = undefined;
    @memset(&buf, 0);
    const n = try L.build(&buf, &.{.{ .base = 0x1000_2000 }}, .{ .plane = 0, .stride = 320, .hscroll = false, .colour_entry = null });
    try expectEqual(@as(u32, 0x5FFF_FFFF), buf[1]);
    try expectEqual(@as(usize, 3), n);
}
