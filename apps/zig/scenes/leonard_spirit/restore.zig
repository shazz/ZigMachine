// --------------------------------------------------------------------------
// The clear: the window the hardware shows this frame, copied back from the
// background tile in cart RAM by CHISEL, at the scrolled coordinates. The
// window (400x280) spans at most 3 x 3 pieces of the 320x200 tile, so at most
// 9 blits, each from cart RAM (never within the plane).
//
// Why not Leonard's precomputed clear list: the loop's lists fit (~430 KB for
// 360 frames) but the show's intro (still, borders opening, scroll ease-in) is
// not periodic and would need ~1 MB more of the 2 MB cart window; and with
// only the loop tabled the intro would be the heaviest phase anyway.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const lay = @import("layout.zig");

/// The plane seen from buffer row y down. CHISEL clips a destination of any
/// stride but 400 to 200 rows (machine/blitter.zig dstHeight), so an op below
/// row 200 of the 448-row buffer starts from a view based at its own row.
pub fn rowView(fb: *zg.LogicalFB, y: u32) zg.LogicalFB {
    var v = fb.*;
    v.fb = fb.fb + @as(usize, y) * fb.stride;
    return v;
}

/// Restore the window at buffer (x0, y0); `tile` is back.raw, (ox, oy) the
/// tile origin of layout.tileX/tileY.
pub fn window(bl: *zg.Blitter, fb: *zg.LogicalFB, tile: []const u8, x0: u32, y0: u32, ox: u32, oy: u32) void {
    var y = y0;
    while (y < y0 + lay.WIN_H) {
        const ty = lay.tileY(y, oy);
        const h = @min(lay.TILE_H - ty, y0 + lay.WIN_H - y);
        var x = x0;
        while (x < x0 + lay.WIN_W) {
            const tx = lay.tileX(x, ox);
            const w = @min(lay.TILE_W - tx, x0 + lay.WIN_W - x);
            var v = rowView(fb, y);
            bl.blitImage(&v, @intCast(x), 0, tile, lay.TILE_W, @intCast(tx), @intCast(ty), @intCast(w), @intCast(h), null);
            x += w;
        }
        y += h;
    }
}
