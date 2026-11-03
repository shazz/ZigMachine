// Tests for the true-colour plane's pixel rules (HW 1.15.0, machine/video_tc.zig): the 565
// expansion over all 65,536 values against the formula written out channel by channel, its
// fixed points, the ignored bit 0 of a line address, and a doubled line.
const std = @import("std");
const tc = @import("video_tc.zig");
const expectEqual = std.testing.expectEqual;

// The study's formula (fpga/review/TRUECOLOR_PLANE.md), in floats-free integer form: scale the
// 5/6-bit channel to 8 bits by replicating its top bits into the low ones.
fn reference(px: u32) [3]u32 {
    const r = px >> 11 & 31;
    const g = px >> 5 & 63;
    const b = px & 31;
    return .{ r * 8 + r / 4, g * 4 + g / 16, b * 8 + b / 4 };
}

test "every 565 value expands by bit replication, alpha 255" {
    var px: u32 = 0;
    while (px <= 0xFFFF) : (px += 1) {
        const c = tc.expand(@intCast(px));
        const want = reference(px);
        try expectEqual(want[0], c & 0xFF);
        try expectEqual(want[1], c >> 8 & 0xFF);
        try expectEqual(want[2], c >> 16 & 0xFF);
        try expectEqual(@as(u32, 0xFF), c >> 24);
    }
}

test "the corners: white, black and the primaries are exact" {
    try expectEqual(@as(u32, 0xFFFFFFFF), tc.expand(0xFFFF));
    try expectEqual(@as(u32, 0xFF000000), tc.expand(0x0000));
    try expectEqual(@as(u32, 0xFF0000FF), tc.expand(0xF800));
    try expectEqual(@as(u32, 0xFF00FF00), tc.expand(0x07E0));
    try expectEqual(@as(u32, 0xFFFF0000), tc.expand(0x001F));
    // the RTL prototype's iverilog vectors (TRUECOLOR_PLANE.md "Function check")
    try expectEqual(@as(u32, 0xFF848284), tc.expand(0x8410));
    try expectEqual(@as(u32, 0xFFA54510), tc.expand(0x1234));
    try expectEqual(@as(u32, 0xFF6B79AD), tc.expand(0xABCD));
}

test "a shift alone is not the rule: 0xFFFF would not be white" {
    const shifted: u32 = (0x1F << 3) | (0x3F << 2) << 8 | (0x1F << 3) << 16;
    try std.testing.expect(tc.expand(0xFFFF) & 0xFFFFFF != shifted);
}

test "bit 0 of a line address is ignored: odd base or HSCROLL lands on the pixel below" {
    try expectEqual(@as(usize, 1000), tc.lineAt(1001, 0));
    try expectEqual(@as(usize, 1000), tc.lineAt(1000, 1));
    try expectEqual(@as(usize, 1002), tc.lineAt(1001, 1));
    try expectEqual(@as(usize, 640), tc.lineAt(640, 0));
}

test "a line writes each pixel doubled, little-endian words" {
    const src = [_]u8{ 0xFF, 0xFF, 0x00, 0xF8, 0x1F, 0x00 } ++ [_]u8{0} ** 2;
    var out = [_]u64{0} ** 4;
    tc.line(&out, &src, 0, 3, .{});
    try expectEqual(@as(u64, 0xFFFFFFFF_FFFFFFFF), out[0]);
    try expectEqual(@as(u64, 0xFF0000FF_FF0000FF), out[1]);
    try expectEqual(@as(u64, 0xFFFF0000_FFFF0000), out[2]);
    try expectEqual(@as(u64, 0), out[3]); // n stops the line
}
