// The OSD menu: the shelf of .zmd disks, a cursor, and what a key does. Pure
// state and drawing; app.zig turns its actions into loads and resets.
//
//   row 0       title bar (inverse)
//   rows 2..13  the disks, the cursor's row inverse
//   row 15      status: a hint, or the last error
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");

pub const Action = union(enum) { none, close, reset, load: usize };

const FIRST = 2;
const SHOWN = 12;

pub const Menu = struct {
    titles: []const []const u8,
    cursor: usize = 0,
    top: usize = 0,
    status: []const u8 = "ENTER load  R reset  F12 close",
    status_buf: [osd.COLS]u8 = undefined,

    /// A key event (map.KEY_*), down edges and repeats only.
    pub fn key(self: *Menu, ev: u32) Action {
        if (ev & map.KEY_DOWN == 0) return .none;
        const n = self.titles.len;
        switch (ev & map.KEY_CODE_MASK) {
            map.KEY_ARROW_UP => self.cursor -|= 1,
            map.KEY_ARROW_DOWN => if (self.cursor + 1 < n) {
                self.cursor += 1;
            },
            map.KEY_ESCAPE => return .close,
            map.KEY_ENTER, ' ' => if (n > 0) return .{ .load = self.cursor },
            'r', 'R' => return .reset,
            else => {},
        }
        self.scroll();
        return .none;
    }

    fn scroll(self: *Menu) void {
        if (self.cursor < self.top) self.top = self.cursor;
        if (self.cursor >= self.top + SHOWN) self.top = self.cursor + 1 - SHOWN;
    }

    pub fn setStatus(self: *Menu, comptime fmt: []const u8, args: anytype) void {
        self.status = std.fmt.bufPrint(&self.status_buf, fmt, args) catch self.status_buf[0..];
    }

    pub fn draw(self: *const Menu, o: *osd.Osd) void {
        o.clear();
        var bar: [osd.COLS]u8 = undefined;
        o.line(0, std.fmt.bufPrint(&bar, " ZIGMACHINE          {d:>3} disks", .{self.titles.len}) catch "", true);
        if (self.titles.len == 0) o.put(2, FIRST, "no .zmd disk on the card", false);
        var row: u32 = FIRST;
        var i = self.top;
        while (i < self.titles.len and row < FIRST + SHOWN) : ({
            i += 1;
            row += 1;
        }) {
            var cell: [osd.COLS]u8 = undefined;
            const text = std.fmt.bufPrint(&cell, " {s}", .{self.titles[i]}) catch cell[0..];
            o.line(row, text, i == self.cursor);
        }
        o.line(osd.ROWS - 1, self.status, false);
    }
};

fn rowText(o: *const osd.Osd, row: u32) [osd.COLS]u8 {
    var s: [osd.COLS]u8 = undefined;
    for (&s, 0..) |*c, i| c.* = @truncate(o.text[row * osd.COLS + i]);
    return s;
}

test "the cursor moves, scrolls and loads" {
    const titles = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n" };
    var m = Menu{ .titles = &titles };
    const down = map.KEY_ARROW_DOWN | map.KEY_DOWN;
    for (0..13) |_| try std.testing.expectEqual(Action.none, m.key(down));
    try std.testing.expectEqual(@as(usize, 13), m.cursor);
    try std.testing.expectEqual(@as(usize, 2), m.top);
    _ = m.key(down); // already on the last disk
    try std.testing.expectEqual(@as(usize, 13), m.cursor);
    try std.testing.expectEqual(Action{ .load = 13 }, m.key(map.KEY_ENTER | map.KEY_DOWN));
    try std.testing.expectEqual(Action.none, m.key(map.KEY_ENTER)); // a release does nothing
    try std.testing.expectEqual(Action.close, m.key(map.KEY_ESCAPE | map.KEY_DOWN));
    try std.testing.expectEqual(Action.reset, m.key('r' | map.KEY_DOWN));
}

test "the menu draws its disks with the cursor inverse" {
    const titles = [_][]const u8{ "Union Demo", "STNICCC 2000" };
    var m = Menu{ .titles = &titles, .cursor = 1 };
    var o = osd.Osd{};
    m.draw(&o);
    try std.testing.expectEqualStrings(" STNICCC 2000", rowText(&o, FIRST + 1)[0..13]);
    try std.testing.expect(o.text[(FIRST + 1) * osd.COLS] & map.OSD_INVERSE != 0);
    try std.testing.expect(o.text[FIRST * osd.COLS] & map.OSD_INVERSE == 0);
    try std.testing.expect(o.text[0] & map.OSD_INVERSE != 0); // the title bar
    m.setStatus("load failed: {s}", .{"NoBoardImage"});
    m.draw(&o);
    try std.testing.expectEqualStrings("load failed: NoBoardImage", rowText(&o, osd.ROWS - 1)[0..25]);
    var empty = Menu{ .titles = &.{} };
    try std.testing.expectEqual(Action.none, empty.key(map.KEY_ENTER | map.KEY_DOWN));
}
