const std = @import("std");
const id3 = @import("id3.zig");

fn tag(comptime ver: u8, comptime frame: []const u8) [10 + 10 + frame.len]u8 {
    var b: [10 + 10 + frame.len]u8 = undefined;
    @memcpy(b[0..10], &[_]u8{ 'I', 'D', '3', ver, 0, 0, 0, 0, 0, 10 + frame.len });
    @memcpy(b[10..14], "TIT2");
    @memcpy(b[14..20], &[_]u8{ 0, 0, 0, frame.len, 0, 0 });
    @memcpy(b[20..], frame);
    return b;
}

test "a Latin-1 TIT2 in a v2.3 tag is the title" {
    var out: [32]u8 = undefined;
    const b = tag(3, "\x00Les murs de demain");
    try std.testing.expectEqualStrings("Les murs de demain", id3.title(&b, &out));
}

test "a UTF-16 title with a BOM keeps its Latin letters" {
    var out: [32]u8 = undefined;
    const b = tag(3, "\x01\xFF\xFEH\x00i\x00");
    try std.testing.expectEqualStrings("Hi", id3.title(&b, &out));
}

test "no tag, a truncated tag, or a long title cut to the buffer" {
    var out: [4]u8 = undefined;
    try std.testing.expectEqualStrings("", id3.title(&[_]u8{ 0xFF, 0xFB, 0x90, 0, 0, 0, 0, 0, 0, 0 }, &out));
    const b = tag(4, "\x03Longer title");
    try std.testing.expectEqualStrings("", id3.title(b[0 .. b.len - 4], &out));
    try std.testing.expectEqualStrings("Long", id3.title(&b, &out));
}
