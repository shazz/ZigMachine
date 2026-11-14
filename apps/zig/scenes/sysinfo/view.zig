// --------------------------------------------------------------------------
// SysInfo — the page on the screen mode's glass. Every page is composed once,
// as HWAM's 80 x 25 medium-res text (grid.zig); the screen shows it in the
// mode the user picked (L / M / D, F6 cycles):
//
//   medium  640 x 200: the page as composed, 8 x 8 cells
//   desk    640 x 480: the same 80 x 25 cells, each 8 x 16 (the 8x8 glyphs drawn
//           twice as tall, as medium's 2:1 pixels show them on an ST monitor),
//           the page centred: DESK_TOP rows above it
//   low     320 x 200: 40 columns. Two columns of 40 do not fit, so the page is
//           shown a half at a time (Tab): the program line and the prompt left
//           aligned, rows 1..23 from the left half (columns 0..39) or the right
//           one (COL2 - 1 ..), the program line naming the half
//
// Pure: no machine, no ROM. Tested natively (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const grid = @import("grid.zig");

pub const Mode = enum(u8) { low = 0, medium = 1, desk = 2 }; // rom_sdk.aes.ScreenMode's numbers

pub const LOW_COLS: usize = 40;
/// Where the right half starts in low res: one column left of COL2, so its fields' colons line up.
pub const RIGHT_AT: usize = grid.COL2 - 1;
/// The desk's pixel rows above the page: (480 - 25 * 16) / 2.
pub const DESK_TOP: i16 = 40;
/// Where low res names the page and the half on the program line.
const LOW_TAG_COL: usize = 37;

pub fn cols(m: Mode) usize {
    return if (m == .low) LOW_COLS else grid.COLS;
}

/// A cell's top-left pixel and its height in this mode.
pub fn cellY(m: Mode, row: usize) i16 {
    const r: i16 = @intCast(row);
    return if (m == .desk) DESK_TOP + r * 16 else r * 8;
}
pub fn cellH(m: Mode) i16 {
    return if (m == .desk) 16 else 8;
}

pub fn width(m: Mode) i16 {
    return if (m == .low) 320 else 640;
}
pub fn height(m: Mode) i16 {
    return if (m == .desk) 480 else 200;
}

/// What the glass shows of `page` in mode `m`; `right` picks low res's right half.
pub fn project(page: *const grid.Grid, out: *grid.Grid, m: Mode, right: bool) void {
    if (m != .low) {
        out.* = page.*;
        return;
    }
    out.clear();
    const off: usize = if (right) RIGHT_AT else 0;
    for (0..grid.ROWS) |r| {
        const from: usize = if (r == 0 or r == grid.ROWS - 1) 0 else off;
        const n = @min(LOW_COLS, grid.COLS - from);
        @memcpy(out.ch[r][0..n], page.ch[r][from .. from + n]);
        @memcpy(out.at[r][0..n], page.at[r][from .. from + n]);
    }
    // the program line: its start, then the page's number (PAGE n at column 73) and the half
    @memset(out.ch[0][LOW_TAG_COL..LOW_COLS], ' ');
    var tag = [3]u8{ 'P', page.ch[0][78], if (right) 'R' else 'L' };
    out.put(0, LOW_TAG_COL, &tag, page.at[0][73]);
}

// --- native tests ------------------------------------------------------------
fn sample() grid.Grid {
    var p: grid.Grid = undefined;
    p.clear();
    p.put(0, 1, "SYSINFO FOR ZIGMACHINE, VERSION 2.0  (AFTER HWAM SYSINFO 8.34)", .small);
    p.put(0, 73, "PAGE 3", .small);
    p.field(3, 0, "TYPE", "ZIGMACHINE");
    p.field(3, grid.COL2, "CART WINDOW", "$100000-$400000");
    p.put(24, 1, "PRESS SPACE OR CLICK FOR MENU !", .small);
    return p;
}

test "medium and desk show the page as composed" {
    const p = sample();
    var o: grid.Grid = undefined;
    project(&p, &o, .desk, false);
    try std.testing.expectEqualSlices(u8, &p.ch[3], &o.ch[3]);
}

test "low res shows the left half, then the right one, its colons where the left's are" {
    const p = sample();
    var o: grid.Grid = undefined;
    project(&p, &o, .low, false);
    try std.testing.expectEqualStrings("TYPE", o.ch[3][0..4]);
    try std.testing.expectEqualStrings("P3L", o.ch[0][LOW_TAG_COL .. LOW_TAG_COL + 3]);
    try std.testing.expectEqual(@as(u8, ' '), o.ch[3][LOW_COLS]);
    project(&p, &o, .low, true);
    try std.testing.expectEqualStrings(" CART WINDOW", o.ch[3][0..12]);
    try std.testing.expectEqual(@as(u8, ':'), o.ch[3][1 + grid.LABEL_W]);
    try std.testing.expectEqualStrings("P3R", o.ch[0][LOW_TAG_COL .. LOW_TAG_COL + 3]);
    try std.testing.expectEqualStrings(" PRESS SPACE", o.ch[24][0..12]); // the prompt stays
}

test "the desk is 25 rows of 16 pixels, centred in 480" {
    try std.testing.expectEqual(@as(i16, 480), 2 * DESK_TOP + 25 * cellH(.desk));
    try std.testing.expectEqual(@as(i16, 16 * 8), cellY(.medium, 16));
}
