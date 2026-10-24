// --------------------------------------------------------------------------
// NOEXTRA's band: REAL rasters, the way RASTERS.PRG does them (Timer B at
// $CEE8, synced to the beam with `lsl.b d0,d0`):
//   one line   39 x move.w (a0)+,(a1)  of gradbar.pal into colour 0
//   146 lines  37 x move.w (a3)+,(a4)  of ramp.pal from ramp[(S[p1+r] + S[p2+2r]) / 2]
//   one line   the gradient bar again, then colours 0-3 black
// A move.w to a colour register takes 12 cycles, so colour 0 changes every
// 12 pixels across the WHOLE scanline, borders included; nothing of the band
// is in the framebuffer, only colour 0 (and the scroller's plane-0 ink).
//
// Here the band's rows hold a fixed ramp of palette INDICES, one per 12-px
// block, and this plane's HBL writes those entries for each line, as the
// 68000 wrote colour 0 across it. Measured on a Hatari capture (borders on,
// screen x 0 = capture x 48 = physical x 40): rainbow block k covers capture
// x [-3 + 12k, 9 + 12k), so physical x belongs to block (x + 11) / 12; the bar
// line's blocks start 4 px further left, block (x + 15) / 12. 400 physical
// columns show blocks 0..34 of either; the rest fell in the right border's
// blanking. A line is rewritten only where its ramp offset changed.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const T = @import("timeline.zig");

pub const PW = zg.PHYSICAL_WIDTH; // 400
pub const SX = zg.HORIZONTAL_BORDERS_WIDTH; // 40: ST screen x 0
/// ST line 0 (the capture's first row) sits on physical row PAD, so the
/// capture's last displayed row (272: the bottom border opened) is the last
/// physical row. The display itself starts on capture row 9 (FIRST_SHOWN):
/// with the screen bobbed up, the lines above stay black (measured, bob 52).
pub const PAD = 7;
pub const FIRST_SHOWN = PAD + 9;
pub const BAR_TOP = 77; // ST lines, bob 0 (the capture's rows)
pub const BAND_FIRST = 78;
pub const BAND_ROWS = 146;
pub const BAR_BOTTOM = BAND_FIRST + BAND_ROWS; // 224

pub const band_row: [PW]u8 = blocks(A.BAND, 11);
pub const bar_row: [PW]u8 = blocks(A.BAR, 15);

fn blocks(comptime first: u8, comptime lead: usize) [PW]u8 {
    var row: [PW]u8 = undefined;
    for (&row, 0..) |*p, x| p.* = first + (x + lead) / 12;
    return row;
}

const RAMP = blk: {
    var t: [A.ramp.len]u32 = undefined;
    for (&t, A.ramp) |*c, w| c.* = A.rgba(w);
    break :blk t;
};
const TOP_COLOURS = blk: {
    var t: [15]u32 = undefined;
    for (&t, 1..) |*c, i| c.* = A.rgba(A.pal_top[i]);
    break :blk t;
};
const BLACK = A.rgba(0);

/// What the HBL replays this frame: written by frame(), read per line.
var g_on = false;
var g_bob: u16 = 0;
var g_off: [BAND_ROWS]u8 = undefined;

/// The frame's ramp offsets and bob (main only).
pub fn frame(k: u32, bob: u16) void {
    const ph = T.bandPhase(k);
    for (&g_off, 0..) |*o, r| o.* = T.bandOffset(ph.p1, ph.p2, @intCast(r));
    g_bob = bob;
    g_on = true;
}

pub fn stop() void {
    g_on = false;
}

/// Flicker (every border open, every line) then this line's palette.
pub fn hbl(fb: *zg.LogicalFB, _: *zg.ZigOS, line: u16, _: u16) void {
    fb.flickerBorder();
    if (!g_on) return;
    if (line == 0) {
        // the bob lifts the top logo above the first line shown, where the ST showed nothing
        if (g_bob > 0) setRange(fb, A.TOP + 1, &([_]u32{BLACK} ** 15));
        return;
    }
    if (line == FIRST_SHOWN) setRange(fb, A.TOP + 1, &TOP_COLOURS);
    const r = @as(i32, line) + g_bob - (PAD + BAND_FIRST);
    if (r < 0 or r >= BAND_ROWS) return;
    const ur: usize = @intCast(r);
    if (ur > 0 and g_off[ur] == g_off[ur - 1]) return;
    setRange(fb, A.BAND, RAMP[g_off[ur]..][0..A.BAND_BLOCKS]);
}

/// Store only the entries that change: a raster coder never rewrites a register
/// that already holds the colour, and on the board every store is a bus write.
pub fn setRange(fb: *zg.LogicalFB, first: u8, colours: []const u32) void {
    for (colours, first..) |c, i| {
        if (fb.palette[i] != c) fb.palette[i] = c;
    }
}

/// The band's static pixels: the two bar lines and 146 lines of block indices.
pub fn drawStatic(blitter: *zg.Blitter, fb: *zg.LogicalFB) void {
    blitter.blitRow(fb, 0, PAD + BAR_TOP, &bar_row, 1, null);
    blitter.blitRow(fb, 0, PAD + BAND_FIRST, &band_row, BAND_ROWS, null);
    blitter.blitRow(fb, 0, PAD + BAR_BOTTOM, &bar_row, 1, null);
}
