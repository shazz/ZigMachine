// The OSD's home page: the shelf of carts on top, the selected one's details
// below (docs/FPGA_GLASS.md, "The menu").
//
//   row 0       title bar: page name, cursor/count, '>' to the console page
//   rows 1..9   the carts by title, the cursor's row inverse; '*' = loaded
//   row 10      a rule
//   row 11      group, year and machine of the selected cart
//   rows 12..14 its one-line description, word-wrapped
//   row 15      status: a hint, or the last error
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const text = @import("text.zig");
const shelf = @import("shelf.zig");

pub const FIRST = 1;
pub const SHOWN = 9;
pub const RULE = 10;
pub const DETAIL = 11;
const DESC_ROWS = 3;
const NAME_W = osd.COLS - 1; // column 0 is the loaded mark

pub const Key = enum { none, close, load, console, cold, warm };

pub const State = struct {
    cursor: usize = 0,
    top: usize = 0,
    phase: usize = 0, // the marquee's step, advanced by the app's tick

    /// A key event (map.KEY_*), down edges and repeats only.
    pub fn key(self: *State, code: u32, n: usize) Key {
        switch (code) {
            map.KEY_ARROW_UP => self.cursor -|= 1,
            map.KEY_ARROW_DOWN => if (self.cursor + 1 < n) {
                self.cursor += 1;
            },
            map.KEY_ARROW_RIGHT => return .console,
            map.KEY_ESCAPE => return .close,
            map.KEY_ENTER, ' ' => return if (n > 0) .load else .none,
            'r', 'R' => return .cold,
            'w', 'W' => return .warm,
            else => return .none,
        }
        self.phase = 0;
        if (self.cursor < self.top) self.top = self.cursor;
        if (self.cursor >= self.top + SHOWN) self.top = self.cursor + 1 - SHOWN;
        return .none;
    }

    /// `fps_x10`: the running cart's frame rate, shown in the title instead of SHELF.
    pub fn draw(self: *const State, o: *osd.Osd, disks: []const shelf.Disk, loaded: ?usize, fps_x10: ?u32) void {
        var bar: [osd.COLS]u8 = undefined;
        const at = if (disks.len == 0) 0 else self.cursor + 1;
        const title = if (fps_x10) |f|
            std.fmt.bufPrint(&bar, " ZIGMACHINE {d:>3}.{d} FPS {d:>3}/{d:<3}>", .{ f / 10, f % 10, at, disks.len })
        else
            std.fmt.bufPrint(&bar, " ZIGMACHINE  SHELF   {d:>3}/{d:<3} >", .{ at, disks.len });
        o.line(0, title catch "", true);
        if (disks.len == 0) o.put(1, FIRST, "no .zmd disk on the card", false);
        var row: u32 = FIRST;
        var i = self.top;
        while (i < disks.len and row < FIRST + SHOWN) : ({
            i += 1;
            row += 1;
        }) self.drawRow(o, row, disks[i].title, i, loaded);
        o.line(RULE, "-" ** osd.COLS, false);
        if (disks.len > 0) details(o, disks[self.cursor]);
    }

    fn drawRow(self: *const State, o: *osd.Osd, row: u32, title: []const u8, i: usize, loaded: ?usize) void {
        var cell = [_]u8{' '} ** osd.COLS;
        var cut: [osd.COLS]u8 = undefined;
        if (loaded == i) cell[0] = '*';
        const name = if (i == self.cursor) text.marquee(title, NAME_W, self.phase) else text.fit(&cut, title, NAME_W);
        @memcpy(cell[1..][0..name.len], name);
        o.line(row, &cell, i == self.cursor);
    }
};

fn details(o: *osd.Osd, d: shelf.Disk) void {
    var line: [osd.COLS]u8 = undefined;
    var cut: [osd.COLS]u8 = undefined;
    const m = d.meta orelse {
        o.line(DETAIL, "no shelf.txt entry", false);
        o.line(DETAIL + 1, text.fit(&cut, d.file, osd.COLS), false);
        return;
    };
    const who = if (m.group.len > 0) m.group else "?";
    const left = std.fmt.bufPrint(&line, "{s} {s}", .{ text.fit(&cut, who, 20), m.year }) catch "";
    o.line(DETAIL, left, false);
    const room = osd.COLS -| (left.len + 1);
    const kind = if (room >= 2) text.fit(cut[20..], m.kind, @min(room, 12)) else "";
    if (kind.len > 0) o.put(@intCast(osd.COLS - kind.len), DETAIL, kind, false);
    var rows: [DESC_ROWS][]const u8 = undefined;
    var last: [osd.COLS]u8 = undefined;
    const n = text.wrap(m.desc, osd.COLS, &rows, &last);
    for (rows[0..n], 0..) |r, k| o.line(DETAIL + 1 + @as(u32, @intCast(k)), r, false);
}
