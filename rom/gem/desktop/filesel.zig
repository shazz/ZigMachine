// --------------------------------------------------------------------------
// ITEM SELECTOR — GEM's file-choosing dialog (fsel_input), the box every TOS
// program opens for "Load from disc". Geometry measured on the real one (TOS
// 1.02 in Hatari, prototypes/gem_filesel_re/tos102), relative to the box:
//
//   320 x 152, title at (24,8)
//   Directory:  at (8,24), the path over a 38-cell underscore rule
//   a window-framed list at (24,45), 176 x 99 (close box, hatched mover with
//   the mask centred, nine rows, scrollbar): filesel_list.zig
//   Selection:  at (208,..), the chosen name in an editable 8.3 field, which
//   ends 16 px inside the frame (it ran into the frame when the box was 304)
//   OK (default, 3 px border) and Cancel down the right, at x 221 / 222
//
// The box is the same 320 px in every resolution (the AES lays it out in 8 px
// character cells): in ST Replay's medium res it sits centred, at x 160.
// Built from the ROM's own parts — window chrome, arrow gadgets, slider, the 8.3
// NameField — rather than a second set of look-alikes, so it tracks the rest of
// the desktop. The caller supplies the names; this file does not touch a disk.
//
// The Directory: line is the path spec (filesel_path.zig), editable as TOS's:
// a click on it moves the caret there, Return or a click in the list re-reads
// it; a folder row (a name added with a trailing backslash) opens the folder,
// the list's close box goes to the parent. Each of those clears the list and
// answers `relist`: the caller reads the spec (fileSelPath) and adds the names
// again. A caller that adds no folders and never re-lists (ST Replay) sees the
// box it always saw.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const glyphs = @import("../gem_glyphs.zig");
const NameField = @import("namefield.zig").NameField;
const list_mod = @import("filesel_list.zig");
const fpath = @import("filesel_path.zig");
const Rect = gui.Rect;

pub const MAX_FILES = list_mod.MAX_FILES;
pub const ROWS = list_mod.ROWS;
const W: i16 = 320;
const H: i16 = 152;
const LIST_Y: i16 = 45; // the list window's top, from the box's
const DIR_CELLS: usize = fpath.CELLS; // the Directory: rule, as TOS's template
const TITLE_CELLS: usize = 16; // the list's mover shows the spec's end

pub const Result = enum { none, ok, cancel, relist };

