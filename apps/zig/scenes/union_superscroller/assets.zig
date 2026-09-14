// --------------------------------------------------------------------------
// TCB2 SUPERSCROLLER assets: the layout of superscroller.bin, the one image this
// screen depacks (tools/private_tools/union_superscroller_assets.py writes it
// from the remake's screens/superscroller/*.png).
//
//   back      320x200, colour 0..3   (back.png halved on its 2x grid)
//   overlay   320x200, 0 or 1..4     (overlay.png halved; 0 = transparent)
//   rasters   168, colour 0..41      (rasters.png: one colour a CANVAS row)
//   colours   RGB x (4 + 4 + 42 + 1): back, overlay, rasters, the font's ink
//   font      fonts2.png's 60 tiles as runs of ink on their even rows (spanfont)
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");

pub const W: usize = zg.WIDTH; // usize: TOTAL (2 * W * H) overflows u16
pub const H: usize = zg.HEIGHT;
pub const BACK_COLOURS = 4;
pub const OVER_COLOURS = 4;
pub const RASTER_COLOURS = 42;
pub const RASTER_ROWS = 168; // rasters.png 640x168
pub const GLYPHS = 60; // fonts2.png 3840x2280: initTile(384,380,32)
pub const FIRST_CHAR = 32;
pub const SAMPLED_ROWS = 187; // canvas rows 0, 2 .. 372 of the 374-row scroll canvas
const FONT_ROWS = 127; // unique rows, as the asset script reports them
const FONT_SPANS = 201;
const COLOURS = BACK_COLOURS + OVER_COLOURS + RASTER_COLOURS + 1;

pub const TOTAL = 2 * W * H + RASTER_ROWS + 3 * COLOURS +
    GLYPHS * SAMPLED_ROWS + 2 * (FONT_ROWS + 1) + 4 * FONT_SPANS;

pub const Images = struct {
    back: []const u8,
    overlay: []const u8,
    rasters: []const u8,
    back_rgb: [BACK_COLOURS]u32,
    over_rgb: [OVER_COLOURS + 1]u32, // [0] unused: 0 is transparent
    raster_rgb: [RASTER_COLOURS]u32,
    ink: u32,
    font: zg.spanfont.SpanFont,

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        std.debug.assert(buf.len == TOTAL);
        var at: usize = 0;
        var img: Images = undefined;
        img.back = take(buf, &at, W * H);
        img.overlay = take(buf, &at, W * H);
        img.rasters = take(buf, &at, RASTER_ROWS);
        const rgb = take(buf, &at, 3 * COLOURS);
        for (&img.back_rgb, 0..) |*c, i| c.* = colour(rgb, i);
        img.over_rgb[0] = 0;
        for (img.over_rgb[1..], 0..) |*c, i| c.* = colour(rgb, BACK_COLOURS + i);
        for (&img.raster_rgb, 0..) |*c, i| c.* = colour(rgb, BACK_COLOURS + OVER_COLOURS + i);
        img.ink = colour(rgb, COLOURS - 1);
        img.font = .{
            .row_ids = take(buf, &at, GLYPHS * SAMPLED_ROWS),
            .first = take(buf, &at, 2 * (FONT_ROWS + 1)),
            .spans = take(buf, &at, 4 * FONT_SPANS),
            .rows_per_glyph = SAMPLED_ROWS,
        };
        return img;
    }
};

fn take(buf: []const u8, at: *usize, n: usize) []const u8 {
    defer at.* += n;
    return buf[at.*..][0..n];
}

fn colour(rgb: []const u8, i: usize) u32 {
    return zg.linepal.rgb(rgb[3 * i], rgb[3 * i + 1], rgb[3 * i + 2]);
}
