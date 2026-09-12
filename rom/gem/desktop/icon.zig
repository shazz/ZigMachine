// --------------------------------------------------------------------------
// Icon — a desktop icon as ONE object: its bitmap, position, label and the
// geometry/drawing/hit-testing that used to be scattered across placeIcon +
// clamp + snap + loose LABEL_* constants. Icon and label are a single unit, so
// they move, clamp and hit-test together (the label can no longer slide out
// from under the icon at the desktop border).
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const icons = @import("../gem_icons.zig");
const Rect = gui.Rect;

// GEM icon-label geometry: the name is drawn in the 6x6 system font in a
// fixed-width field so all labels line up regardless of length — 11 characters
// wide plus a 2px margin each side, centred under the icon.
const LABEL_FW: i16 = 6;
const LABEL_CHARS: i16 = 11;
const LABEL_MARGIN: i16 = 2;
pub const LABEL_W: i16 = LABEL_CHARS * LABEL_FW + 2 * LABEL_MARGIN;
// TOS sets an icon name down from the top of its box: TWO blank rows above the
// 6px glyph and one below. The box sits 1px under the icon so the whole unit
// still fits one CELL_H row of the desktop grid.
const LABEL_PAD_TOP: i16 = 2;
pub const LABEL_H: i16 = LABEL_PAD_TOP + 6 + 1;
// The desktop snap grid is a whole ICON CELL, not a fine pixel grid — so a
// dropped icon lands flush in a grid and only ever overlaps another exactly
// (GEM allows perfect overlap; it just never leaves icons half-covering).
// 72x40 is the authentic GEM icon cell (320x200): 70px label box + margin wide,
// tallest icon (~30) + 8px label tall.
pub const CELL_W: i16 = 72;
pub const CELL_H: i16 = 40;
// The desktop's own grid of those cells: column 0 at the left edge, row 0 just
// under the menu bar. An icon sits CENTRED in its cell with its bottom on the
// cell's baseline — the same placement a window gives its file icons — so the
// fixed-width label always lands inside the cell and lines up column to column.
pub const GRID_X0: i16 = 0;
pub const GRID_Y0: i16 = gui.MENU_H + 1;
const BASELINE: i16 = 30; // tallest icon; icon BOTTOMS align within a cell

// The tight bounding box of an icon's SILHOUETTE (ink | body), relative to the
// bitmap's origin. The ripped icon sheet left some bitmaps much wider than their
// art — TRASH is declared 51 px wide but draws about 25 — so anything that has
// to line an icon up or trace its outline (cell placement, the label, the drag
// ghost) must measure the art rather than trust w/h.
pub fn artBox(bmp: icons.Icon) Rect {
    const rowbytes: usize = (@as(usize, bmp.w) + 7) / 8;
    var x0: i16 = @intCast(bmp.w);
    var y0: i16 = @intCast(bmp.h);
    var x1: i16 = -1;
    var y1: i16 = -1;
    var row: u16 = 0;
    while (row < bmp.h) : (row += 1) {
        var col: u16 = 0;
        while (col < bmp.w) : (col += 1) {
            const idx = @as(usize, row) * rowbytes + col / 8;
            const sh: u3 = @intCast(7 - (col % 8));
            if (((bmp.ink[idx] | bmp.body[idx]) >> sh) & 1 == 0) continue;
            x0 = @min(x0, @as(i16, @intCast(col)));
            y0 = @min(y0, @as(i16, @intCast(row)));
            x1 = @max(x1, @as(i16, @intCast(col)));
            y1 = @max(y1, @as(i16, @intCast(row)));
        }
    }
    if (x1 < x0) return .{ .x = 0, .y = 0, .w = @intCast(bmp.w), .h = @intCast(bmp.h) }; // blank
    return .{ .x = x0, .y = y0, .w = x1 - x0 + 1, .h = y1 - y0 + 1 };
}