pub const FileSel = struct {
    active: bool = false,
    path: fpath.PathField = .{}, // the Directory: line, the spec the list shows
    on_path: bool = false, // typing goes to the Directory: line (else the Selection)
    list: list_mod.List = .{},
    name: NameField = .{}, // the Selection: field

    pub fn open(self: *FileSel, start: []const u8) void {
        self.* = .{ .active = true };
        self.path.set(start);
    }

    pub fn spec(self: *const FileSel) []const u8 {
        return self.path.text();
    }

    pub fn add(self: *FileSel, name: []const u8) void {
        self.list.add(name);
    }

    pub fn chosen(self: *const FileSel) []const u8 {
        return self.name.text();
    }
    pub fn key(self: *FileSel, cp: u32) void {
        if (!self.active) return;
        if (self.on_path) {
            if (cp == 8) self.path.deleteBack() else if (cp >= 32 and cp < 127) self.path.insert(@intCast(cp));
            return;
        }
        if (cp == 8) self.name.deleteBack() else if (cp >= 32 and cp < 127) self.name.insert(@intCast(cp));
    }

    // The list emptied for the caller to fill from the (new) spec; the Selection keeps the caret.
    fn relist(self: *FileSel) Result {
        self.list = .{};
        self.on_path = false;
        return .relist;
    }

    pub fn process(self: *FileSel, g: *gui.Gui) Result {
        if (!self.active) return .none;
        const dx = g.screen.centreX(W);
        const dy = g.screen.centreY(H);
        const grid = gui.Grid{ .ox = dx, .oy = dy };
        box(g, .{ .x = dx, .y = dy, .w = W, .h = H });

        g.text("ITEM SELECTOR", grid.x(3), grid.y(1), gui.BLACK, gui.WHITE);
        g.text("Directory:", grid.x(1), grid.y(3), gui.BLACK, gui.WHITE);
        const dir_line = Rect{ .x = grid.x(1), .y = grid.y(4), .w = DIR_CELLS * 8, .h = 8 };
        self.drawPath(g, dir_line);

        const list = Rect{ .x = grid.x(3), .y = dy + LIST_Y, .w = 176, .h = list_mod.H };
        // An edited Directory: line is re-read by Return (not OK) or a click in the list (TOS).
        const reread = self.on_path and (g.enter or (g.edge and g.hit(list)));
        const moved = self.drawList(g, list, !reread);

        const fx = list.x + list.w + 8; // 208 into the box
        g.text("Selection:", fx, grid.y(6), gui.BLACK, gui.WHITE);
        drawField(g, &self.name, fx, grid.y(8), !self.on_path);
        if (reread or moved) return self.relist();
        if (g.edge and g.hit(dir_line)) self.on_path = true;
        if (g.edge and g.hit(.{ .x = fx, .y = grid.y(8), .w = 12 * 8, .h = 8 })) self.on_path = false;

        if (g.buttonThick(.{ .x = dx + 221, .y = dy + 101, .w = 86, .h = 14 }, "OK", false, 3)) return self.close(.ok);
        if (g.buttonThick(.{ .x = dx + 222, .y = dy + 118, .w = 84, .h = 12 }, "Cancel", false, 2)) return self.close(.cancel);
        return .none;
    }

    fn close(self: *FileSel, r: Result) Result {
        self.active = false;
        return r;
    }

    // The spec over the rule; the caret only while the line is being edited.
    fn drawPath(self: *FileSel, g: *gui.Gui, r: Rect) void {
        const t = fpath.shown(self.path.text());
        rule(g, r.x, r.y, DIR_CELLS, t);
        if (!self.on_path) return;
        const off = self.path.len - t.len; // the cells scrolled off the left
        const col: i16 = @intCast(@min(self.path.caret -| off, DIR_CELLS));
        g.fill(r.x + col * 8, r.y - 1, 2, 9, gui.BLACK);
    }

    // The list is a little WINDOW: close box, hatched mover with the spec centred
    // on it, then the rows and the scrollbar (filesel_list.zig). True when a
    // folder was opened or the close box went to the parent: the spec moved.
    fn drawList(self: *FileSel, g: *gui.Gui, r: Rect, clicks: bool) bool {
        g.rect(r, gui.WHITE);
        g.frame(r, gui.BLACK);
        const bar = Rect{ .x = r.x + glyphs.GW, .y = r.y + 1, .w = r.w - glyphs.GW - 1, .h = gui.TITLE_H - 2 };
        g.hatch(bar, gui.BLACK, gui.WHITE);
        g.gadget(r.x, r.y, glyphs.CLOSE, gui.BLACK, gui.WHITE);
        const full = self.path.text();
        const t = if (full.len > TITLE_CELLS) full[full.len - TITLE_CELLS ..] else full;
        const tw: i16 = @as(i16, @intCast(t.len)) * 8;
        const tx = r.x + @divTrunc(r.w - tw, 2);
        g.rect(.{ .x = tx - 8, .y = bar.y, .w = tw + 16, .h = bar.h }, gui.WHITE);
        g.text(t, tx, r.y + 2, gui.BLACK, gui.WHITE);
        g.fill(r.x, r.y + gui.TITLE_H - 1, @intCast(r.w), 1, gui.BLACK);
        if (!clicks) {
            _ = self.list.draw(g, r);
            return false;
        }
        if (g.edge and g.hit(.{ .x = r.x, .y = r.y, .w = glyphs.GW, .h = gui.TITLE_H }) and self.path.up()) return true;
        if (self.list.draw(g, r)) |idx| {
            if (self.list.isDir(idx)) return self.path.enter(self.list.nameAt(idx));
            self.list.sel = @intCast(idx); // a file fills the Selection field
            self.name.set(self.list.nameAt(idx));
            self.on_path = false;
        }
        return false;
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

fn drawField(g: *gui.Gui, f: *const NameField, x: i16, y: i16, caret: bool) void {
    var out: [12]u8 = undefined;
    g.text(f.cells(&out), x, y, gui.BLACK, gui.WHITE);
    if (caret) g.fill(x + f.caretCol() * 8, y - 1, 2, 9, gui.BLACK);
}
