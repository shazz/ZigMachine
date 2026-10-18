// --------------------------------------------------------------------------
// VEX's per-row raster palette (raster.row_pal), rebuilt once a frame.
//
// Everything in a row depends only on its Timer-B split (71 of them, two
// scanlines each) and its colour band (5), so each RGBA is converted once per
// split or band and then copied down the rows. The first version converted
// every colour of every one of the 200 rows (1,200 conversions a frame, each
// three table lookups and shifts); this does 71 + 15 + 4, and the scroller's
// colour per split is a compile-time table.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const P = @import("planes.zig");
const pal = @import("palette.zig");
const cubes = @import("cubes.zig");
const raster = @import("raster.zig");

/// The big scroller's ink per split ($e90a reads it from the table at scrollcol.dat).
const SCROLL_RGBA: [raster.SPLITS]u32 = blk: {
    var t: [raster.SPLITS]u32 = undefined;
    for (&t, 0..) |*c, s| c.* = pal.rgba(A.be(A.scrollcol_b, s));
    break :blk t;
};

pub fn build(fade: *const pal.Fade, ramp: *const pal.Ramp, cb: *const cubes.Cubes, settle: u16) void {
    const top = pal.rgba(fade.live[pal.TOP_BG]);
    const flash = pal.rgba(fade.live[pal.SPLIT_BG]);
    const body = pal.rgba(fade.live[pal.BODY_BG]);
    const small_ink = pal.rgba(fade.live[pal.SMALL_INK]);
    const held_scroll = pal.rgba(fade.live[8]);

    var shades: [cubes.BAND_ROW.len][3]u32 = undefined;
    for (&shades, 0..) |*sh, b| {
        const c = cb.band(if (settle > 0) 0 else b, fade);
        for (c, 0..) |v, i| sh[i] = pal.rgba(v);
    }
    var ramp_rgba: [raster.SPLITS]u32 = undefined;
    for (&ramp_rgba, 0..) |*c, s| c.* = pal.rgba(ramp.colour(s));

    var b: usize = 0;
    for (&raster.row_pal, 0..) |*row, y| {
        const s = raster.splitOf(y);
        row[0] = if (y < raster.SPLIT_TOP or y >= P.SMALL_TOP) top else if (y < raster.SPLIT_TOP + 2 or y >= raster.SPLIT_END) flash else body;
        while (b + 1 < cubes.BAND_ROW.len and y >= cubes.BAND_ROW[b + 1]) b += 1;
        row[1] = shades[b][0];
        row[2] = shades[b][1];
        row[3] = shades[b][2];
        row[4] = if (y >= P.SMALL_TOP) small_ink else ramp_rgba[s];
        row[5] = if (settle > 0) held_scroll else SCROLL_RGBA[s];
    }
}
