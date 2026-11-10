// --------------------------------------------------------------------------
// The old path's icon pixels (icon.zig Icon.draw): the mono icon with
// transparency (ink black, body white, outside clear so the desktop shows
// through the silhouette, swapped when selected), or a colour icon's image where
// the set's mask is set (its bytes index the pens at eng/looks.zig PEN_BASE).
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const iconset = @import("../iconset.zig");
const Rect = gui.Rect;
const Bitmap = iconset.Icon;

/// Where the bitmap's origin lands, and the window content it is clipped to (null: the screen).
pub const At = struct { x: i16, y: i16, bounds: ?Rect };

fn visible(at: At, sx: i16, sy: i16) bool {
    const b = at.bounds orelse return true; // clip to the window's content — never draw outside
    return sx >= b.x and sx < b.x + b.w and sy >= b.y and sy < b.y + b.h;
}

pub fn mono(g: *gui.Gui, at: At, ic: Bitmap, sel: bool) void {
    const ink_c: u8 = if (sel) gui.WHITE else gui.BLACK;
    const body_c: u8 = if (sel) gui.BLACK else gui.WHITE;
    const rowbytes: usize = (@as(usize, ic.w) + 7) / 8;
    var row: u16 = 0;
    while (row < ic.h) : (row += 1) {
        var col: u16 = 0;
        while (col < ic.w) : (col += 1) {
            const idx = row * rowbytes + col / 8;
            const sh: u3 = @intCast(7 - (col % 8));
            const sx = at.x + @as(i16, @intCast(col));
            const sy = at.y + @as(i16, @intCast(row));
            if (!visible(at, sx, sy)) continue;
            if ((ic.ink[idx] >> sh) & 1 != 0) {
                g.plot(sx, sy, ink_c);
            } else if ((ic.body[idx] >> sh) & 1 != 0) {
                g.plot(sx, sy, body_c); // enclosed body
            } // else: outside the silhouette -> transparent (desktop shows)
        }
    }
}

pub fn colour(g: *gui.Gui, at: At, ic: Bitmap, e: *const iconset.Entry) void {
    const img = e.col orelse return mono(g, at, ic, false);
    const rowbytes: usize = (@as(usize, ic.w) + 7) / 8;
    var row: u16 = 0;
    while (row < ic.h) : (row += 1) {
        var col: u16 = 0;
        while (col < ic.w) : (col += 1) {
            const sh: u3 = @intCast(7 - (col % 8));
            const p = @as(usize, row) * ic.w + col;
            const m = @as(usize, row) * rowbytes + col / 8;
            if (p >= img.len or m >= e.mask.len or (e.mask[m] >> sh) & 1 == 0) continue;
            const sx = at.x + @as(i16, @intCast(col));
            const sy = at.y + @as(i16, @intCast(row));
            if (visible(at, sx, sy)) g.plot(sx, sy, img[p]);
        }
    }
}
