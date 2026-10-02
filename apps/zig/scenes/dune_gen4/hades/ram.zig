// F2 draws the way the original does, into two ST screens in ST format (four
// interleaved bitplanes, 160 bytes a line), because what it leaves behind
// matters: every sprite is erased where it was drawn ONE VBL ago -- on the other
// screen -- so a sliver of the logo two VBLs old survives above it, and the
// stars ORed over it then show in its colours. Byte for byte is the only way
// that comes out the same. The screen on show is turned into palette indices
// once a frame (hades.zig).

pub const LINE = 160;
/// Lines 0..199 and the lower border the scroller is copied into (to 227).
pub const LINES = 232;
pub const Screen = [LINES * LINE]u8;

pub var screens: [2]Screen = undefined;

pub fn r16(s: *const Screen, at: usize) u16 {
    return @as(u16, s[at]) << 8 | s[at + 1];
}

pub fn w16(s: *Screen, at: usize, v: u16) void {
    s[at] = @truncate(v >> 8);
    s[at + 1] = @truncate(v);
}

/// The byte offset of ST pixel (x, y)'s 16-pixel group, as the code computes
/// it: y * 160 + (x & $FFF0) / 2.
pub fn groupAt(x: usize, y: usize) usize {
    return y * LINE + (x & 0xFFF0) / 2;
}

/// The palette indices of line `y`'s 320 pixels, through the shifter.
pub fn pixels(s: *const Screen, y: usize, px: *[320]u8) void {
    for (0..20) |g| {
        const at = y * LINE + g * 8;
        const p = [4]u16{ r16(s, at), r16(s, at + 2), r16(s, at + 4), r16(s, at + 6) };
        for (0..16) |i| {
            const b: u4 = @intCast(15 - i);
            var v: u8 = 0;
            for (p, 0..) |w, k| v |= @as(u8, @intCast((w >> b) & 1)) << @intCast(k);
            px[g * 16 + i] = v;
        }
    }
}

test "the shifter reads plane k as bit k, leftmost pixel first" {
    const std = @import("std");
    var s: Screen = undefined;
    @memset(&s, 0);
    w16(&s, LINE + 8, 0x8000); // line 1, group 1, plane 0: pixel 16
    w16(&s, LINE + 14, 0x0001); // plane 3: pixel 31
    var px: [320]u8 = undefined;
    pixels(&s, 1, &px);
    try std.testing.expectEqual(@as(u8, 1), px[16]);
    try std.testing.expectEqual(@as(u8, 8), px[31]);
    try std.testing.expectEqual(@as(u8, 0), px[17]);
    try std.testing.expectEqual(@as(usize, LINE * 3 + 8), groupAt(31, 3));
}
