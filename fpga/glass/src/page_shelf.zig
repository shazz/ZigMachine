// The OSD's home page: the shelf of carts on top, the selected one's details
// below (docs/FPGA_GLASS.md, "The menu").
//
//   row 0       title bar: page name (or the folder), cursor/count, '>' to the console page
//   rows 1..9   the rows (shelf_view.zig): the folders, then the carts by title; in a
//               folder, ".." then its carts. The cursor's row inverse; 'A'/'*' = loaded
//               (rows 1..14 sit right of the section strip: osd.BODY_COL, 30 wide)
//   row 10      a rule
//   row 11      group, year and machine of the selected cart
//   rows 12..14 its one-line description, word-wrapped
//   row 15      status: a hint, or the last error
const std = @import("std");
const map = @import("map.zig");
const osd = @import("osd.zig");
const text = @import("text.zig");
const shelf = @import("shelf.zig");
const sv = @import("shelf_view.zig");

pub const FIRST = 1;
pub const SHOWN = 9;
pub const RULE = 10;
pub const DETAIL = 11;
const DESC_ROWS = 3;
/// Content column 0 is the mark ('A' the disk in drive A, '*' the disk in the window), 1 a gap,
/// so every title starts at TITLE_COL whether its row is marked or not ("A REPS", not "AREPS").
pub const TITLE_COL = 2;
const NAME_W = osd.BODY_W - TITLE_COL;

pub const View = sv.View;

/// `open`: Enter on the cursor's row (a cart, a folder or ".."); `up`: back out of a folder.
pub const Key = enum { none, close, open, insert, eject, floppy_a, console, cold, warm, source, up };
/// The marks in column 0: 'A' the disk in drive A, '*' the disk in the window (when not in A).
pub const Marks = struct { loaded: ?usize = null, drive: ?usize = null, floppy: bool = false };

pub const State = struct {
    cursor: usize = 0, // a ROW of the view (shelf_view.zig), not a disk index
    top: usize = 0,
    phase: usize = 0, // the marquee's step, advanced by the app's tick
    folder_buf: [shelf.MAX_FOLDER]u8 = undefined,
    folder_len: usize = 0, // 0: the top of the shelf

    pub fn folder(self: *const State) []const u8 {
        return self.folder_buf[0..self.folder_len];
    }

    pub fn view(self: *const State, disks: []const shelf.Disk) sv.View {
        return .{ .disks = disks, .folder = self.folder() };
    }

    /// Into folder `name`, the cursor on its first cart (row 1; row 0 is "..").
    pub fn enter(self: *State, name: []const u8, disks: []const shelf.Disk) void {
        self.folder_len = @min(name.len, self.folder_buf.len);
        @memcpy(self.folder_buf[0..self.folder_len], name[0..self.folder_len]);
        self.show(@min(1, self.view(disks).len() -| 1));
    }

    /// Back to the top, the cursor on the folder just left. False at the top already.
    pub fn leave(self: *State, disks: []const shelf.Disk) bool {
        if (self.folder_len == 0) return false;
        var name: [shelf.MAX_FOLDER]u8 = undefined;
        const was = name[0..self.folder_len];
        @memcpy(was, self.folder());
        self.folder_len = 0;
        self.show(self.view(disks).rowOfFolder(was) orelse 0);
        return true;
    }

    /// The cursor on `row`, scrolled into sight.
    pub fn show(self: *State, row: usize) void {
        self.cursor = row;
        self.phase = 0;
        if (self.cursor < self.top) self.top = self.cursor;
        if (self.cursor >= self.top + SHOWN) self.top = self.cursor + 1 - SHOWN;
    }

    /// A key event (map.KEY_*), down edges and repeats only; `n` rows in the view.
    pub fn key(self: *State, code: u32, n: usize) Key {
        switch (code) {
            map.KEY_ARROW_UP => self.cursor -|= 1,
            map.KEY_ARROW_DOWN => if (self.cursor + 1 < n) {
                self.cursor += 1;
            },
            // A screenful at a time, stopping on the first/last row.
            map.KEY_PAGE_UP => self.cursor -|= SHOWN,
            map.KEY_PAGE_DOWN => if (n > 0) {
                self.cursor = @min(self.cursor + SHOWN, n - 1);
            },
            map.KEY_ARROW_RIGHT => return .console,
            map.KEY_ARROW_LEFT, map.KEY_BACKSPACE => return .up,
            map.KEY_ESCAPE => return .close,
            map.KEY_ENTER, ' ' => return if (n > 0) .open else .none,
            'i', 'I' => return if (n > 0) .insert else .none,
            'e', 'E' => return .eject,
            'd', 'D' => return .floppy_a, // the real floppy itself in drive A (docs/KOS_FAT.md)
            'r', 'R' => return .cold,
            'w', 'W' => return .warm,
            'f', 'F' => return .source,
            else => return .none,
        }
        self.show(self.cursor);
        return .none;
    }

    /// `fps_x10`: the running cart's frame rate, shown in the title instead of SHELF.
    pub fn draw(self: *const State, o: *osd.Osd, disks: []const shelf.Disk, marks: Marks, fps_x10: ?u32) void {
        const v = self.view(disks);
        const n = v.len();
        self.drawTitle(o, n, marks, fps_x10);
        if (disks.len == 0) o.bodyPut(0, FIRST, if (marks.floppy) "no .zmd disk on the floppy" else "no .zmd disk on the card", false);
        var row: u32 = FIRST;
        var r = self.top;
        while (r < n and row < FIRST + SHOWN) : ({
            r += 1;
            row += 1;
        }) self.drawRow(o, row, disks, v.at(r).?, r, marks);
        o.body(RULE, "-" ** osd.BODY_W, false);
        if (n > 0) details(o, disks, v.at(@min(self.cursor, n - 1)).?);
    }

    fn drawTitle(self: *const State, o: *osd.Osd, n: usize, marks: Marks, fps_x10: ?u32) void {
        var bar: [osd.COLS]u8 = undefined;
        var up: [shelf.MAX_FOLDER]u8 = undefined;
        const at = if (n == 0) 0 else self.cursor + 1;
        const where = if (marks.floppy) "FLOPPY" else "SHELF ";
        const title = if (fps_x10) |f|
            std.fmt.bufPrint(&bar, " ZIGMACHINE {d:>3}.{d} FPS {d:>3}/{d:<3}>", .{ f / 10, f % 10, at, n })
        else if (self.folder_len > 0)
            std.fmt.bufPrint(&bar, " ZIGMACHINE {s:<9} {d:>3}/{d:<3} >", .{ std.ascii.upperString(&up, self.folder()[0..@min(self.folder_len, 9)]), at, n })
        else
            std.fmt.bufPrint(&bar, " ZIGMACHINE  {s}  {d:>3}/{d:<3} >", .{ where, at, n });
        o.line(0, title catch "", true);
    }

    fn drawRow(self: *const State, o: *osd.Osd, row: u32, disks: []const shelf.Disk, what: sv.Row, r: usize, marks: Marks) void {
        var cell = [_]u8{' '} ** osd.BODY_W;
        var cut: [osd.COLS]u8 = undefined;
        var label: [osd.COLS]u8 = undefined;
        const name = switch (what) {
            .up => "..",
            .folder => |f| folderLabel(&label, f, sv.count(disks, f)),
            .disk => |i| if (r == self.cursor) text.marquee(disks[i].title, NAME_W, self.phase) else text.fit(&cut, disks[i].title, NAME_W),
        };
        cell[0] = mark(disks, what, marks);
        @memcpy(cell[TITLE_COL..][0..name.len], name);
        o.body(row, &cell, r == self.cursor);
    }
};

