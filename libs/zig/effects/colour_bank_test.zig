// Tests for effects/colour_bank.zig: sharing within a frame, forgetting across
// frames, running out, and the stamp wrap.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const ColourBank = @import("colour_bank.zig").ColourBank;

test "one colour, one entry, written opaque" {
    var bank: ColourBank = undefined;
    bank.init(3);
    var pal = [_]u32{0} ** 256;
    bank.begin();
    try expectEqual(@as(?u8, 3), bank.entry(&pal, 0x112233));
    try expectEqual(@as(?u8, 4), bank.entry(&pal, 0x445566));
    try expectEqual(@as(?u8, 3), bank.entry(&pal, 0x112233));
    try expectEqual(@as(u32, 0xFF112233), pal[3]);
    try expectEqual(@as(u32, 0xFF445566), pal[4]);
    try expectEqual(@as(usize, 2), bank.used());
}

test "begin() frees every entry" {
    var bank: ColourBank = undefined;
    bank.init(10);
    var pal = [_]u32{0} ** 256;
    bank.begin();
    _ = bank.entry(&pal, 1);
    _ = bank.entry(&pal, 2);
    bank.begin();
    try expectEqual(@as(?u8, 10), bank.entry(&pal, 2));
    try expectEqual(@as(u32, 0xFF000002), pal[10]);
}

test "the entries run out at 255, and black is a colour like any other" {
    var bank: ColourBank = undefined;
    bank.init(250);
    var pal = [_]u32{0} ** 256;
    bank.begin();
    for (0..6) |i| try expectEqual(@as(?u8, @intCast(250 + i)), bank.entry(&pal, @intCast(i)));
    try expectEqual(@as(?u8, null), bank.entry(&pal, 99));
    try expectEqual(@as(?u8, 250), bank.entry(&pal, 0)); // already held: still answered
}

test "255 distinct colours in one frame all get their own entry" {
    var bank: ColourBank = undefined;
    bank.init(1);
    var pal = [_]u32{0} ** 256;
    bank.begin();
    for (0..255) |i| try expectEqual(@as(?u8, @intCast(1 + i)), bank.entry(&pal, @intCast(i * 7919)));
    for (0..255) |i| try expectEqual(@as(?u8, @intCast(1 + i)), bank.entry(&pal, @intCast(i * 7919)));
}

test "the frame stamp wraps without resurrecting old colours" {
    var bank: ColourBank = undefined;
    bank.init(5);
    var pal = [_]u32{0} ** 256;
    bank.begin();
    _ = bank.entry(&pal, 0xABCDEF);
    bank.frame = 0xFFFF; // the next begin() wraps
    bank.begin();
    try expectEqual(@as(?u8, 5), bank.entry(&pal, 0x010203));
    try expectEqual(@as(?u8, 6), bank.entry(&pal, 0xABCDEF));
}
