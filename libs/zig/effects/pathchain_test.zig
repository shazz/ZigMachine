// Tests for effects/pathchain.zig: the JS chain `table[(t - i*lag) % len]`,
// including the sprites that are not on the path yet.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const pathchain = @import("pathchain.zig");

const XS = [_]u16{ 10, 11, 12, 13, 14, 15, 16 };
const YS = [_]u16{ 20, 21, 22, 23, 24, 25, 26 };

test "the lead sprite walks the path from its first point and wraps at its length" {
    try expectEqual(pathchain.Point(u16){ .x = 10, .y = 20 }, pathchain.at(u16, &XS, &YS, 0, 0, 5).?);
    try expectEqual(pathchain.Point(u16){ .x = 16, .y = 26 }, pathchain.at(u16, &XS, &YS, 6, 0, 5).?);
    try expectEqual(pathchain.Point(u16){ .x = 10, .y = 20 }, pathchain.at(u16, &XS, &YS, 7, 0, 5).?);
    try expectEqual(@as(?usize, 3), pathchain.index(1_000_003, 0, 5, 1_000_000));
}

test "sprite i trails i*lag steps behind and is absent until it reaches the path" {
    // screen2.js: (spritePos - i*5) % len is negative, so array[-k] is undefined
    try expectEqual(@as(?pathchain.Point(u16), null), pathchain.at(u16, &XS, &YS, 9, 2, 5));
    try expectEqual(pathchain.Point(u16){ .x = 10, .y = 20 }, pathchain.at(u16, &XS, &YS, 10, 2, 5).?);
    try expectEqual(pathchain.Point(u16){ .x = 13, .y = 23 }, pathchain.at(u16, &XS, &YS, 13, 2, 5).?);
    try expectEqual(@as(?usize, 0), pathchain.index(7, 1, 0, XS.len)); // lag 0: every sprite on the lead
}

test "an empty path, a short y table and a huge i*lag answer null instead of reading past a table" {
    try expectEqual(@as(?pathchain.Point(u16), null), pathchain.at(u16, &.{}, &.{}, 100, 0, 5));
    try expectEqual(@as(?pathchain.Point(u16), null), pathchain.at(u16, &XS, YS[0..3], 5, 0, 5));
    try expectEqual(@as(?usize, null), pathchain.index(std.math.maxInt(u32), std.math.maxInt(u32), 2, XS.len));
}
