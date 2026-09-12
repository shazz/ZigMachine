// --------------------------------------------------------------------------
// Show Info... — the GEM information dialog (ref: real TOS "DISK INFORMATION").
// A disk shows drive/label/counts/bytes; a file or folder shows its name (in the
// 8.3 field that rename edits), kind and size. Laid out on the 8px cell grid with
// right-aligned labels + values, like TOS.
//
// The same dialog also serves File > New Folder (kind .new_folder): TOS uses one
// "NEW FOLDER" box with the identical Name: + 8.3 field, so it reuses the field,
// the keyboard editor and the OK/Cancel row rather than cloning them.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const NameField = @import("namefield.zig").NameField;
const stamp = @import("stamp.zig");

pub const Info = struct {
    active: bool = false,
    kind: Kind = .disk,
    name: NameField = .{}, // the editable 8.3 field (rename / new folder)
    folders: u16 = 0,
    items: u16 = 0,
    used: u32 = 0,
    avail: u32 = 0,
    size: u32 = 0,
    date: u32 = 0,
    enter: bool = false, // Enter key pressed -> apply (= OK)

    pub const Kind = enum { disk, file, folder, new_folder };

// Paint a NameField's 12 cells at (x,y); `edit` also draws the caret between the
// two cells it sits at.
fn drawField(g: *gui.Gui, f: *const NameField, x: i16, y: i16, edit: bool) void {
    var out: [12]u8 = undefined;
    g.text(f.cells(&out), x, y, gui.BLACK, gui.WHITE);
    if (edit) g.blit.fill(g.fb, x + f.caretCol() * 8, y - 1, 2, 9, gui.BLACK);
}
    pub const Result = enum { none, ok, cancel };

    // Edit the name field (file/folder rename, 8.3). cp: 8=Backspace, 13=Enter.
    pub fn key(self: *Info, cp: u32) void {
        if (self.kind == .disk) return; // disk-label rename not wired
        if (cp == 8) self.name.deleteBack() else if (cp == 13) self.enter = true else if (cp >= 32 and cp < 127) self.name.insert(@intCast(cp));
    }

    // Left/Right arrows walk the caret along the name (see Desktop.input).
    pub fn moveCaret(self: *Info, delta: i8) void {
        self.name.moveCaret(delta);
    }

    // The dialog must FIT the 320px low-res screen (the TOS reference shot this
    // was traced from is 640-wide, which made it 336 and hung off both edges).
    // Wide enough for the widest label + value; the one-field boxes are narrower.
    fn boxW(self: *const Info) i16 {
        return switch (self.kind) {
            .disk, .file => 312, // 39 cells — 4px margin each side at 320
            .folder, .new_folder => 208, // 26 cells — just the Name row
        };
    }
    const LABR: i16 = 19; // label column (right edge), in cells
    const MASK: usize = 12; // value field width in cells, like the 8.3 name box
    // The box is only as tall as the rows it actually shows.
    fn rows(self: *const Info) i16 {
        return switch (self.kind) {
            .disk => 15, // six dense rows + the OK button
            .file => 17, // three dense rows + the two Attributes buttons
            .folder, .new_folder => 8, // heading + Name + buttons
        };
    }

    // Consecutive text rows need more than the 8px cell pitch: the system font
    // fills all 8 rows, so cell-pitched lines touch. 10px gives one clear pixel
    // above and below each line while still reading as a block, not a list of
    // double-spaced rows.
    const DENSE: i16 = 10;
    fn boxH(self: *const Info) i16 {
        return self.rows() * 8;
    }
    fn btnRow(self: *const Info) i16 {
        return self.rows() - 3;
    }

    pub fn openDisk(self: *Info, folders: u16, items: u16, used: u32, avail: u32) void {
        self.* = .{ .active = true, .kind = .disk, .folders = folders, .items = items, .used = used, .avail = avail };
    }
    // File > New Folder: an empty editable 8.3 field; OK returns the typed name.
    pub fn openNewFolder(self: *Info) void {
        self.* = .{ .active = true, .kind = .new_folder };
    }
    pub fn openFile(self: *Info, name: []const u8, size: u32, date: u32, folder: bool) void {
        self.* = .{ .active = true, .kind = if (folder) .folder else .file, .size = size, .date = date };
        self.name.set(name);
    }

    pub fn process(self: *Info, g: *gui.Gui) Result {
        if (!self.active) return .none;
        if (self.enter) { // Enter key = OK (apply)
            self.enter = false;
            self.active = false;
            return .ok;
        }
        const H = self.boxH();
        const W = self.boxW();
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
            .new_folder => "NEW FOLDER",
        };
        g.text(heading, grid.x(3), grid.y(1) + 2, gui.BLACK, gui.WHITE);

        var buf: [24]u8 = undefined;
        if (self.kind == .disk) {
            // Six CONSECUTIVE rows, every value left-aligned in the same column
            // over the TOS underscore mask.
            const r = grid.y(4);
            self.labelAt(g, grid, "Drive Identifier:", r);
            self.valueAt(g, grid, "A:", r); // a drive letter is not an editable field
            self.labelAt(g, grid, "Disk Label:", r + DENSE);
            drawField(g, &NameField{}, grid.x(LABR) + 16, r + DENSE, false); // unnamed disk
            self.labelAt(g, grid, "Number of Folders:", r + 2 * DENSE);
            self.masked(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.folders}) catch "?", r + 2 * DENSE);
            self.labelAt(g, grid, "Number of Items:", r + 3 * DENSE);
            self.masked(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.items}) catch "?", r + 3 * DENSE);
            self.labelAt(g, grid, "Bytes Used:", r + 4 * DENSE);
            self.masked(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.used}) catch "?", r + 4 * DENSE);
            self.labelAt(g, grid, "Bytes Available:", r + 5 * DENSE);
            self.masked(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.avail}) catch "?", r + 5 * DENSE);
        } else {
            const r0 = grid.y(4); // first dense row
            if (self.kind == .new_folder) {
                // The NEW FOLDER box has one field, so TOS starts it under the
                // heading rather than in the right-aligned label column.
                g.text("Name:", grid.x(3), r0, gui.BLACK, gui.WHITE);
                drawField(g, &self.name, grid.x(3) + 6 * 8, r0, true);
                return self.buttons(g, grid, dx);
            }
            self.labelAt(g, grid, "Name:", r0);
            drawField(g, &self.name, grid.x(LABR) + 16, r0, true); // editable (rename / new name)
            if (self.kind == .file) {
                // TOS packs Name / Size / Last modified on CONSECUTIVE rows, all
                // three values left-aligned in the same value column.
                self.labelAt(g, grid, "Size in bytes:", r0 + DENSE);
                self.valueAt(g, grid, std.fmt.bufPrint(&buf, "{d}", .{self.size}) catch "?", r0 + DENSE);
                self.labelAt(g, grid, "Last modified:", r0 + 2 * DENSE);
                self.valueAt(g, grid, stamp.stamp(&buf, self.date), r0 + 2 * DENSE);
                self.labelAt(g, grid, "Attributes:", r0 + 4 * DENSE);
                // Read/Write (selected) + Read-Only — cosmetic (the disk is read-only).
                _ = g.button(.{ .x = grid.x(LABR) + 16, .y = r0 + 4 * DENSE, .w = 96, .h = 12 }, "Read/Write", true);
                _ = g.button(.{ .x = grid.x(LABR) + 16, .y = r0 + 4 * DENSE + 14, .w = 80, .h = 12 }, "Read-Only", false);
            }
        }

        return self.buttons(g, grid, dx);
    }

    // The exit-button row: OK (GEM default, 3px border) and, for everything but
    // the read-only disk box, Cancel at the far right.
    fn buttons(self: *Info, g: *gui.Gui, grid: gui.Grid, dx: i16) Result {
        const bw: i16 = 64;
        const y = grid.y(self.btnRow());
        const right = dx + self.boxW() - bw - grid.w(2);
        const okr = if (self.kind == .disk) right else grid.x(3);
        if (g.buttonThick(.{ .x = okr, .y = y, .w = bw, .h = 14 }, "OK", false, 3)) {
            self.active = false;
            return .ok;
        }
        if (self.kind != .disk and g.buttonThick(.{ .x = right, .y = y, .w = bw, .h = 14 }, "Cancel", false, 2)) {
            self.active = false;
            return .cancel;
        }
        return .none;
    }

    fn label(self: *Info, g: *gui.Gui, grid: gui.Grid, s: []const u8, row: i16) void {
        self.labelAt(g, grid, s, grid.y(row));
    }
    // Right-aligned label at an explicit y (the dense rows are not on the grid).
    fn labelAt(self: *Info, g: *gui.Gui, grid: gui.Grid, s: []const u8, y: i16) void {
        _ = self;
        g.text(s, grid.x(LABR) - @as(i16, @intCast(s.len)) * 8, y, gui.BLACK, gui.WHITE);
    }
    // A value left-aligned in the value column over the TOS underscore mask —
    // the same fixed-width field look as the editable 8.3 name box.
    fn masked(self: *Info, g: *gui.Gui, grid: gui.Grid, s: []const u8, y: i16) void {
        _ = self;
        var f: [MASK]u8 = [_]u8{'_'} ** MASK;
        const n = @min(s.len, MASK);
        @memcpy(f[0..n], s[0..n]);
        g.text(&f, grid.x(LABR) + 16, y, gui.BLACK, gui.WHITE);
    }
    // A left-aligned value at an explicit y, in the 8.3 name field's column.
    fn valueAt(self: *Info, g: *gui.Gui, grid: gui.Grid, s: []const u8, y: i16) void {
        _ = self;
        g.text(s, grid.x(LABR) + 16, y, gui.BLACK, gui.WHITE);
    }
};
