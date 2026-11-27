// Native tests of tiles.zig and container.zig (scene_tests.zig runs them).
const std = @import("std");
const t = @import("tiles.zig");
const container = @import("container.zig");

const W = container.WIDTH;
const H = container.HEIGHT;

/// A block: one dictionary tile (a diagonal), then the frames given.
fn block(comptime frames: []const []const u8) []const u8 {
    comptime var out: []const u8 = &[_]u8{ 1, 0, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };
    inline for (frames) |f| out = out ++ [_]u8{ @intCast(f.len & 0xFF), @intCast(f.len >> 8) } ++ f;
    return out;
}

const key_white: [1001]u8 = [_]u8{1} ++ [_]u8{1} ** 1000; // every slot code 1

test "BATL key frame, then a delta that names two slots" {
    var fb = [_]u8{7} ** (@as(usize, W) * H);
    var s: t.State = .{};
    const delta = [_]u8{ 0, 0b10, 0, 0, 0, 0b101, 0, 0, 0, 0, 2, 0 }; // tile row 1: slots 0 (diagonal) and 2 (black)
    const raw = comptime block(&.{&key_white});
    const off = s.beginBlock(raw).?;
    try std.testing.expectEqual(@as(usize, 10), off);
    try std.testing.expect(s.decodeFrame(&key_white, &fb, W));
    try std.testing.expect(std.mem.allEqual(u8, &fb, 1));
    try std.testing.expect(s.decodeFrame(&delta, &fb, W));
    // slot 40 (row 1, col 0) is the diagonal: pixel (k, 8 + k) white, the rest black
    try std.testing.expectEqual(@as(u8, 1), fb[8 * W + 0]);
    try std.testing.expectEqual(@as(u8, 0), fb[8 * W + 1]);
    try std.testing.expectEqual(@as(u8, 1), fb[15 * W + 7]);
    try std.testing.expectEqual(@as(u8, 0), fb[15 * W + 6]);
    try std.testing.expectEqual(@as(u8, 0), fb[8 * W + 16]); // slot 42: black
    try std.testing.expectEqual(@as(u8, 1), fb[8 * W + 8]); // slot 41: untouched
    // an unaligned plane paints the same pixels (the byte path)
    var odd = [_]u8{7} ** (@as(usize, W) * H + 1);
    var s2: t.State = .{};
    _ = s2.beginBlock(raw).?;
    try std.testing.expect(s2.decodeFrame(&key_white, odd[1..], W));
    try std.testing.expect(s2.decodeFrame(&delta, odd[1..], W));
    try std.testing.expectEqualSlices(u8, &fb, odd[1..]);
}

test "BATL delta that changes a slot in every one of the 25 tile rows" {
    // 125 bytes of slot masks: more than a u6 count of rows times 5 holds (the bug the harness caught)
    const f = comptime blk: {
        var b: []const u8 = &[_]u8{ 0, 0xFF, 0xFF, 0xFF, 0x01 };
        for (0..25) |_| b = b ++ [_]u8{ 1, 0, 0, 0, 0 };
        for (0..25) |_| b = b ++ [_]u8{0};
        break :blk b;
    };
    var fb = [_]u8{1} ** (@as(usize, W) * H);
    var s: t.State = .{};
    _ = s.beginBlock(&[_]u8{ 0, 0 }).?;
    try std.testing.expect(s.decodeFrame(&key_white, &fb, W));
    try std.testing.expect(s.decodeFrame(f, &fb, W));
    for (0..H) |y| {
        try std.testing.expectEqual(@as(u8, 0), fb[y * W + 7]); // column 0's slots: black
        try std.testing.expectEqual(@as(u8, 1), fb[y * W + 8]);
    }
}

test "BATL refuses malformed frames and blocks" {
    var fb = [_]u8{0} ** (@as(usize, W) * H);
    var s: t.State = .{};
    try std.testing.expect(s.beginBlock(&[_]u8{ 2, 0, 1, 2, 3 }) == null); // a dictionary past the block
    try std.testing.expect(s.beginBlock(&[_]u8{0}) == null);
    _ = s.beginBlock(&[_]u8{ 0, 0 }).?;
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 0, 0, 0, 0 }, &fb, W)); // a block must start with a key frame
    _ = s.beginBlock(&[_]u8{ 0, 0 }).?;
    try std.testing.expect(!s.decodeFrame(key_white[0..999], &fb, W)); // a key frame ends early
    _ = s.beginBlock(&[_]u8{ 0, 0 }).?;
    var key_bad = key_white;
    key_bad[500] = 2; // code 2 with an empty dictionary
    try std.testing.expect(!s.decodeFrame(&key_bad, &fb, W));
    _ = s.beginBlock(&[_]u8{ 0, 0 }).?;
    try std.testing.expect(s.decodeFrame(&key_white, &fb, W));
    try std.testing.expect(!s.decodeFrame(&key_white, &fb, W)); // a second key frame in a block
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 0, 0, 0, 2 }, &fb, W)); // row 25 does not exist
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 }, &fb, W)); // an empty slot mask
    try std.testing.expect(!s.decodeFrame(&[_]u8{ 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 }, &fb, W)); // a stray byte
}

test "container headers: the magic, 320x200 only, no empty blocks" {
    const good: [16]u8 = ("BATL" ++ [_]u8{ 64, 1, 200, 0, 30, 0, 90, 0, 3, 0, 30, 0 }).*;
    try std.testing.expect(container.parseHeader(&good, "BATL") != null);
    try std.testing.expect(container.parseHeader(&good, "BASP") == null);
    var bad = good;
    bad[6] = 240;
    try std.testing.expect(container.parseHeader(&bad, "BATL") == null);
    try std.testing.expect(container.parseHeader(good[0..15], "BATL") == null);
    try std.testing.expect(container.parseBlockHeader(&[_]u8{ 1, 0, 0, 0, 2, 0, 0, 0, 0, 0 }) == null);
}
