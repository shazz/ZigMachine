// Native test of the rebuilt Amiga copper list and its translation
// (amiga_copper.zig) and of the compile-time text printer (screen.zig), against
// numbers read off the original by hand (prototypes/hippel_musicdisk_re/NOTES.md).
// Run through apps/zig/scene_tests.zig (the embeds are relative to apps/zig/).
const std = @import("std");
const C = @import("amiga_copper.zig");
const S = @import("screen.zig");

test "the list is $02C2's: 12,846 words, ending where the blitter's save row starts" {
    try std.testing.expectEqual(@as(usize, 12846), C.LEN);
    try std.testing.expectEqual(@as(usize, 0x7D5C - 0x1900), C.LEN * 2);
    try std.testing.expectEqual(@as(u16, 0x0180), C.AMIGA_LIST[0]);
    try std.testing.expectEqual(@as(u16, 0x2F0F), C.AMIGA_LIST[2]);
    // the template follows the top bar: DIWSTRT $4081 at word 70
    try std.testing.expectEqual(@as(u16, 0x008E), C.AMIGA_LIST[70]);
    try std.testing.expectEqual(@as(u16, 0x4081), C.AMIGA_LIST[71]);
    try std.testing.expectEqual(@as(u16, 0xFFFF), C.AMIGA_LIST[C.LEN - 2]);
    try std.testing.expectEqual(@as(u16, 0xFFFE), C.AMIGA_LIST[C.LEN - 1]);
}

test "the bar moves $025E writes sit on lines $2F..$3E and $108..$117" {
    try std.testing.expectEqual(@as(usize, 36), C.WALK.move00_count);
    for (0..C.BAR_LINES) |j| {
        try std.testing.expectEqual(@as(u16, @intCast(0x2F + j)), C.WALK.move00_line[C.TOP_MOVE + j]);
        try std.testing.expectEqual(@as(u16, @intCast(0x108 + j)), C.WALK.move00_line[C.BOTTOM_MOVE + j]);
    }
    try std.testing.expectEqual(@as(u16, 0x40), C.WALK.diw_line);
    try std.testing.expectEqual(@as(u16, 0x888), C.WALK.color09);
}

test "the text rows: a blue ramp up and back, red then green per line" {
    try std.testing.expectEqual(@as(u16, 0x000), C.WALK.text[0][0]);
    try std.testing.expectEqual(@as(u16, 0x00F), C.WALK.text[0][15]);
    try std.testing.expectEqual(@as(u16, 0x00F), C.WALK.text[0][16]);
    try std.testing.expectEqual(@as(u16, 0x000), C.WALK.text[0][31]);
    try std.testing.expectEqual(@as(u16, 0xF05), C.WALK.text[15][5]);
    try std.testing.expectEqual(@as(u16, 0xF10), C.WALK.text[17][0]);
    try std.testing.expectEqual(@as(u16, 0x0F0), C.WALK.text[48][0]);
    try std.testing.expectEqual(@as(u16, 0x010), C.WALK.text[62][0]);
    try std.testing.expectEqual(C.WALK.text[5], C.WALK.text[64 + 5]); // made 3 times
}

test "the bars: the shade is subtracted per channel and floors at 0" {
    // top line 0 at rotation 4 is the magenta 0F0F minus grey AAA = 505
    try std.testing.expectEqual(C.rgba(0x505), C.TOP_BAR[4][0]);
    try std.testing.expectEqual(C.rgba(0x00B), C.TOP_BAR[4][4]); // 00F - 444
    try std.testing.expectEqual(C.rgba(0xF0F), C.BOTTOM_BAR[0][7]); // 0F0F - grey 000
    try std.testing.expectEqual(@as(u32, 0xFF55_0055), C.rgba(0x505));
}

test "the printer: the title is row 8, the last line row 186, nothing below 194" {
    try std.testing.expect(!S.hasText(6)); // row 7 empty
    try std.testing.expect(S.hasText(7)); // "Feinbeinsoftware" from row 8
    try std.testing.expect(S.hasText(192)); // "- Spreading Rights -" rows 186..193
    for (193..S.LINES) |n| try std.testing.expect(!S.hasText(n));
    // 'F' of "Feinbeinsoftware", doubled: its top row is the font's, bit for bit wide
    try std.testing.expect(S.bit(8, 0) == S.bit(8, 1));
}
