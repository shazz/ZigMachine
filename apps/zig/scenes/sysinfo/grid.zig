// --------------------------------------------------------------------------
// SysInfo — the screen as a text grid. HWAM's SysInfo is an 80 x 25 page of
// text on the ST's medium-res screen (640 x 200, 8 x 8 cells), so the app keeps
// two grids: what each page WANTS on the glass, and what is on it. Only the
// span of a row that differs is redrawn (screen.zig), which is what keeps a
// live page cheap on the board, where every store is a blocking DDR write.
//
// Pure: no machine, no ROM. Tested natively (apps/zig/scene_tests.zig).
// --------------------------------------------------------------------------
const std = @import("std");

pub const COLS: usize = 80;
pub const ROWS: usize = 25;
/// Where HWAM's second column starts.
pub const COL2: usize = 41;
/// "LABEL<pad>: value": the colon sits at this offset from the column.
pub const LABEL_W: usize = 16;

/// Underlined text is HWAM's section heading ("SYSTEM INFO:", "MEMORY:");
/// inverse marks the speed test that is running.
pub const Attr = enum(u8) { plain, under, inverse };

pub const Span = struct { c0: usize, c1: usize }; // columns [c0, c1)

pub const Grid = struct {
    ch: [ROWS][COLS]u8,
    at: [ROWS][COLS]Attr,

    pub fn clear(self: *Grid) void {
        for (&self.ch) |*r| @memset(r, ' ');
        for (&self.at) |*r| @memset(r, .plain);
    }

    /// Write `s` at (row, col), clipped to the row. Lower case is kept: the
    /// system font has it, and GEM's own strings use it.
    pub fn put(self: *Grid, row: usize, col: usize, s: []const u8, attr: Attr) void {
        if (row >= ROWS or col >= COLS) return;
        const n = @min(s.len, COLS - col);
        @memcpy(self.ch[row][col .. col + n], s[0..n]);
        @memset(self.at[row][col .. col + n], attr);
    }

    /// put() with std.fmt; a line longer than a row is cut, never an error.
    pub fn print(self: *Grid, row: usize, col: usize, comptime fmt: []const u8, args: anytype) void {
        var buf: [COLS]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        w.print(fmt, args) catch {};
        self.put(row, col, w.buffered(), .plain);
    }

    /// HWAM's "LABEL           : value" line.
    pub fn field(self: *Grid, row: usize, col: usize, label: []const u8, value: []const u8) void {
        self.put(row, col, label, .plain);
        self.put(row, col + LABEL_W, ": ", .plain);
        self.put(row, col + LABEL_W + 2, value, .plain);
    }

    /// field() with a formatted value.
    pub fn fieldf(self: *Grid, row: usize, col: usize, label: []const u8, comptime fmt: []const u8, args: anytype) void {
        var buf: [COLS]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        w.print(fmt, args) catch {};
        self.field(row, col, label, w.buffered());
    }

    /// Mark a row as unknown: the next diff() against it covers the whole row.
    pub fn invalidate(self: *Grid) void {
        for (&self.ch) |*r| @memset(r, 0);
    }
};

/// The columns of `row` where `want` and `shown` differ, as one span from the
/// first to the last difference, or null when the row is already right.
pub fn diff(want: *const Grid, shown: *const Grid, row: usize) ?Span {
    var c0: usize = COLS;
    var c1: usize = 0;
    for (0..COLS) |c| {
        if (want.ch[row][c] == shown.ch[row][c] and want.at[row][c] == shown.at[row][c]) continue;
        c0 = @min(c0, c);
        c1 = c + 1;
    }
    return if (c0 < c1) .{ .c0 = c0, .c1 = c1 } else null;
}

/// After drawing `sp`, the glass holds what `want` says there.
pub fn commit(want: *const Grid, shown: *Grid, row: usize, sp: Span) void {
    @memcpy(shown.ch[row][sp.c0..sp.c1], want.ch[row][sp.c0..sp.c1]);
    @memcpy(shown.at[row][sp.c0..sp.c1], want.at[row][sp.c0..sp.c1]);
}

/// The run of cells from `c` that share one attribute, ending by `end`.
pub fn runEnd(g: *const Grid, row: usize, c: usize, end: usize) usize {
    var e = c + 1;
    while (e < end and g.at[row][e] == g.at[row][c]) e += 1;
    return e;
}

// --- native tests ------------------------------------------------------------
test "a row that matches the glass needs no redraw" {
    var a: Grid = undefined;
    var b: Grid = undefined;
    a.clear();
    b.clear();
    a.put(3, 0, "TYPE", .plain);
    b.put(3, 0, "TYPE", .plain);
    try std.testing.expectEqual(@as(?Span, null), diff(&a, &b, 3));
}

test "only the changed span of a row is redrawn" {
    var a: Grid = undefined;
    var b: Grid = undefined;
    a.clear();
    b.clear();
    a.field(5, 0, "FREE", "1234 Kbytes");
    b.field(5, 0, "FREE", "1299 Kbytes");
    const sp = diff(&a, &b, 5).?;
    try std.testing.expectEqual(@as(usize, LABEL_W + 2 + 2), sp.c0);
    try std.testing.expectEqual(@as(usize, LABEL_W + 2 + 4), sp.c1);
    commit(&a, &b, 5, sp);
    try std.testing.expectEqual(@as(?Span, null), diff(&a, &b, 5));
}

test "an attribute change alone is a difference" {
    var a: Grid = undefined;
    var b: Grid = undefined;
    a.clear();
    b.clear();
    a.put(2, 4, "MEMORY:", .under);
    b.put(2, 4, "MEMORY:", .plain);
    const sp = diff(&a, &b, 2).?;
    try std.testing.expectEqual(@as(usize, 4), sp.c0);
    try std.testing.expectEqual(@as(usize, 11), sp.c1);
}

test "text past the right edge is clipped, not wrapped" {
    var a: Grid = undefined;
    a.clear();
    a.put(0, COLS - 2, "ABCD", .plain);
    try std.testing.expectEqualStrings("AB", a.ch[0][COLS - 2 ..]);
    a.put(ROWS, 0, "X", .plain); // off the grid: ignored
}

test "an invalidated grid differs from every page on every row" {
    var a: Grid = undefined;
    var b: Grid = undefined;
    a.clear();
    b.invalidate();
    const sp = diff(&a, &b, 0).?;
    try std.testing.expectEqual(@as(usize, 0), sp.c0);
    try std.testing.expectEqual(COLS, sp.c1);
}

test "a formatted field longer than the row is cut" {
    var a: Grid = undefined;
    a.clear();
    a.fieldf(1, COL2, "LONG", "{s}", .{"X" ** 60});
    try std.testing.expectEqual(@as(u8, 'X'), a.ch[1][COLS - 1]);
}

test "runEnd stops where the attribute changes" {
    var a: Grid = undefined;
    a.clear();
    a.put(0, 0, "AB", .under);
    try std.testing.expectEqual(@as(usize, 2), runEnd(&a, 0, 0, COLS));
    try std.testing.expectEqual(COLS, runEnd(&a, 0, 2, COLS));
}
