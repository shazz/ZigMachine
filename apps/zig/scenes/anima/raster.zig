// --------------------------------------------------------------------------
// The REAL raster: one HBL handler on plane 0, at the overscan magic column.
//
// Per PHYSICAL line (0..279) it
//   1. flickers the resolution (flickerBorder) when the line is to be open:
//      in the top band that opens the top border from this row down, on a
//      visible line it opens both side borders for that line, in the bottom
//      band it opens the bottom border from this row down -- the overscan is
//      earned line by line, and the DARK/OPEN phases show it being earned;
//   2. writes palette entry 0 (the raster), the logo's body and the font's
//      body from three per-line tables, each only when the register does not
//      already hold the colour (3 colour registers a line, under the 16-entry
//      snoop queue; a line whose colours are unchanged costs no store).
//
// Entry 0 is the plane's background, so the raster runs edge to edge through
// every open border, as on an ST where the border is painted from the same
// register. bars.zig fills the tables once a frame.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const P = @import("palette.zig");
const T = @import("timeline.zig");

pub const ROWS: usize = zg.PHYSICAL_HEIGHT; // 280
pub const TOP: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40: first visible row
pub const BOTTOM: usize = TOP + zg.HEIGHT; // 240: first bottom-border row
const MID: usize = TOP + zg.HEIGHT / 2; // 140

pub var bg: [ROWS]u32 = @splat(0xFF00_0000);
pub var logo: [ROWS]u32 = @splat(0xFF00_0000);
pub var font: [ROWS]u32 = @splat(0xFF00_0000);
/// 1 = flicker on this line. Rebuilt only while the borders are opening.
pub var open: [ROWS]u8 = @splat(0);
var open_tick: u32 = 0xFFFF_FFFF;

pub fn install(fb: *zg.LogicalFB) void {
    fb.setOverscanBuffer();
    open = @splat(0);
    open_tick = 0xFFFF_FFFF;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    const r: usize = line; // an overscan plane's handler gets PHYSICAL lines
    if (r >= ROWS) return;
    if (open[r] != 0) fb.flickerBorder();
    const pal = fb.palette;
    if (pal[P.BG] != bg[r]) pal[P.BG] = bg[r];
    if (pal[P.LOGO_BODY] != logo[r]) pal[P.LOGO_BODY] = logo[r];
    if (pal[P.FONT_BODY] != font[r]) pal[P.FONT_BODY] = font[r];
}

/// Which lines flicker at tick t. Sides first, from the middle line out; then
/// the top border opens upward from the visible edge (a band row opens from the
/// first flicker down) and the bottom one rises from the screen's last line.
/// Once every line is open the table stays as it is: no stores.
pub fn openAt(t: u32) void {
    const key = @min(t, T.OPEN + T.SIDES_TICKS + T.BANDS_TICKS);
    if (key == open_tick) return;
    open_tick = key;
    const sides = T.ramp(t, T.OPEN, T.SIDES_TICKS) * (zg.HEIGHT / 2) / 256;
    const bands = T.ramp(t, T.OPEN + T.SIDES_TICKS, T.BANDS_TICKS) * TOP / 256;
    for (0..ROWS) |r| {
        const on = if (r < TOP)
            r + bands >= TOP
        else if (r < BOTTOM)
            t >= T.OPEN and (if (r < MID) MID - r else r - MID) <= sides
        else
            r + bands >= ROWS;
        const v: u8 = @intFromBool(on);
        if (open[r] != v) open[r] = v;
    }
}

/// True when line r flickers (the harness's view of what should be open).
pub fn isOpen(r: usize) bool {
    return r < ROWS and open[r] != 0;
}