pub const Icon = struct {
    x: i16,
    y: i16,
    bmp: icons.Icon, // the 1bpp icon bitmap (ink + body silhouette)
    label: []const u8,
    is_app: bool = false,
    bounds: ?Rect = null, // clip/clamp region (a window's content); null = whole screen

    // The icon bitmap's bounding rect (not including the label). Generous on
    // purpose for hit-testing — the ART rect below is the tighter one.
    pub fn rect(self: *const Icon) Rect {
        return .{ .x = self.x, .y = self.y, .w = @intCast(self.bmp.w), .h = @intCast(self.bmp.h) };
    }

    // Where the icon's ART actually is on screen (see artBox).
    pub fn artRect(self: *const Icon) Rect {
        const a = artBox(self.bmp);
        return .{ .x = self.x + a.x, .y = self.y + a.y, .w = a.w, .h = a.h };
    }

    // The fixed-width label box, always centred under the icon. Inside a window
    // it is NOT clamped: sliding it along the content edge would drift the name
    // away from the icon it belongs to while scrolling (draw() drops the label
    // instead when the unit does not fit). A DESKTOP icon has no content rect, so
    // there it is still kept on-screen — the desktop cannot scroll.
    pub fn labelBox(self: *const Icon, screen_w: i16) Rect {
        const art = self.artRect();
        const cx = art.x + @divTrunc(art.w, 2); // centred on the ART, not the bitmap
        var bx = cx - @divTrunc(LABEL_W, 2);
        if (self.bounds == null) bx = @max(0, @min(bx, screen_w - LABEL_W));
        return .{ .x = bx, .y = art.y + art.h + 1, .w = LABEL_W, .h = LABEL_H };
    }

    // Pointer hit-test on the icon bitmap (uses the live Gui pointer).
    pub fn hit(self: *const Icon, g: *gui.Gui) bool {
        return g.hit(self.rect());
    }
    // Hit-test at explicit logical coords (native double-click from the loader).
    pub fn hitAt(self: *const Icon, x: i32, y: i32) bool {
        const r = self.rect();
        return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
    }

    // Keep the icon AND its (wider) label box on-screen — the label stays
    // centred over the icon at the border instead of clamping independently.
    pub fn clampInto(self: *Icon, screen_w: i16, screen_h: i16) void {
        self.place(self.cellCol(), self.cellRow(), screen_w, screen_h);
    }

    // Put the icon in desktop cell (col,row), clamped to the cells that fit. The
    // ART is what gets centred in the cell — a bitmap with padding around its art
    // (TRASH) would otherwise sit visibly off-centre next to a tight one.
    pub fn place(self: *Icon, want_col: i16, want_row: i16, screen_w: i16, screen_h: i16) void {
        const art = artBox(self.bmp);
        const cols = @max(1, @divTrunc(screen_w - GRID_X0, CELL_W));
        const rows = @max(1, @divTrunc(screen_h - GRID_Y0, CELL_H));
        const c = @max(0, @min(want_col, cols - 1));
        const r = @max(0, @min(want_row, rows - 1));
        self.x = GRID_X0 + c * CELL_W + @divTrunc(CELL_W - art.w, 2) - art.x;
        self.y = GRID_Y0 + r * CELL_H + BASELINE - art.y - art.h;
    }

    // Which cell the icon's ART centre currently falls in.
    pub fn cellCol(self: *const Icon) i16 {
        const a = self.artRect();
        return @divFloor(a.x + @divTrunc(a.w, 2) - GRID_X0, CELL_W);
    }
    pub fn cellRow(self: *const Icon) i16 {
        const a = self.artRect();
        return @divFloor(a.y + @divTrunc(a.h, 2) - GRID_Y0, CELL_H);
    }

    // Magnet-snap to the nearest grid cell on drop (icons align to a whole-cell
    // grid), then clamp back on-screen. GEM allows icons to overlap — dropping
    // two into the same cell stacks them exactly — it just never leaves an icon
    // half-covering another off the grid.
    pub fn snap(self: *Icon, screen_w: i16, screen_h: i16) void {
        self.place(self.cellCol(), self.cellRow(), screen_w, screen_h);
    }

    // Draw the icon with TRANSPARENCY (ink=black, body=white, outside=clear so
    // the desktop shows through the silhouette) and its caps label beneath on a
    // fixed-width box. When `sel`, the icon is inverse-video (GEM selection).
    pub fn draw(self: *const Icon, g: *gui.Gui, sel: bool) void {
        const ink_c: u8 = if (sel) gui.WHITE else gui.BLACK;
        const body_c: u8 = if (sel) gui.BLACK else gui.WHITE;
        const ic = self.bmp;
        const rowbytes: usize = (@as(usize, ic.w) + 7) / 8;
        var row: u16 = 0;
        while (row < ic.h) : (row += 1) {
            var col: u16 = 0;
            while (col < ic.w) : (col += 1) {
                const idx = row * rowbytes + col / 8;
                const sh: u3 = @intCast(7 - (col % 8));
                const sx = self.x + @as(i16, @intCast(col));
                const sy = self.y + @as(i16, @intCast(row));
                if (self.bounds) |b| { // clip to the window's content — never draw outside
                    if (sx < b.x or sx >= b.x + b.w or sy < b.y or sy >= b.y + b.h) continue;
                }
                if ((ic.ink[idx] >> sh) & 1 != 0) {
                    g.plot(sx, sy, ink_c);
                } else if ((ic.body[idx] >> sh) & 1 != 0) {
                    g.plot(sx, sy, body_c); // enclosed body
                } // else: outside the silhouette -> transparent (desktop shows)
            }
        }
        var box = self.labelBox(g.screen_w);
        var lo: i16 = 0;
        var hi: i16 = g.screen_w;
        if (self.bounds) |b| {
            // A label is a whole row, so a partly visible ROW is dropped; across
            // the window's edges it is CUT instead — the name loses its last (or
            // first) letters as it scrolls, rather than disappearing outright.
            if (box.y < b.y or box.y + box.h > b.y + b.h) return;
            lo = b.x;
            hi = b.x + b.w;
            const x0 = @max(box.x, lo);
            const x1 = @min(box.x + box.w, hi);
            if (x1 <= x0) return;
            box = .{ .x = x0, .y = box.y, .w = x1 - x0, .h = box.h };
        }
        const box_bg: u8 = if (sel) gui.BLACK else gui.WHITE;
        g.rect(box, box_bg);
        const full = self.labelBox(g.screen_w);
        const lw: i16 = @as(i16, @intCast(self.label.len)) * LABEL_FW;
        g.textSmallIn(self.label, full.x + @divTrunc(full.w - lw, 2), full.y + LABEL_PAD_TOP, if (sel) gui.WHITE else gui.BLACK, box_bg, lo, hi);
    }
};
