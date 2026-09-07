// --------------------------------------------------------------------------
// Dragging a file onto the TRASH opens this modal GEM confirm box (the classic
// "DELETE FILE(S)" alert): the folder/file counts + OK / Cancel, on the grid.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");

pub const DeleteDlg = struct {
    active: bool = false,
    folders: u16 = 0,
    files: u16 = 0,

    const W: i16 = 240; // 30 cells
    const H: i16 = 112; // 14 cells
    pub const Result = enum { none, ok, cancel };

    pub fn open(self: *DeleteDlg, folders: u16, files: u16) void {
        self.* = .{ .active = true, .folders = folders, .files = files };
    }

    pub fn process(self: *DeleteDlg, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        const grid = gui.Grid{ .ox = dx, .oy = dy };

        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE);
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK);
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK);
        title(g, "DELETE FILE(S)", dx, grid.y(1) + 2, W);

        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        g.text(std.fmt.bufPrint(&b1, "Number of Folders: {d}", .{self.folders}) catch "", grid.x(3), grid.y(4), gui.BLACK, gui.WHITE);
        g.text(std.fmt.bufPrint(&b2, "Number of Files: {d}", .{self.files}) catch "", grid.x(3), grid.y(6), gui.BLACK, gui.WHITE);

        const bw: i16 = 64;
        const cw = W - grid.w(6);
        const by = grid.y(9);
        if (g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 0), .y = by, .w = bw, .h = 14 }, "OK", false, 3)) {
            self.active = false;
            return .ok;
        }
        if (g.buttonThick(.{ .x = gui.hspread(grid.x(3), cw, 2, bw, 1), .y = by, .w = bw, .h = 14 }, "Cancel", false, 2)) {
            self.active = false;
            return .cancel;
        }
        return .none;
    }
};

fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}
