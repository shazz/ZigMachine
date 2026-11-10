// --------------------------------------------------------------------------
// The ITEM SELECTOR's file list: the names, which one is picked, the scroll
// position, and how the little window draws them. Split out of filesel.zig.
//
// The rows are TOS's (measured on TOS 1.02, prototypes/gem_filesel_re/tos102):
// all nine slots are drawn every time, a file as NAME____.EXT with the dots in
// one column, an EMPTY slot as the bare `________.___` template. The text sits
// 32 px into the list, the highlight covers the 15-cell row object (a marker
// cell, a blank, the 12 cells, a blank) from 16 px in, and there are 8 px of
// white between the title bar and the first row and under the last. A folder
// (a name added with a trailing backslash) has TOS's diamond in the marker cell.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const glyphs = @import("../gem_glyphs.zig");
const listCells = @import("namefield.zig").listCells;
const Rect = gui.Rect;

pub const MAX_FILES: usize = 32;
pub const ROWS: usize = 9; // visible list rows
const ROW_H: i16 = 8;
const PAD: i16 = 8; // white above the first row and below the last
const ROW_X: i16 = 16; // the row object, from the list's left edge
const ROW_W: i16 = 15 * 8;
const TEXT_X: i16 = 32; // the 12 name cells
/// The list window's height: title bar, padding, nine rows, padding (99 px, as TOS).
pub const H: i16 = gui.TITLE_H + PAD + ROW_H * ROWS + PAD;

pub const List = struct {
    names: [MAX_FILES][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** MAX_FILES,
    nlen: [MAX_FILES]u8 = [_]u8{0} ** MAX_FILES,
    dir: [MAX_FILES]bool = [_]bool{false} ** MAX_FILES,
    n: usize = 0,
    sel: i16 = -1,
    top: usize = 0, // first visible row

    pub fn add(self: *List, name: []const u8) void {
        if (self.n >= MAX_FILES) return;
        const folder = name.len > 0 and name[name.len - 1] == '\\';
        self.dir[self.n] = folder;
        const k = @min(name.len - @intFromBool(folder), 16);
        @memcpy(self.names[self.n][0..k], name[0..k]);
        self.nlen[self.n] = @intCast(k);
        self.n += 1;
    }

    pub fn nameAt(self: *const List, i: usize) []const u8 {
        return self.names[i][0..self.nlen[i]];
    }

    pub fn isDir(self: *const List, i: usize) bool {
        return i < self.n and self.dir[i];
    }

    /// Draw the rows and scrollbar inside the list window `r`; returns the
    /// index of a file a click picked this frame, if any.
    pub fn draw(self: *List, g: *gui.Gui, r: Rect) ?usize {
        const picked = self.rows(g, r.x, r.y + gui.TITLE_H + PAD);
        const bar_h = r.h - gui.TITLE_H - 1;
        self.scrollbar(g, .{ .x = r.x + r.w - gui.SCROLL, .y = r.y + gui.TITLE_H, .w = gui.SCROLL, .h = bar_h });
        return picked;
    }

    fn rows(self: *List, g: *gui.Gui, x: i16, y: i16) ?usize {
        var picked: ?usize = null;
        var cells: [12]u8 = undefined;
        for (0..ROWS) |i| {
            const idx = self.top + i;
            const ry = y + @as(i16, @intCast(i)) * ROW_H;
            const row = Rect{ .x = x + ROW_X, .y = ry, .w = ROW_W, .h = ROW_H };
            if (idx >= self.n) { // an empty slot: the template, not clickable
                g.text(listCells("", &cells), x + TEXT_X, ry, gui.BLACK, gui.WHITE);
                continue;
            }
            const on = self.sel == @as(i16, @intCast(idx));
            const ink: u8 = if (on) gui.WHITE else gui.BLACK;
            const paper: u8 = if (on) gui.BLACK else gui.WHITE;
            if (on) g.rect(row, gui.BLACK);
            g.text(listCells(self.nameAt(idx), &cells), x + TEXT_X, ry, ink, paper);
            if (self.dir[idx]) diamond(g, x + ROW_X, ry, ink);
            if (g.edge and g.hit(row)) picked = idx;
        }
        return picked;
    }

    // Up/down step one row; the slider shows how much of the list is visible.
    fn scrollbar(self: *List, g: *gui.Gui, r: Rect) void {
        const up = Rect{ .x = r.x, .y = r.y, .w = r.w, .h = glyphs.GH };
        const dn = Rect{ .x = r.x, .y = r.y + r.h - glyphs.GH, .w = r.w, .h = glyphs.GH };
        const track = Rect{ .x = r.x, .y = up.y + up.h, .w = r.w, .h = r.h - 2 * glyphs.GH };
        const max = if (self.n > ROWS) self.n - ROWS else 0;
        if (max == 0) {
            g.rect(track, gui.WHITE);
        } else {
            g.hatch(track, gui.BLACK, gui.WHITE);
            const box_h = @max(glyphs.GH, @divTrunc(track.h * @as(i16, ROWS), @as(i16, @intCast(self.n))));
            const at = @divTrunc((track.h - box_h) * @as(i16, @intCast(self.top)), @as(i16, @intCast(max)));
            g.rect(.{ .x = track.x, .y = track.y + at, .w = track.w, .h = box_h }, gui.WHITE);
            g.frame(.{ .x = track.x, .y = track.y + at, .w = track.w, .h = box_h }, gui.BLACK);
        }
        g.frame(track, gui.BLACK);
        g.gadget(up.x, up.y, glyphs.UP, gui.BLACK, gui.WHITE);
        g.gadget(dn.x, dn.y, glyphs.DOWN, gui.BLACK, gui.WHITE);
        if (!g.edge) return;
        if (g.hit(up) and self.top > 0) self.top -= 1;
        if (g.hit(dn) and self.top < max) self.top += 1;
    }
};

// TOS's folder mark: a 7-pixel diamond in the row's marker cell.
fn diamond(g: *gui.Gui, x: i16, y: i16, ink: u8) void {
    const half = [_]i16{ 0, 1, 2, 3, 2, 1, 0 };
    for (half, 0..) |h, i| g.fill(x + 3 - h, y + @as(i16, @intCast(i)), @intCast(2 * h + 1), 1, ink);
}
