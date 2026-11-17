//! A menu PANEL over the NFO (nfo.zig): the cart gives its lines as CP437 art (a frame of block
//! characters round its choices, drawn by the same cell, font, colours and drop shadow as the page)
//! and its choice keys. Space opens or closes it, Esc closes it, a choice key chooses while it is
//! open. Keys only QUEUE a change; Nfo.update() paints the panel into the window's rows of the
//! buffer (centred in the page) or restores those rows, beside the pan, never from a key handler
//! (a buffer edit outside the frame is what flashed the bar, ef0c182d). While it is open the page
//! does not scroll (the automatic scroll waits, the reader's scroll is dropped).
const std = @import("std");
const glyph = @import("nfo_glyph.zig");
const render = @import("nfo_render.zig");

pub const Error = render.Error || error{MenuTooBig};
pub const K_ESC: u32 = 0xE012; // docs/sealed-loader.js KEY_CODES

pub const Menu = struct {
    text: render.Text,
    keys: []const u8,
    cols: u32, // the widest line
    want: bool = false, // queued by key(): open (true) or closed
    shown: bool = false, // painted in the buffer now
    top: u32 = 0, // the buffer row the panel was painted at
    chosen: ?u8 = null,

    /// `bytes` is CP437 (kept: rows are rendered from it), `keys` the choice keys (ASCII, any case).
    /// A panel wider than 78 columns or taller than `page_rows` pixel rows is an error.
    pub fn init(bytes: []const u8, keys: []const u8, page_rows: u32) Error!Menu {
        const text = try render.Text.parse(bytes);
        var w: u32 = 0;
        for (0..text.n) |i| w = @max(w, @as(u32, @intCast(text.line(@intCast(i)).len)));
        if (w > render.cols - 2 or text.height() + 1 > page_rows or text.n == 0) return error.MenuTooBig;
        return .{ .text = text, .keys = keys, .cols = w };
    }

    /// A key: Space toggles, Esc closes, a choice key while open is returned (and kept in `chosen`).
    pub fn key(self: *Menu, cp: u32) ?u8 {
        if (cp == ' ') {
            self.want = !self.want;
            return null;
        }
        if (cp == K_ESC) {
            self.want = false;
            return null;
        }
        if (!self.want or cp > 0x7E) return null;
        const up = std.ascii.toUpper(@intCast(cp));
        for (self.keys) |k| if (std.ascii.toUpper(k) == up) {
            self.chosen = k;
            return k;
        };
        return null;
    }

    pub fn isOpen(self: *const Menu) bool {
        return self.want;
    }

    /// Pixel rows of the panel: its lines, and one more for the last line's shadow.
    pub fn rows(self: *const Menu) u32 {
        return self.text.height() + 1;
    }

    /// The first pixel column (centred, on a cell).
    pub fn x0(self: *const Menu) usize {
        return (render.cols - self.cols) / 2 * glyph.cell_w;
    }

    /// Called by Nfo.update(): paint or restore what key() queued. True while the panel is shown (the
    /// page holds still). `nfo` is the Nfo (anytype: no import cycle); before paint() nothing is drawn.
    pub fn sync(self: *Menu, nfo: anytype) bool {
        if (nfo.buf.len == 0) return self.want;
        if (self.want and !self.shown) {
            self.top = nfo.y + (nfo.page() - self.rows()) / 2;
            for (0..self.rows()) |k| self.renderRow(@intCast(k), nfo.buf[(self.top + k) * render.row_px ..][0..render.row_px]);
        } else if (!self.want and self.shown) {
            for (0..self.rows()) |k| nfo.paintRow(@intCast(self.top + k));
        }
        self.shown = self.want;
        return self.shown;
    }

    /// Panel row k into the 640-byte buffer row `dst`: its columns (and one more for the shadow) only.
    pub fn renderRow(self: *const Menu, k: u32, dst: []u8) void {
        var tmp: [render.row_px]u8 = undefined;
        render.renderRow(&self.text, k, &tmp);
        const w = (self.cols + 1) * glyph.cell_w;
        @memcpy(dst[self.x0()..][0..w], tmp[0..w]);
    }
};
