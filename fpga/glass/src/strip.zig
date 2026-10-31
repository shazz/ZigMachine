// The menu's section strip, MiSTer-style: column 0 of rows 1..ROWS-2 is a light
// (inverse) bar carrying the page's name, the list on the dark panel to its right
// (osd.BODY_COL). The name is stacked upright, one letter a row from the top.
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");

pub const FIRST = 1;
pub const LAST = osd.ROWS - 2;
/// The upright name's first letter, one cell below the strip's top.
pub const STACK_ROW = FIRST + 1;

/// Paint the strip and its name; column 1 stays the dark gap.
pub fn draw(o: *osd.Osd, name: []const u8) void {
    for (FIRST..LAST + 1) |r| o.put(0, @intCast(r), " ", true);
    for (name, 0..) |c, i| {
        const row = STACK_ROW + i;
        if (row > LAST) break;
        o.put(0, @intCast(row), &.{c}, true);
    }
}

test "the strip is inverse from row 1 to 14, the name stacked down it, the gap dark" {
    var o = osd.Osd{};
    draw(&o, "CONSOLE");
    try std.testing.expectEqual(@as(u16, ' '), o.text[0]); // the title row is the page's
    for (FIRST..LAST + 1) |r| {
        const c = o.text[r * osd.COLS];
        try std.testing.expect(c & map.OSD_INVERSE != 0);
        const want: u8 = if (r >= STACK_ROW and r < STACK_ROW + 7) "CONSOLE"[r - STACK_ROW] else ' ';
        try std.testing.expectEqual(@as(u16, want), c & 0xFF);
        try std.testing.expectEqual(@as(u16, ' '), o.text[r * osd.COLS + 1]);
    }
    try std.testing.expectEqual(@as(u16, ' '), o.text[(osd.ROWS - 1) * osd.COLS]); // nor the status row
    draw(&o, "A NAME LONGER THAN THE STRIP"); // cut at the strip's end, never into the status row
    try std.testing.expectEqual(@as(u16, ' '), o.text[(osd.ROWS - 1) * osd.COLS]);
}
