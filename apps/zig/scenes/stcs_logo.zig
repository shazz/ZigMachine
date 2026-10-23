// --------------------------------------------------------------------------
// STCS STARGOOSE — the logo, drawn into the scroller's plane (plane 1).
//
// It used to be plane 0 under plane 1: every enabled plane costs FRESCO ~1.09 Mc
// a frame on the board, so it now lives in plane 1 and plane 0 stays disabled.
// The composed picture is the same because:
//   - its colours 1..15 move to 17..31 (BASE + c) at compile time; plane 1's
//     scroller pixels are font colours 0..15 (stcs_scratch.COLORS), so none
//     collide. Entries 17..31 hold logo_pal (stcs.zig init), never touched again;
//   - its colour 0 stays 0: plane 1's entry 0 was transparent (showing plane 0's
//     entry 0, the raster); it now IS the raster, written per line by the
//     merged HBL (stcs_hbl.plane), transparent black down to line 66 as before;
//   - where the scroller's pixel is 0 the logo's shows: rows 0..68 are never
//     written by the scroller (drawn once); rows 69..72 are inside the band it
//     clears each frame, so they are restored first and the only copies that
//     reach them are cookie-cut with key 0 (stcs_strip.Copy.rows).
// --------------------------------------------------------------------------
const zg = @import("zigos");

const LogicalFB = zg.LogicalFB;
const Blitter = zg.Blitter;

const W: u16 = zg.WIDTH;
/// Plane view x of screen x 0: the view starts at the left border (stcs.zig).
const XO: i16 = zg.HORIZONTAL_BORDERS_WIDTH;
/// The highest line ZIG MODE's border groups reach (interlaced_mirror, group
/// 22: 88 - 22), so the side columns are restored from there.
pub const SIDE_TOP: i16 = 66;
/// The logo's colours (0..15) and where colours 1..15 land in plane 1.
pub const COLORS: usize = 16;
pub const BASE: u8 = 16;

const raw = @embedFile("../assets/screens/stcs/logo.raw");
/// The logo covers rows 0..ROWS-1 of the plane (its art is on rows 4..72).
pub const ROWS: u16 = raw.len / W;

/// The logo with colours 1..15 at 17..31, built at compile time from logo.raw.
pub const pixels: [raw.len]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var out: [raw.len]u8 = undefined;
    for (raw, 0..) |c, i| {
        if (c >= COLORS) @compileError("logo pixel >= 16");
        out[i] = if (c == 0) 0 else BASE + c;
    }
    break :blk out;
};

/// Once: the logo's rows above the scroller's band (they never change).
pub fn drawTop(c: *Blitter, fb: *LogicalFB, band_top: i16) void {
    c.blitImage(fb, XO, 0, &pixels, W, 0, 0, W, @intCast(band_top), null);
}

/// Each frame, before the strips: the band back to what is under the scroller,
/// the logo's last rows and then 0. `wide` (ZIG MODE's open sides): the side
/// columns too, from SIDE_TOP down (they hold no logo).
pub fn restoreBand(c: *Blitter, fb: *LogicalFB, band_top: i16, wide: bool) void {
    const top: u16 = @intCast(band_top);
    c.blitImage(fb, XO, band_top, &pixels, W, 0, top, W, ROWS - top, null);
    c.fill(fb, XO, @intCast(ROWS), W, zg.HEIGHT - ROWS, 0);
    if (!wide) return;
    const h: u16 = @intCast(zg.HEIGHT - SIDE_TOP);
    c.fill(fb, 0, SIDE_TOP, XO, h, 0);
    c.fill(fb, XO + W, SIDE_TOP, XO, h, 0);
}

/// The logo's pixel under screen (x, y) (0 outside it): what a star restores.
pub fn under(x: i16, y: i16) u8 {
    if (x < 0 or x >= W or y < 0 or y >= ROWS) return 0;
    return pixels[@as(usize, @intCast(y)) * W + @as(usize, @intCast(x))];
}
