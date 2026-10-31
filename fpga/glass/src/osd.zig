// The OSD text as the ARM keeps it: a 32 x 16 grid of character words, drawn
// into here and then flushed to the PL. Only cells that changed since the last
// flush cross the bus (the text RAM is write-only, so this copy is the truth).
const std = @import("std");
const map = @import("map.zig");
const bus = @import("bus.zig");

pub const COLS = map.OSD_COLS;
pub const ROWS = map.OSD_ROWS;
/// The menu's MiSTer layout (strip.zig): column 0 the section strip, column 1 a gap,
/// rows 1..ROWS-2 hold the page's content from column BODY_COL; row 0 is the title
/// bar and the last row the status, both full width.
pub const BODY_COL = 2;
pub const BODY_W = COLS - BODY_COL;
const NEVER: u16 = 0xFFFF; // not a character word: forces the first flush to write every cell

pub const Osd = struct {
    text: [map.OSD_CHARS]u16 = [_]u16{' '} ** map.OSD_CHARS,
    shown: [map.OSD_CHARS]u16 = [_]u16{NEVER} ** map.OSD_CHARS,

    pub fn clear(self: *Osd) void {
        @memset(&self.text, ' ');
    }

    /// Write `s` at (col, row), clipped to the row; `inverse` swaps ink and paper.
    pub fn put(self: *Osd, col: u32, row: u32, s: []const u8, inverse: bool) void {
        if (row >= ROWS) return;
        const attr: u16 = if (inverse) map.OSD_INVERSE else 0;
        for (s, 0..) |c, i| {
            if (col + i >= COLS) break;
            // A control byte (a title's, a song name's) would show a rotated letter (map.OSD_ROT_BASE).
            self.text[row * COLS + col + i] = attr | @as(u16, if (c < ' ') ' ' else c);
        }
    }

    /// One glyph by its code, control codes included: the strip's rotated letters (strip.zig).
    pub fn glyph(self: *Osd, col: u32, row: u32, code: u8, inverse: bool) void {
        if (row >= ROWS or col >= COLS) return;
        const attr: u16 = if (inverse) map.OSD_INVERSE else 0;
        self.text[row * COLS + col] = attr | code;
    }

    /// A whole row, padded with spaces, so an inverse bar spans the window.
    pub fn line(self: *Osd, row: u32, s: []const u8, inverse: bool) void {
        var buf = [_]u8{' '} ** COLS;
        const n = @min(s.len, COLS);
        @memcpy(buf[0..n], s[0..n]);
        self.put(0, row, &buf, inverse);
    }

    /// A content row (BODY_COL to the right edge), padded, so a selected row's bar
    /// spans the panel but not the strip or its gap.
    pub fn body(self: *Osd, row: u32, s: []const u8, inverse: bool) void {
        var buf = [_]u8{' '} ** BODY_W;
        const n = @min(s.len, BODY_W);
        @memcpy(buf[0..n], s[0..n]);
        self.put(BODY_COL, row, &buf, inverse);
    }

    /// `s` at column `col` of the content area.
    pub fn bodyPut(self: *Osd, col: u32, row: u32, s: []const u8, inverse: bool) void {
        self.put(BODY_COL + col, row, s, inverse);
    }

    /// Send the changed cells; returns how many were written.
    pub fn flush(self: *Osd, regs: bus.Regs) u32 {
        var n: u32 = 0;
        for (self.text, &self.shown, 0..) |c, *s, i| {
            if (c == s.*) continue;
            regs.write(map.OFF_OSD_TEXT + 4 * @as(u32, @intCast(i)), c);
            s.* = c;
            n += 1;
        }
        return n;
    }

    /// The grid as text, one line a row (sim-menu and tests); inverse cells as upper bits dropped.
    pub fn dump(self: *const Osd, out: *[ROWS * (COLS + 1)]u8) void {
        for (0..ROWS) |r| {
            for (0..COLS) |c| out[r * (COLS + 1) + c] = @truncate(self.text[r * COLS + c]);
            out[r * (COLS + 1) + COLS] = '\n';
        }
    }
};

test "only changed cells cross the bus" {
    const sim = @import("sim.zig");
    var g = sim.Glass{};
    var o = Osd{};
    try std.testing.expectEqual(map.OSD_CHARS, o.flush(g.regs()));
    o.put(30, 2, "ABCD", true); // clipped at the right edge
    try std.testing.expectEqual(@as(u32, 2), o.flush(g.regs()));
    try std.testing.expectEqual(@as(u32, map.OSD_INVERSE | 'B'), g.text[2 * COLS + 31]);
    try std.testing.expectEqual(@as(u32, ' '), g.text[3 * COLS]);
    try std.testing.expectEqual(@as(u32, 0), o.flush(g.regs()));
    o.put(0, ROWS, "off the grid", false);
    try std.testing.expectEqual(@as(u32, 0), o.flush(g.regs()));
    o.put(0, 0, "a\x01b", false); // a control byte in text is a space, never a strip glyph
    try std.testing.expectEqual(@as(u16, ' '), o.text[1]);
    o.glyph(1, 0, map.OSD_ROT_BASE, true);
    try std.testing.expectEqual(@as(u16, map.OSD_INVERSE | map.OSD_ROT_BASE), o.text[1]);
}
