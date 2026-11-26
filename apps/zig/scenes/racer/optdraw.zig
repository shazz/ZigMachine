// --------------------------------------------------------------------------
// RACER: the options screen (M5 finish) on a menu frame: a heading, one row a setting (its label,
// its value between arrows; the cursor's row highlighted) and the footer. The values are
// options.zig's (the same state the debug keys change).
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const fd = @import("frontdraw.zig");
const menu = @import("menu.zig");
const options = @import("options.zig");
const palette = @import("palette.zig");

pub const BOX = [4]i32{ 24, 36, 272, 132 }; // x, y, w, h (M6: 7 rows)
pub const ROW = 16;
pub const FOOT = "UP/DN ROW  LEFT/RIGHT SET  BKSP BACK";

pub fn draw(d: anytype, os: *zg.ZigOS, fb: *zg.LogicalFB, p: menu.Px) void {
    p.panel(8, 16, 304, 12);
    fd.text(os, fb, "OPTIONS", 160 - 7 * 4, 18, menu.HILITE);
    p.panel(BOX[0], BOX[1], BOX[2], BOX[3]);
    p.panel(8, 178, 304, 10);
    fd.text(os, fb, FOOT, 160 - FOOT.len * 4, 179, palette.INK);
    var y: i32 = BOX[1] + 8;
    var vb: [8]u8 = undefined;
    var lb: [36]u8 = undefined;
    for (0..options.ROWS) |i| {
        const r: options.Row = @enumFromInt(i);
        const on = r == d.front.row;
        const ink = if (on) menu.HILITE else palette.INK;
        const v = options.value(d, r, &vb);
        const line = if (r == .back)
            std.fmt.bufPrint(&lb, "{s}{s}", .{ if (on) ">" else " ", options.LABELS[i] }) catch ""
        else
            std.fmt.bufPrint(&lb, "{s}{s:<14}< {s} >", .{ if (on) ">" else " ", options.LABELS[i], v }) catch "";
        fd.text(os, fb, line, BOX[0] + 8, y, ink);
        y += ROW;
    }
}
