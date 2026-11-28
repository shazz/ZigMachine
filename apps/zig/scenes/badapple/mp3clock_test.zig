// Native tests of mp3clock.zig (scene_tests.zig runs them).
const std = @import("std");
const c = @import("mp3clock.zig");

test "mp3clock reads MPEG-2 22.05 kHz and MPEG-1 44.1 kHz Layer III, after an ID3 tag too" {
    const f2 = c.parse(&[_]u8{ 0xFF, 0xF3, 0x60, 0xC4 }).?; // MPEG-2 L3 48 kbps 22.05 kHz (the local song's header)
    try std.testing.expectEqual(@as(u32, 22050), f2.rate);
    try std.testing.expectEqual(@as(u32, 576), f2.spf);
    // 219.2 s of song is 8391 frames of 576 samples: the film's 6,573 frames end with it
    try std.testing.expectEqual(@as(u64, 219_193_469), f2.us(8391));
    const f1 = c.parse(&[_]u8{ 0xFF, 0xFB, 0x90, 0x64 }).?;
    try std.testing.expectEqual(@as(u32, 44100), f1.rate);
    try std.testing.expectEqual(@as(u32, 1152), f1.spf);
    const tagged = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 2, 0xAA, 0xBB, 0xFF, 0xF3, 0x60, 0xC4 };
    try std.testing.expectEqual(@as(u32, 22050), c.parse(&tagged).?.rate);
}

test "mp3clock refuses what is not a Layer III frame header" {
    try std.testing.expect(c.parse(&[_]u8{ 0xFF, 0xF3, 0x60 }) == null); // short
    try std.testing.expect(c.parse(&[_]u8{ 0x00, 0xF3, 0x60, 0xC4 }) == null); // no sync
    try std.testing.expect(c.parse(&[_]u8{ 0xFF, 0xFD, 0x90, 0x64 }) == null); // Layer II
    try std.testing.expect(c.parse(&[_]u8{ 0xFF, 0xEB, 0x90, 0x64 }) == null); // reserved version
    try std.testing.expect(c.parse(&[_]u8{ 0xFF, 0xFB, 0x9C, 0x64 }) == null); // reserved rate
    const bad_tag = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0x80, 0, 0, 2, 0, 0, 0xFF, 0xF3, 0x60, 0xC4 };
    try std.testing.expect(c.parse(&bad_tag) == null);
    const long_tag = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 1, 0, 0xFF, 0xF3, 0x60, 0xC4 }; // past `head`
    try std.testing.expect(c.parse(&long_tag) == null);
}

test "mp3clock pull keeps the host clock inside the slack, the song's outside" {
    try std.testing.expectEqual(@as(u64, 1_010_000), c.pull(1_010_000, 1_000_000, 40_000));
    try std.testing.expectEqual(@as(u64, 1_040_000), c.pull(1_200_000, 1_000_000, 40_000)); // ahead: held
    try std.testing.expectEqual(@as(u64, 960_000), c.pull(500_000, 1_000_000, 40_000)); // behind: jumps on
    try std.testing.expectEqual(@as(u64, 0), c.pull(0, 0, 40_000));
}