/// "DEMOS/" and its cart count, the count right-aligned.
fn folderLabel(buf: *[osd.COLS]u8, name: []const u8, n: usize) []const u8 {
    @memset(buf[0..NAME_W], ' ');
    const shown = @min(name.len, NAME_W - 6);
    _ = std.ascii.upperString(buf[0..shown], name[0..shown]);
    buf[shown] = '/';
    var num: [8]u8 = undefined;
    const digits = std.fmt.bufPrint(&num, "{d}", .{n}) catch "";
    @memcpy(buf[NAME_W - digits.len .. NAME_W], digits);
    return buf[0..NAME_W];
}

fn mark(disks: []const shelf.Disk, what: sv.Row, marks: Marks) u8 {
    return switch (what) {
        .up => ' ',
        .disk => |i| if (marks.drive == i) 'A' else if (marks.loaded == i) '*' else ' ',
        .folder => |f| if (sv.holds(disks, marks.drive, f)) 'A' else if (sv.holds(disks, marks.loaded, f)) '*' else ' ',
    };
}

fn details(o: *osd.Osd, disks: []const shelf.Disk, what: sv.Row) void {
    var line: [osd.COLS]u8 = undefined;
    switch (what) {
        .up => return o.body(DETAIL, "back to the shelf's folders", false),
        .folder => |f| return o.body(DETAIL, std.fmt.bufPrint(&line, "folder {s}: {d} carts", .{ f, sv.count(disks, f) }) catch "", false),
        .disk => |i| cartDetails(o, disks[i]),
    }
}

fn cartDetails(o: *osd.Osd, d: shelf.Disk) void {
    var line: [osd.COLS]u8 = undefined;
    var cut: [osd.COLS]u8 = undefined;
    const m = d.meta orelse {
        o.body(DETAIL, "no shelf.txt entry", false);
        o.body(DETAIL + 1, text.fit(&cut, d.file, osd.BODY_W), false);
        return;
    };
    const who = if (m.group.len > 0) m.group else "?";
    const left = std.fmt.bufPrint(&line, "{s} {s}", .{ text.fit(&cut, who, 18), m.year }) catch "";
    o.body(DETAIL, left, false);
    const room = osd.BODY_W -| (left.len + 1);
    const kind = if (room >= 2) text.fit(cut[20..], m.kind, @min(room, 12)) else "";
    if (kind.len > 0) o.bodyPut(@intCast(osd.BODY_W - kind.len), DETAIL, kind, false);
    var rows: [DESC_ROWS][]const u8 = undefined;
    var last: [osd.COLS]u8 = undefined;
    const n = text.wrap(m.desc, osd.BODY_W, &rows, &last);
    for (rows[0..n], 0..) |r, k| o.body(DETAIL + 1 + @as(u32, @intCast(k)), r, false);
}
