const std = @import("std");
const f = @import("mp3_frame.zig");

test "an MPEG-1 128 kbps 44.1 kHz stereo header is a 417-byte frame, 418 padded" {
    try std.testing.expectEqual(f.Header{ .len = 417, .rate = 44100, .channels = 2 }, f.parse(.{ 0xFF, 0xFB, 0x90, 0x00 }).?);
    try std.testing.expectEqual(@as(u32, 418), f.parse(.{ 0xFF, 0xFB, 0x92, 0x00 }).?.len);
}

test "32 kHz, 48 kHz and mono headers" {
    try std.testing.expectEqual(f.Header{ .len = 576, .rate = 32000, .channels = 2 }, f.parse(.{ 0xFF, 0xFB, 0x98, 0x00 }).?);
    try std.testing.expectEqual(f.Header{ .len = 384, .rate = 48000, .channels = 1 }, f.parse(.{ 0xFF, 0xFB, 0x94, 0xC0 }).?);
}

test "an MPEG-2 24 kHz 64 kbps header uses the half-size frame" {
    try std.testing.expectEqual(f.Header{ .len = 192, .rate = 24000, .channels = 2 }, f.parse(.{ 0xFF, 0xF3, 0x84, 0x00 }).?);
}

test "not a Layer III frame: no sync, Layer II, a free bitrate, a reserved rate" {
    try std.testing.expect(f.parse(.{ 0xFF, 0x7B, 0x90, 0x00 }) == null);
    try std.testing.expect(f.parse(.{ 0xFF, 0xFD, 0x90, 0x00 }) == null);
    try std.testing.expect(f.parse(.{ 0xFF, 0xFB, 0x00, 0x00 }) == null);
    try std.testing.expect(f.parse(.{ 0xFF, 0xFB, 0x9C, 0x00 }) == null);
}

test "an ID3v2 tag's length is its syncsafe size plus the header" {
    const tag = [_]u8{ 'I', 'D', '3', 3, 0, 0, 0, 0, 0x02, 0x01 };
    try std.testing.expectEqual(@as(u32, 10 + 257), f.id3Len(&tag));
    try std.testing.expectEqual(@as(u32, 0), f.id3Len(&.{ 0xFF, 0xFB, 0x90, 0x00, 0, 0, 0, 0, 0, 0 }));
}
