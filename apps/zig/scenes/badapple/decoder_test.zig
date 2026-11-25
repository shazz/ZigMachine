// Native tests of decoder.zig (scene_tests.zig runs them).
const std = @import("std");
const d = @import("decoder.zig");
const State = d.State;
const WIDTH = d.WIDTH;
const HEIGHT = d.HEIGHT;
const parseHeader = d.parseHeader;
const parseBlockHeader = d.parseBlockHeader;

test "BASP decode handles skip, nibble dx, and full row" {
    var state: State = .{};
    var fb = [_]u8{0} ** (@as(usize, WIDTH) * HEIGHT);

    // Frame 0: row 0 full [10, 20], rows 1..199 skip (128 + 71)
    const f0 = [_]u8{
        0xC2, 10, 20, // row 0: k=2, x=[10, 20]
        0x7F, // skip 128 (rows 1..128)
        0x46, // skip 71 (rows 129..199)
    };
    try std.testing.expect(state.decodeFrame(&f0, &fb, WIDTH));
    try std.testing.expectEqual(@as(u8, 0), fb[9]);
    try std.testing.expectEqual(@as(u8, 1), fb[10]);
    try std.testing.expectEqual(@as(u8, 1), fb[19]);
    try std.testing.expectEqual(@as(u8, 0), fb[20]);

    // Frame 1: row 0 dx=[+2, -3] -> [12, 17], rows 1..199 skip
    const f1 = [_]u8{
        0x82, @as(u8, ((-3 + 8) << 4) | (2 + 8)), // dx0=+2, dx1=-3
        0x7F,
        0x46,
    };
    try std.testing.expect(state.decodeFrame(&f1, &fb, WIDTH));
    try std.testing.expectEqual(@as(u8, 0), fb[11]);
    try std.testing.expectEqual(@as(u8, 1), fb[12]);
    try std.testing.expectEqual(@as(u8, 1), fb[16]);
    try std.testing.expectEqual(@as(u8, 0), fb[17]);
}

test "BASP decode refuses malformed frames" {
    var state: State = .{};
    var fb = [_]u8{0} ** (@as(usize, WIDTH) * HEIGHT);
    const rest = [_]u8{ 0x7F, 0x46 }; // rows 1..199 skipped

    // a delta on a row that has no transitions yet (count mismatch)
    try std.testing.expect(!state.decodeFrame(&[_]u8{ 0x81, 0x88 } ++ rest, &fb, WIDTH));
    // a transition past the right edge (varint 319 = 0xBF 0x02 is fine, 320 = 0xC0 0x02 is not)
    try std.testing.expect(state.decodeFrame(&[_]u8{ 0xC1, 0xBF, 0x02 } ++ rest, &fb, WIDTH));
    try std.testing.expect(!state.decodeFrame(&[_]u8{ 0xC1, 0xC0, 0x02 } ++ rest, &fb, WIDTH));
    // 63 transitions in a row, a delta that leaves the row, a frame that ends early, one that overshoots
    try std.testing.expect(!state.decodeFrame(&[_]u8{0xFF}, &fb, WIDTH));
    try std.testing.expect(!state.decodeFrame(&[_]u8{ 0x81, 0xFF } ++ rest, &fb, WIDTH));
    try std.testing.expect(!state.decodeFrame(&[_]u8{ 0xC0, 0x7F }, &fb, WIDTH));
    try std.testing.expect(!state.decodeFrame(&[_]u8{ 0xC0, 0x7F, 0x7F }, &fb, WIDTH));
}

test "BASP headers: 320x200 only, no empty blocks" {
    const good: [16]u8 = ("BASP" ++ [_]u8{ 64, 1, 200, 0, 30, 0, 90, 0, 3, 0, 30, 0 }).*;
    try std.testing.expect(parseHeader(&good) != null);
    var bad = good;
    bad[4] = 0; // 256 wide
    try std.testing.expect(parseHeader(&bad) == null);
    bad = good;
    bad[0] = 'X';
    try std.testing.expect(parseHeader(&bad) == null);
    try std.testing.expect(parseBlockHeader(&[_]u8{ 1, 0, 0, 0, 2, 0, 0, 0, 30, 0 }) != null);
    try std.testing.expect(parseBlockHeader(&[_]u8{ 1, 0, 0, 0, 2, 0, 0, 0, 0, 0 }) == null); // 0 frames
}
