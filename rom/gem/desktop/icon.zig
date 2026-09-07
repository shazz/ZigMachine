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
const LABEL_W: i16 = LABEL_CHARS * LABEL_FW + 2 * LABEL_MARGIN;
const LABEL_H: i16 = 6 + 2; // 6x6 font + 1px top/bottom
// The desktop snap grid is a whole ICON CELL, not a fine pixel grid — so a
// dropped icon lands flush in a grid and only ever overlaps another exactly
// (GEM allows perfect overlap; it just never leaves icons half-covering).
// 72x40 is the authentic GEM icon cell (320x200): 70px label box + margin wide,
// tallest icon (~30) + 8px label tall.
pub const CELL_W: i16 = 72;
pub const CELL_H: i16 = 40;
const FOOT: i16 = 10; // label headroom kept below the icon when clamping

pub const Icon = struct {
    x: i16,
    y: i16,
    bmp: icons.Icon, // the 1bpp icon bitmap (ink + body silhouette)
    label: []const u8,
    is_app: bool = false,
    bounds: ?Rect = null, // clip/clamp region (a window's content); null = whole screen

    // The icon bitmap's bounding rect (not including the label).
    pub fn rect(self: *const Icon) Rect {
        return .{ .x = self.x, .y = self.y, .w = @intCast(self.bmp.w), .h = @intCast(self.bmp.h) };
    }

    // The fixed-width label box, centred under the icon and kept inside `bounds`
    // (a window's content rect) or, by default, on-screen.
    pub fn labelBox(self: *const Icon, screen_w: i16) Rect {
        const cx = self.x + @divTrunc(@as(i16, @intCast(self.bmp.w)), 2);
        const lo: i16 = if (self.bounds) |b| b.x else 0;
        const hi: i16 = if (self.bounds) |b| b.x + b.w - LABEL_W else screen_w - LABEL_W;
        const bx = @max(lo, @min(cx - @divTrunc(LABEL_W, 2), hi));
        return .{ .x = bx, .y = self.y + @as(i16, @intCast(self.bmp.h)) + 2, .w = LABEL_W, .h = LABEL_H };
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
        const iw: i16 = @intCast(self.bmp.w);
        const half_ic = @divTrunc(iw, 2);
        const half_lbl = @divTrunc(LABEL_W, 2);
        const low = @max(0, half_lbl - half_ic);
        const high = @min(screen_w - iw, screen_w - half_lbl - half_ic);
        self.x = @max(low, @min(self.x, high));
        self.y = @max(gui.MENU_H + 1, @min(self.y, screen_h - @as(i16, @intCast(self.bmp.h)) - FOOT));
    }

    // Magnet-snap to the nearest grid cell on drop (icons align to a whole-cell
    // grid), then clamp back on-screen. GEM allows icons to overlap — dropping
    // two into the same cell stacks them exactly — it just never leaves an icon
    // half-covering another off the grid.
    pub fn snap(self: *Icon, screen_w: i16, screen_h: i16) void {
        self.x = @divFloor(self.x + CELL_W / 2, CELL_W) * CELL_W;
        self.y = @divFloor(self.y + CELL_H / 2, CELL_H) * CELL_H;
        self.clampInto(screen_w, screen_h);
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
                const px: u16 = @intCast(sx);
                const py: u16 = @intCast(sy);
                if ((ic.ink[idx] >> sh) & 1 != 0) {
                    g.fb.setPixelValue(px, py, ink_c);
                } else if ((ic.body[idx] >> sh) & 1 != 0) {
                    g.fb.setPixelValue(px, py, body_c); // enclosed body
                } // else: outside the silhouette -> transparent (desktop shows)
            }
        }
        const box = self.labelBox(g.screen_w);
        const box_bg: u8 = if (sel) gui.BLACK else gui.WHITE;
        g.rect(box, box_bg);
        const lw: i16 = @as(i16, @intCast(self.label.len)) * LABEL_FW;
        g.textSmall(self.label, box.x + @divTrunc(box.w - lw, 2), box.y + 1, if (sel) gui.WHITE else gui.BLACK, box_bg);
    }
};
