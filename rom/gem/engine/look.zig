// --------------------------------------------------------------------------
// GEM 5 engine: a LOOK — what the renderer needs besides the tree: how a GEM
// colour number (0 white, 1 black, 2 red ... 8 light grey, 9 dark grey) maps to
// the plane's palette, the fonts, the eight object fill patterns, and whether
// the TOS 4 3D rules apply. TOS 1's flat look and TOS 4's 3D look are two Looks
// over the same renderer; an asset set (assets.zig) supplies the fonts.
// --------------------------------------------------------------------------
const std = @import("std");
const canvas = @import("canvas.zig");
pub const Font = canvas.Font;

// GEM colour numbers (the VDI's first 16 pens).
pub const WHITE: u4 = 0;
pub const BLACK: u4 = 1;
pub const RED: u4 = 2;
pub const GREEN: u4 = 3;
pub const BLUE: u4 = 4;
pub const CYAN: u4 = 5;
pub const YELLOW: u4 = 6;
pub const MAGENTA: u4 = 7;
pub const LWHITE: u4 = 8; // light grey: TOS 4's 3D face
pub const LBLACK: u4 = 9; // dark grey: TOS 4's 3D shadow

pub const Look = struct {
    three_d: bool = false,
    pal: [16]u8, // GEM colour number -> plane palette index
    font: *const Font, // the system font (menus, buttons, titles)
    small: *const Font, // the small font (icon labels, te_font 5)
    patterns: *const [8][16]u16 = &PATTERNS,
    grey: u8 = 3, // a DISABLED object's text (a plane palette index)

    pub fn ink(self: *const Look, c: u4) u8 {
        return self.pal[c];
    }
    /// The colour a SELECTED object draws `c` in: white and black trade places
    /// (the AES inverts a selected object; on a palette plane that is the swap).
    pub fn inv(self: *const Look, c: u4, selected: bool) u8 {
        if (!selected) return self.pal[c];
        return switch (c) {
            WHITE => self.pal[BLACK],
            BLACK => self.pal[WHITE],
            else => self.pal[c],
        };
    }
};

/// The object patterns 0..7: 0 hollow, 7 solid, 1..6 ordered dithers from sparse
/// to dense (ours: a 4x4 Bayer order, tiled to 16x16).
pub const PATTERNS: [8][16]u16 = blk: {
    @setEvalBranchQuota(10000);
    const bayer = [4][4]u8{ .{ 0, 8, 2, 10 }, .{ 12, 4, 14, 6 }, .{ 3, 11, 1, 9 }, .{ 15, 7, 13, 5 } };
    const level = [8]u8{ 0, 2, 4, 6, 8, 10, 12, 16 }; // of 16 cells set
    var out: [8][16]u16 = undefined;
    for (0..8) |p| {
        for (0..16) |y| {
            var row: u16 = 0;
            for (0..16) |x| {
                if (bayer[y % 4][x % 4] < level[p]) row |= @as(u16, 0x8000) >> @intCast(x);
            }
            out[p][y] = row;
        }
    }
    break :blk out;
};

/// TOS 4's 3D offset: an indicator or an activator is drawn this much larger
/// than its box on every side (the room its bevel needs).
pub const ADJ3D: i16 = 2;

const expectEqual = std.testing.expectEqual;

test "patterns run from hollow to solid" {
    try expectEqual(@as(u16, 0), PATTERNS[0][5]);
    try expectEqual(@as(u16, 0xFFFF), PATTERNS[7][9]);
    var prev: u32 = 0;
    for (PATTERNS) |p| {
        var n: u32 = 0;
        for (p) |row| n += @popCount(row);
        try std.testing.expect(n >= prev);
        prev = n;
    }
    try expectEqual(@as(u32, 256), prev);
}

test "a selected object swaps white and black only" {
    var f = Font{ .w = 1, .h = 1, .data = &.{} };
    var pal: [16]u8 = undefined;
    for (&pal, 0..) |*p, i| p.* = @intCast(40 + i);
    const l: Look = .{ .pal = pal, .font = &f, .small = &f };
    try expectEqual(@as(u8, 41), l.inv(WHITE, true));
    try expectEqual(@as(u8, 40), l.inv(BLACK, true));
    try expectEqual(@as(u8, 42), l.inv(RED, true));
    try expectEqual(@as(u8, 40), l.inv(WHITE, false));
}
