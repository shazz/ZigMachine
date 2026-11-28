// Native tests of poly.zig + polyfill.zig (scene_tests.zig runs them).
const std = @import("std");
const p = @import("poly.zig");

const W: usize = 320;
const H: usize = 200;

fn white(fb: []const u8, x: usize, y: usize) bool {
    return fb[y * W + x] == 1;
}

// A 10x10 square at (10, 20) with a 4x4 hole at (13, 23): two NEW contours, black background.
fn frameSquareHole() []const u8 {
    // NEW n=4 at (10,20): steps (+10,0) (0,+10) (-10,0) escaped (dx 10 is past a nibble)
    return &[_]u8{
        0, 2,
        0, 4, 10, 0, 20, 0x00, 20, 0x00, 0x00, 0x00, 20, 0x00, 19, 0x00, // (+10,0),(0,+10),(-10,0) zigzag
        0, 4, 13, 0, 23, 0x8C, 0xC8, 0x84, // (+4,0) (0,+4) (-4,0) as nibbles: dx+8 | (dy+8) << 4
    };
}

test "BAPO even-odd: a square with a hole, then KEEP and DELTA" {
    var s: p.State = undefined;
    s.reset();
    var fb = [_]u8{0} ** (W * H);
    _ = s.beginBlock(&.{}).?;
    try std.testing.expect(s.decodeFrame(frameSquareHole(), &fb, W));
    try std.testing.expect(white(&fb, 10, 20) and white(&fb, 19, 29) and white(&fb, 12, 25));
    try std.testing.expect(!white(&fb, 9, 20) and !white(&fb, 20, 20) and !white(&fb, 10, 30));
    try std.testing.expect(!white(&fb, 13, 23) and !white(&fb, 16, 26)); // the hole
    try std.testing.expect(white(&fb, 17, 23)); // just right of the hole
    // KEEP the square, DELTA the hole one pixel right: (13,23)->(14,23)...
    const f1 = [_]u8{ 0, 2, 1, 0, 2, 1, 0x89, 0x89, 0x89, 0x89 };
    try std.testing.expect(s.decodeFrame(&f1, &fb, W));
    try std.testing.expect(white(&fb, 13, 23) and !white(&fb, 14, 23) and !white(&fb, 17, 26) and white(&fb, 18, 26));
    // a white background inverts every row (an empty frame)
    try std.testing.expect(s.decodeFrame(&[_]u8{ 1, 0 }, &fb, W));
    try std.testing.expect(std.mem.allEqual(u8, &fb, 1));
}

test "BAPO a slanted edge follows the integer rule" {
    var s: p.State = undefined;
    s.reset();
    var fb = [_]u8{0} ** (W * H);
    _ = s.beginBlock(&.{}).?;
    // triangle (0,0) (3,0) (0,3): row r has pixel centres x+0.5 < 3 - (r+0.5) filled -> widths 2, 1, 0
    const tri = [_]u8{ 0, 1, 0, 3, 0, 0, 0, 0x8B, 0xB5 };
    try std.testing.expect(s.decodeFrame(&tri, &fb, W));
    try std.testing.expect(white(&fb, 0, 0) and white(&fb, 1, 0) and !white(&fb, 2, 0));
    try std.testing.expect(white(&fb, 0, 1) and !white(&fb, 1, 1));
    try std.testing.expect(!white(&fb, 0, 2));
}

test "BAPO refuses malformed frames" {
    var s: p.State = undefined;
    s.reset();
    var fb = [_]u8{0} ** (W * H);
    _ = s.beginBlock(&.{}).?;
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 1, 0 }, &fb, W)); // KEEP in a block's first frame
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 2, 0 }, &fb, W)); // unknown flags
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 2, 0, 0, 0, 0x88 }, &fb, W)); // 2 vertices
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 3, 0x41, 1, 0, 0x88, 0x88 }, &fb, W)); // x 321
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 3, 0, 0, 0, 0x80, 0x88 }, &fb, W)); // a zero nibble
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 3, 0, 0, 0, 0x87, 0x88 }, &fb, W)); // x -1
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 3, 0, 0, 0, 0x8A }, &fb, W)); // ends early
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 0, 7 }, &fb, W)); // a stray byte
    try std.testing.expect(s.decodeFrame(&[_]u8{ 0, 0 }, &fb, W));
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 1, 0 }, &fb, W)); // KEEP past the last frame's contours
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 3, 0 }, &fb, W)); // op 3
}
