// --------------------------------------------------------------------------
// An icon's ART box: the tight bounds of what it draws, measured from the bitmap
// (a ripped bitmap can be much wider than its art), remembered per bitmap.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const icons = @import("../iconset.zig");
const Rect = gui.Rect;

// The tight bounding box of an icon's SILHOUETTE (ink | body), relative to the
// bitmap's origin. The ripped icon sheet left some bitmaps much wider than their
// art — TRASH is declared 51 px wide but draws about 25 — so anything that has
// to line an icon up or trace its outline (cell placement, the label, the drag
// ghost) must measure the art rather than trust w/h.
pub fn artBox(bmp: icons.Icon) Rect {
    // Asked for every icon several times a frame (layout, hit-tests, labels): the scan of a
    // 32x30 bitmap cost ~10k instructions each time. The bitmaps are constants: remember them.
    const key = @intFromPtr(bmp.ink.ptr);
    for (art_seen[0..art_n]) |e| if (e.key == key) return e.box;
    const box = scanArt(bmp);
    art_seen[art_n % art_seen.len] = .{ .key = key, .box = box };
    art_n = @min(art_n + 1, art_seen.len);
    return box;
}
var art_seen: [12]struct { key: usize, box: Rect } = undefined;
var art_n: usize = 0;

fn scanArt(bmp: icons.Icon) Rect {
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
