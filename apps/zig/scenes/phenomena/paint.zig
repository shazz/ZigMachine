// --------------------------------------------------------------------------
// Everything that is drawn once per phase, not per frame: the clears, the
// panel, the logo, the bar lines, the two text pages, and the photon (which
// only moves during its drop). Solid areas go through the blitter.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const G = @import("geom.zig");
const A = @import("assets.zig");

pub var blitter: zg.Blitter = .{};

/// Fill physical rows [y, y+h) x [x, x+w). The blitter clips a stride-800
/// plane to 200 rows, so each band is aimed through a view based at its row.
pub fn fill(fb: *zg.LogicalFB, x: usize, y: usize, w: usize, h: usize, c: u8) void {
    var row = y;
    while (row < y + h) {
        const n = @min(y + h - row, 200);
        var view = fb.*;
        view.fb = fb.fb + row * G.STRIDE;
        blitter.fill(&view, @intCast(x), 0, @intCast(w), @intCast(n), c);
        row += n;
    }
}

pub fn clear(fb: *zg.LogicalFB) void {
    fill(fb, 0, 0, G.STRIDE, G.ROWS, G.BLACK);
}

/// cnvMain.quad(0,130, 640,130, 640,430, 0,430, '#000111').
pub fn panel(fb: *zg.LogicalFB) void {
    fill(fb, G.CX, G.CY + G.PANEL_TOP, G.W, G.PANEL_END - G.PANEL_TOP, G.PANEL);
}

/// A bar's lines, the whole raster wide: the colour is the BAR register's.
pub fn barLines(fb: *zg.LogicalFB, first: usize) void {
    fill(fb, 0, G.CY + first, G.STRIDE, G.BAR_LINES, G.BAR);
}

pub fn logo(fb: *zg.LogicalFB) void {
    for (0..G.LOGO_LINES) |r| @memcpy(fb.fb[G.at(0, r)..][0..G.W], A.logo[r * G.W ..][0..G.W]);
}

// --- the text pages (makeIntroText) -----------------------------------------
const Line = struct { y: usize, text: []const u8 };
pub const PAGE1 = [_]Line{
    .{ .y = 18, .text = "   FOR HOT VHS" },
    .{ .y = 75, .text = "  AND SOFTWARE" },
    .{ .y = 133, .text = "SWAPPING, CONTACT" },
    .{ .y = 219, .text = " $THE PUNISHER$" },
    .{ .y = 291, .text = "      AT..." },
};
pub const PAGE2 = [_]Line{
    .{ .y = 78, .text = "    PHENOMENA" },
    .{ .y = 158, .text = "   SKALDEV. 69" },
    .{ .y = 238, .text = "  16142 BROMMA" },
    .{ .y = 334, .text = "     SWEDEN!" },
};

/// Glyphs at x = 48 + 32j, zoom 2: a font pixel is 2 columns, and font row k
/// is canvas rows y+2k, y+2k+1, i.e. content line y/2 + k.
pub fn page(fb: *zg.LogicalFB, lines: []const Line) void {
    for (lines) |l| {
        for (l.text, 0..) |ch, j| {
            const g = A.GLYPH_OF[ch & 127];
            for (0..A.GLYPH_H) |k| {
                const bits = A.FONT[g][k];
                const o = G.at(48 + 32 * j, l.y / 2 + k);
                for (0..A.GLYPH_W) |c| {
                    if ((bits >> @intCast(c)) & 1 == 0) continue;
                    fb.fb[o + 2 * c] = G.TEXT;
                    fb.fb[o + 2 * c + 1] = G.TEXT;
                }
            }
        }
    }
}

// --- the photon -------------------------------------------------------------
/// What lies under the photon on a content line: the panel, or black.
fn under(r: usize) u8 {
    return if (r >= G.PANEL_TOP and r < G.PANEL_END) G.PANEL else G.BLACK;
}

inline fn isBarLine(r: usize) bool {
    return (r >= G.BAR_TOP and r < G.BAR_TOP + G.BAR_LINES) or
        (r >= G.BAR_BOTTOM and r < G.BAR_BOTTOM + G.BAR_LINES);
}

/// Draw (or, with `erase`, remove) the photon whose first canvas row is
/// `start`. The bottom bar is drawn after it in screen.js, so bar lines keep
/// their BAR pixels.
pub fn photon(fb: *zg.LogicalFB, start: i32, erase: bool) void {
    for (0..G.H) |r| {
        const pr = G.canvasRow(r) - start;
        if (pr < 0) continue;
        if (pr >= G.PHOTON_H) break;
        if (isBarLine(r)) continue;
        const bg = under(r);
        const dst = fb.fb[G.at(G.PHOTON_X, r)..][0..G.PHOTON_W];
        const src = A.photon[@as(usize, @intCast(pr)) * G.PHOTON_W ..][0..G.PHOTON_W];
        for (dst, src) |*d, s| d.* = if (!erase and s != 0) G.PHOTON else bg;
    }
}
