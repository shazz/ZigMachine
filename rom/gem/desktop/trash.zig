// --------------------------------------------------------------------------
// Dragging a file onto the TRASH opens this modal GEM confirm box (the classic
// "DELETE FILE(S)" alert): the folder/file counts + OK / Cancel, on the grid. The same box
// confirms a copy or a move; on C: it stays up after OK (`busy`) and counts down live while
// the shell works (fileop_ui.zig), its buttons dead, as TOS's does.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");

pub const DeleteDlg = struct {
    active: bool = false,
    folders: u16 = 0,
    files: u16 = 0,
    mode: Mode = .delete,
    busy: bool = false, // the operation runs: the counts are what is left, the buttons ignore clicks

    const W: i16 = 248; // 31 cells
    const H: i16 = 112; // 14 cells
    pub const Mode = enum { delete, copy, move };
    pub const Result = enum { none, ok, cancel };

    pub fn open(self: *DeleteDlg, folders: u16, files: u16) void {
        self.openMode(.delete, folders, files);
    }
    pub fn openCopy(self: *DeleteDlg, folders: u16, files: u16) void {
        self.openMode(.copy, folders, files);
    }
    pub fn openMode(self: *DeleteDlg, mode: Mode, folders: u16, files: u16) void {
        self.* = .{ .active = true, .folders = folders, .files = files, .mode = mode };
    }

    pub fn process(self: *DeleteDlg, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = g.screen.centreX(W);
        const dy = g.screen.centreY(H);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE);
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK);
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK);
        title(g, self.heading(), dx, grid.y(1) + 2, W);
        self.counts(g, grid);

        const bw: i16 = 64;
        const cw = W - grid.w(6);
        const by = grid.y(9);
        const ok = g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 0), .y = by, .w = bw, .h = 14 }, "OK", false, 3);
        const cancel = g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 1), .y = by, .w = bw, .h = 14 }, "Cancel", false, 2);
        if (self.busy) return .none;
        if (ok) {
            self.active = false;
            return .ok;
        }
        if (cancel) {
            self.active = false;
            return .cancel;
        }
        return .none;
    }

    fn heading(self: *const DeleteDlg) []const u8 {
        return switch (self.mode) {
            .copy => "COPY FOLDERS / ITEMS",
            .move => "MOVE FOLDERS / ITEMS",
            .delete => "DELETE FILE(S)",
        };
    }

    fn counts(self: *const DeleteDlg, g: *gui.Gui, grid: gui.Grid) void {
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        const s1 = switch (self.mode) {
            .copy => std.fmt.bufPrint(&b1, "Folders to Copy: {d}", .{self.folders}),
            .move => std.fmt.bufPrint(&b1, "Folders to Move: {d}", .{self.folders}),
            .delete => std.fmt.bufPrint(&b1, "Number of Folders: {d}", .{self.folders}),
        } catch "";
        const s2 = switch (self.mode) {
            .copy => std.fmt.bufPrint(&b2, "Items to Copy: {d}", .{self.files}),
            .move => std.fmt.bufPrint(&b2, "Items to Move: {d}", .{self.files}),
            .delete => std.fmt.bufPrint(&b2, "Number of Files: {d}", .{self.files}),
        } catch "";
        g.text(s1, grid.x(3), grid.y(4), gui.BLACK, gui.WHITE);
        g.text(s2, grid.x(3), grid.y(6), gui.BLACK, gui.WHITE);
    }
};

fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
