// --------------------------------------------------------------------------
// Show Info... — the GEM information dialog (ref: real TOS "DISK INFORMATION").
// A disk shows drive/label/counts/bytes; a file or folder shows its name (in the
// 8.3 field that rename edits), kind and size. Laid out on the 8px cell grid with
// right-aligned labels + values, like TOS.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");

pub const Info = struct {
    active: bool = false,
    kind: Kind = .disk,
    name: [12]u8 = [_]u8{0} ** 12,
    nlen: u8 = 0,
    folders: u16 = 0,
    items: u16 = 0,
    used: u32 = 0,
    avail: u32 = 0,
    size: u32 = 0,
    date: u32 = 0,

    pub const Kind = enum { disk, file, folder };
    pub const Result = enum { none, ok };

    const W: i16 = 336; // 42 cells
    const H: i16 = 168; // 21 cells
    const LABR: i16 = 21; // label column (right edge), in cells
    const VALR: i16 = 39; // numeric value column (right edge), in cells

    pub fn openDisk(self: *Info, folders: u16, items: u16, used: u32, avail: u32) void {
        self.* = .{ .active = true, .kind = .disk, .folders = folders, .items = items, .used = used, .avail = avail };
    }
    pub fn openFile(self: *Info, name: []const u8, size: u32, date: u32, folder: bool) void {
        self.* = .{ .active = true, .kind = if (folder) .folder else .file, .size = size, .date = date };
        const n = @min(name.len, self.name.len);
        @memcpy(self.name[0..n], name[0..n]);
        self.nlen = @intCast(n);
    }

    pub fn process(self: *Info, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE);
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK);
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK);

        const heading = switch (self.kind) {
            .disk => "DISK INFORMATION",
            .file => "ITEM INFORMATION",
            .folder => "FOLDER INFORMATION",
        };
        g.text(heading, grid.x(3), grid.y(1) + 2, gui.BLACK, gui.WHITE);

        var buf: [24]u8 = undefined;
        if (self.kind == .disk) {
            self.label(g, grid, "Drive Identifier:", 4);
            g.text("A:", grid.x(LABR) + 16, grid.y(4), gui.BLACK, gui.WHITE);
            self.label(g, grid, "Disk Label:", 6);
            self.field83(g, grid, "", 0, 6); // empty (unnamed) disk label — editable later
            self.label(g, grid, "Number of Folders:", 8);
            self.num(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.folders}) catch "?", 8);
            self.label(g, grid, "Number of Items:", 10);
            self.num(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.items}) catch "?", 10);
            self.label(g, grid, "Bytes Used:", 12);
            self.num(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.used}) catch "?", 12);
            self.label(g, grid, "Bytes Available:", 14);
            self.num(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.avail}) catch "?", 14);
        } else {
            self.label(g, grid, "Name:", 4);
            self.field83(g, grid, self.name[0..self.nlen], self.nlen, 4);
            if (self.kind == .file) {
                self.label(g, grid, "Size in bytes:", 6);
                self.num(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.size}) catch "?", 6);
                self.label(g, grid, "Last modified:", 8);
                g.text(fmtDate(&buf, self.date), grid.x(LABR) + 16, grid.y(8), gui.BLACK, gui.WHITE);
                self.label(g, grid, "Attributes:", 11);
                // Read/Write (selected) + Read-Only — cosmetic (the disk is read-only).
                _ = g.button(.{ .x = grid.x(LABR) + 16, .y = grid.y(11), .w = 96, .h = 12 }, "Read/Write", true);
                _ = g.button(.{ .x = grid.x(LABR) + 16, .y = grid.y(13), .w = 80, .h = 12 }, "Read-Only", false);
            }
        }

        const bw: i16 = 64;
        const okr = if (self.kind == .disk) dx + W - bw - grid.w(2) else grid.x(3);
        if (g.buttonThick(.{ .x = okr, .y = grid.y(H_ROWS), .w = bw, .h = 14 }, "OK", false, 3)) {
            self.active = false;
            return .ok;
        }
        if (self.kind != .disk and g.buttonThick(.{ .x = dx + W - bw - grid.w(2), .y = grid.y(H_ROWS), .w = bw, .h = 14 }, "Cancel", false, 2)) {
            self.active = false;
            return .ok;
        }
        return .none;
    }

    const H_ROWS: i16 = 18; // button row

    fn fmtDate(buf: []u8, d: u32) []const u8 { // YYYYMMDD -> "MM/DD/YY"
        if (d == 0) return "--/--/--";
        return std.fmt.bufPrint(buf, "{d:0>2}/{d:0>2}/{d:0>2}", .{ (d / 100) % 100, d % 100, (d / 10000) % 100 }) catch "?";
    }

    fn label(self: *Info, g: *gui.Gui, grid: gui.Grid, s: []const u8, row: i16) void {
        _ = self;
        g.text(s, grid.x(LABR) - @as(i16, @intCast(s.len)) * 8, grid.y(row), gui.BLACK, gui.WHITE);
    }
    fn num(self: *Info, g: *gui.Gui, grid: gui.Grid, s: []const u8, row: i16) void {
        _ = self;
        g.text(s, grid.x(VALR) - @as(i16, @intCast(s.len)) * 8, grid.y(row), gui.BLACK, gui.WHITE);
    }
    // The 8.3 name/label field: NAME padded to 8 + '.' + EXT padded to 3, blanks as
    // underscores (the classic TOS editable field; typing edits it once wired).
    fn field83(self: *Info, g: *gui.Gui, grid: gui.Grid, name: []const u8, len: u8, row: i16) void {
        _ = self;
        var base: []const u8 = name[0..len];
        var ext: []const u8 = "";
        if (std.mem.lastIndexOfScalar(u8, name[0..len], '.')) |dot| {
            base = name[0..dot];
            ext = name[dot + 1 .. len];
        }
        var f: [12]u8 = undefined;
        var i: usize = 0;
        while (i < 8) : (i += 1) f[i] = if (i < base.len) base[i] else '_';
        f[8] = '.';
        i = 0;
        while (i < 3) : (i += 1) f[9 + i] = if (i < ext.len) ext[i] else '_';
        g.text(&f, grid.x(LABR) + 16, grid.y(row), gui.BLACK, gui.WHITE);
    }
};
