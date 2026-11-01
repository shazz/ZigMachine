// The menu's section strip, MiSTer-style: column 0 of rows 1..ROWS-2 is a light
// (inverse) bar carrying the page's name, the list on the dark panel to its right
// (osd.BODY_COL). On a PL whose font has the rotated letters (map.VERSION_OSD_ROTATED)
// the name reads bottom to top, turned 90 degrees, as MiSTer's does; on an older one
// the same codes are blank, so the name is stacked upright, one letter a row.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");

pub const FIRST = 1;
pub const LAST = osd.ROWS - 2;
/// The upright name's first letter, one cell below the strip's top.
pub const STACK_ROW = FIRST + 1;
/// The rotated name's first letter, one cell above the strip's bottom; the rest rise from it.
pub const ROT_ROW = LAST - 1;

pub fn supported(pl_version: u32) bool {
    return pl_version >= map.VERSION_OSD_ROTATED;
}

/// The rotated glyph for a letter of a section name; anything but A-Z is a blank.
pub fn rotatedCode(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') @intCast(map.OSD_ROT_BASE + (c - 'A')) else ' ';
}

/// Paint the strip and its name; column 1 stays the dark gap.
pub fn draw(o: *osd.Osd, name: []const u8, rotated: bool) void {
    for (FIRST..LAST + 1) |r| o.put(0, @intCast(r), " ", true);
    for (name, 0..) |c, i| {
        if (i > LAST - FIRST) break;
        if (rotated) {
            if (ROT_ROW < FIRST + i) break;
            o.glyph(0, @intCast(ROT_ROW - i), rotatedCode(c), true);
        } else {
            if (STACK_ROW + i > LAST) break;
            o.put(0, @intCast(STACK_ROW + i), &.{c}, true);
        }
    }
}

fn col0(o: *const osd.Osd, r: usize) u16 {
    return o.text[r * osd.COLS];
}

test "the strip is inverse from row 1 to 14, the name stacked down it, the gap dark" {
    var o = osd.Osd{};
    draw(&o, "CONSOLE", false);
    try std.testing.expectEqual(@as(u16, ' '), o.text[0]); // the title row is the page's
    for (FIRST..LAST + 1) |r| {
        try std.testing.expect(col0(&o, r) & map.OSD_INVERSE != 0);
        const want: u8 = if (r >= STACK_ROW and r < STACK_ROW + 7) "CONSOLE"[r - STACK_ROW] else ' ';
        try std.testing.expectEqual(@as(u16, want), col0(&o, r) & 0xFF);
        try std.testing.expectEqual(@as(u16, ' '), o.text[r * osd.COLS + 1]);
    }
    try std.testing.expectEqual(@as(u16, ' '), col0(&o, osd.ROWS - 1)); // nor the status row
    draw(&o, "A NAME LONGER THAN THE STRIP", false); // cut at the strip's end
    try std.testing.expectEqual(@as(u16, ' '), col0(&o, osd.ROWS - 1));
}

test "rotated, the name reads bottom to top in the rotated glyphs, from one above the bottom" {
    var o = osd.Osd{};
    draw(&o, "SHELF", true);
    for ("SHELF", 0..) |c, i| {
        const want: u16 = @intCast(map.OSD_INVERSE | map.OSD_ROT_BASE + (c - 'A'));
        try std.testing.expectEqual(want, col0(&o, ROT_ROW - i));
    }
    try std.testing.expectEqual(@as(u16, map.OSD_INVERSE | ' '), col0(&o, LAST)); // the margin
    try std.testing.expectEqual(@as(u16, map.OSD_INVERSE | ' '), col0(&o, ROT_ROW - 5));
    draw(&o, "A NAME LONGER THAN THE STRIP", true); // cut at the strip's top, never the title
    try std.testing.expectEqual(@as(u16, ' '), o.text[0]);
    try std.testing.expectEqual(@as(u8, ' '), rotatedCode('?'));
    try std.testing.expect(!supported(map.VERSION_OSD_STATS));
    try std.testing.expect(supported(map.VERSION));
}
