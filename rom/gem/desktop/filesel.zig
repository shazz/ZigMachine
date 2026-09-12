// --------------------------------------------------------------------------
// ITEM SELECTOR — GEM's file-choosing dialog (fsel_input), the box every TOS
// program opens for "Load from disc". Geometry measured off a screenshot of the
// real one, at its native 320x152:
//
//   Directory:  a path over an underscore rule
//   a window-framed list (close box, hatched mover, centred title, scrollbar)
//   Selection:  the chosen name in an editable 8.3 field
//   OK (default, thick border) and Cancel down the right
//
// Built from the ROM's own parts — window chrome, arrow gadgets, slider, the 8.3
// NameField — rather than a second set of look-alikes, so it tracks the rest of
// the desktop. The caller supplies the names; this file does not touch a disk.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const glyphs = @import("../gem_glyphs.zig");
const NameField = @import("namefield.zig").NameField;
const Rect = gui.Rect;

pub const MAX_FILES: usize = 32;
pub const ROWS: usize = 9; // visible list rows
const W: i16 = 304;
const H: i16 = 152;
const ROW_H: i16 = 8;

pub const Result = enum { none, ok, cancel };

pub const FileSel = struct {
    active: bool = false,
    title: [16]u8 = [_]u8{0} ** 16, // the mask shown in the list's title bar
    tlen: u8 = 0,
    names: [MAX_FILES][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** MAX_FILES,
    nlen: [MAX_FILES]u8 = [_]u8{0} ** MAX_FILES,
    n: usize = 0,
    sel: i16 = -1,
    top: usize = 0, // first visible row
    name: NameField = .{}, // the Selection: field

    pub fn open(self: *FileSel, mask: []const u8) void {
        self.* = .{ .active = true };
        const t = @min(mask.len, self.title.len);
        @memcpy(self.title[0..t], mask[0..t]);
        self.tlen = @intCast(t);
    }

    pub fn add(self: *FileSel, name: []const u8) void {
        if (self.n >= MAX_FILES) return;
        const k = @min(name.len, 16);
        @memcpy(self.names[self.n][0..k], name[0..k]);
        self.nlen[self.n] = @intCast(k);
        self.n += 1;
    }

    pub fn chosen(self: *const FileSel) []const u8 {
        return self.name.text();
    }
    pub fn key(self: *FileSel, cp: u32) void {
        if (!self.active) return;
        if (cp == 8) self.name.deleteBack() else if (cp >= 32 and cp < 127) self.name.insert(@intCast(cp));
    }

    fn nameAt(self: *const FileSel, i: usize) []const u8 {
        return self.names[i][0..self.nlen[i]];
    }

    pub fn process(self: *FileSel, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        const grid = gui.Grid{ .ox = dx, .oy = dy };
        box(g, .{ .x = dx, .y = dy, .w = W, .h = H });

        g.text("ITEM SELECTOR", grid.x(2), grid.y(1), gui.BLACK, gui.WHITE);
        g.text("Directory:", grid.x(1), grid.y(3), gui.BLACK, gui.WHITE);
        rule(g, grid.x(1), grid.y(4), 36, self.title[0..self.tlen]);

        const list = Rect{ .x = grid.x(3), .y = grid.y(6), .w = 176, .h = ROW_H * ROWS + gui.TITLE_H + 2 };
        self.drawList(g, list);

        g.text("Selection:", list.x + list.w + 8, grid.y(6), gui.BLACK, gui.WHITE);
        drawField(g, &self.name, list.x + list.w + 8, grid.y(8));

        const bw: i16 = 80;
        const bx = list.x + list.w + 8;
        if (g.buttonThick(.{ .x = bx, .y = grid.y(12), .w = bw, .h = 14 }, "OK", false, 3)) return self.close(.ok);
        if (g.buttonThick(.{ .x = bx, .y = grid.y(14), .w = bw, .h = 14 }, "Cancel", false, 2)) return self.close(.cancel);
        return .none;
    }

    fn close(self: *FileSel, r: Result) Result {
        self.active = false;
        return r;
    }

    // The list is a little WINDOW: close box, hatched mover with the mask centred
    // on it, the rows, and a scrollbar down the right.
    fn drawList(self: *FileSel, g: *gui.Gui, r: Rect) void {
        g.rect(r, gui.WHITE);
        g.frame(r, gui.BLACK);
        const bar = Rect{ .x = r.x + glyphs.GW, .y = r.y + 1, .w = r.w - glyphs.GW - 1, .h = gui.TITLE_H - 2 };
        g.hatch(bar, gui.BLACK, gui.WHITE);
        g.gadget(r.x, r.y, glyphs.CLOSE, gui.BLACK, gui.WHITE);
        const t = self.title[0..self.tlen];
        const tw: i16 = @as(i16, @intCast(t.len)) * 8;
        const tx = r.x + @divTrunc(r.w - tw, 2);
        g.rect(.{ .x = tx - 8, .y = bar.y, .w = tw + 16, .h = bar.h }, gui.WHITE);
        g.text(t, tx, r.y + 2, gui.BLACK, gui.WHITE);
        g.blit.fill(g.fb, r.x, r.y + gui.TITLE_H - 1, @intCast(r.w), 1, gui.BLACK);

        const inner = Rect{ .x = r.x + 1, .y = r.y + gui.TITLE_H, .w = r.w - 2 - gui.SCROLL, .h = ROW_H * ROWS };
        self.rows(g, inner);
        self.scrollbar(g, .{ .x = r.x + r.w - gui.SCROLL, .y = inner.y, .w = gui.SCROLL, .h = inner.h });
    }

    fn rows(self: *FileSel, g: *gui.Gui, c: Rect) void {
        var i: usize = 0;
        while (i < ROWS and self.top + i < self.n) : (i += 1) {
            const idx = self.top + i;
            const row = Rect{ .x = c.x, .y = c.y + @as(i16, @intCast(i)) * ROW_H, .w = c.w, .h = ROW_H };
            const on = self.sel == @as(i16, @intCast(idx));
            if (on) g.rect(row, gui.BLACK);
            g.text(self.nameAt(idx), row.x + 8, row.y, if (on) gui.WHITE else gui.BLACK, if (on) gui.BLACK else gui.WHITE);
            if (g.edge and g.hit(row)) { // picking a row fills the Selection field
                self.sel = @intCast(idx);
                self.name.set(self.nameAt(idx));
            }
        }
    }

    // Up/down step one row; the slider shows how much of the list is visible.
    fn scrollbar(self: *FileSel, g: *gui.Gui, r: Rect) void {
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

fn box(g: *gui.Gui, r: Rect) void {
    g.rect(r, gui.WHITE);
    g.frame(r, gui.BLACK);
    g.frame(.{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 }, gui.BLACK);
}

// A value written over the TOS underscore rule that marks an editable field.
fn rule(g: *gui.Gui, x: i16, y: i16, cells: usize, text: []const u8) void {
    var bar: [40]u8 = [_]u8{'_'} ** 40;
    const n = @min(cells, bar.len);
    g.text(bar[0..n], x, y, gui.BLACK, gui.WHITE);
    if (text.len > 0) g.text(text, x, y, gui.BLACK, gui.WHITE);
}

fn drawField(g: *gui.Gui, f: *const NameField, x: i16, y: i16) void {
    var out: [12]u8 = undefined;
    g.text(f.cells(&out), x, y, gui.BLACK, gui.WHITE);
    g.blit.fill(g.fb, x + f.caretCol() * 8, y - 1, 2, 9, gui.BLACK);
}
