// --------------------------------------------------------------------------
// Union main -- the scrolltext's strip and wave, in few CHISEL ops.
//
// Each op costs ~800 cycles of call before its pixels. The first CHISEL version
// took two a glyph (a cookie-cut raster -- a read-modify-write, ~7.7 clocks a
// pixel -- then the outline) and one per 3-px column group of the wave (134);
// the CPU, ~25 cycles a pixel for either, was worse. Now:
//   - CLASS (comptime, from fontsout + fontsin): per sheet pixel the outline
//     colour, RASTER (0xFF) where the interior bit is set under no outline, else 0;
//   - the strip's text rows take the raster whole (one plain copy of raster_w,
//     the 384-wide raster laid twice across 400 at compile time), then each glyph slot ONE copy of CLASS keyed on RASTER: outline and
//     0 land, the raster stays under RASTER -- scrolltext2's drawGlyph pixel
//     (the outline, else the raster where the bit is set, else 0); a blank slot
//     is a fill of 0. The 14 slots tile the strip (32 px apart, 448 px, the
//     leftmost at x in (-32, 0]), so no raster is left outside a glyph;
//   - the strip has PAD zero rows above and below, so a run of column groups
//     with the same wave offset is ONE copy of BAND rows that writes the band
//     whole (the text where the wave puts it, 0 elsewhere): ~25 runs, not 134
//     keyed groups over an erased band. The copy keys on RASTER, which no strip
//     pixel holds (p2.pal uses 0..252): a plain copy.
// The strip is plane 3, never enabled (a blit writes video memory only); the
// wave copies it to plane 1 -- no copy within one plane.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const LogicalFB = zg.LogicalFB;

pub const W: usize = 400; // the strip spans the plane
pub const GLYPH: usize = 32;
const SHEET_W: usize = 320; // 10 glyphs a row
const SHEET_ROWS: usize = 192; // 6 rows of glyphs
const COLS: usize = 10;
const ASCII_BASE: u8 = 32;
const RASTER_W: usize = 384;
pub const PAD: usize = 20; // the wave's swing: band row 0 meets text row -20 at most
const ROWS: usize = PAD + GLYPH + PAD + 1; // + the rounding row
const RASTER: u8 = 0xFF; // CLASS: keep the raster (fontsout uses 0..12)

const fontsout = @embedFile("../../assets/screens/union_main/fontsout.raw");
const fontsin_bits = @embedFile("../../assets/screens/union_main/fontsin.bits");

pub const CLASS: [SHEET_W * SHEET_ROWS]u8 = blk: {
    @setEvalBranchQuota(1_000_000);
    var t: [SHEET_W * SHEET_ROWS]u8 = undefined;
    for (&t, 0..) |*c, so| {
        const bit = (fontsin_bits[so >> 3] >> (7 - (so & 7))) & 1;
        if (fontsout[so] == RASTER) @compileError("fontsout uses 0xFF");
        c.* = if (fontsout[so] != 0) fontsout[so] else if (bit == 1) RASTER else 0;
    }
    break :blk t;
};

var chisel: zg.Blitter = .{};

/// The strip plane (plane 3, never enabled), its pad rows 0. Every entry: the host resets VRAM.
pub fn init(strip: *LogicalFB) void {
    chisel.init();
    strip.setScrollPlane(W, ROWS); // cleared to 0
}

fn isBlank(c: u8) bool { // scrolltext2's
    return c >= 92 or c == '/';
}

/// The raster across the strip's W columns, as its two copies laid it (columns 0..383, then
/// 0..15 again): one copy a frame instead of two.
const raster_w: [W * GLYPH]u8 = blk: {
    @setEvalBranchQuota(100_000);
    const raw = @embedFile("../../assets/screens/union_main/rasters.raw");
    var t: [W * GLYPH]u8 = undefined;
    for (0..GLYPH) |y| for (0..W) |x| {
        t[y * W + x] = raw[y * RASTER_W + x % RASTER_W];
    };
    break :blk t;
};

/// Every slot of `fx` into the strip's text rows, over the raster.
pub fn draw(strip: *LogicalFB, fx: anytype) void {
    const top: i16 = PAD;
    chisel.blitImage(strip, 0, top, &raster_w, W, 0, 0, W, GLYPH, null);
    for (fx.slot_x, fx.slot_ch) |x, ch| {
        const gx0: i32 = @max(0, -x);
        const gx1: i32 = @max(0, @min(@as(i32, GLYPH), @as(i32, W) - x));
        if (gx1 <= gx0) continue;
        const dx: i16 = @intCast(x + gx0);
        const n: u16 = @intCast(gx1 - gx0);
        if (isBlank(ch)) {
            chisel.fill(strip, dx, top, n, GLYPH, 0);
            continue;
        }
        const idx: usize = ch - ASCII_BASE;
        const sx: u16 = @intCast((idx % COLS) * GLYPH + @as(usize, @intCast(gx0)));
        const sy: u16 = @intCast((idx / COLS) * GLYPH);
        chisel.blitImage(strip, dx, top, &CLASS, SHEET_W, sx, sy, n, GLYPH, RASTER);
    }
}

/// The band rows y0 .. y0 + rows - 1 of `dst`: column group g (`col` px wide) shows text
/// row by - top[g] at band row by, 0 off the text. One copy a run of equal `top`.
pub fn wave(dst: *LogicalFB, strip: *LogicalFB, y0: i16, rows: u16, top: []const i32, col: usize) void {
    var g: usize = 0;
    while (g < top.len) {
        var e = g + 1;
        while (e < top.len and top[e] == top[g]) e += 1;
        const x0 = g * col;
        const x1 = @min(e * col, W);
        const sy: i16 = @intCast(@as(i32, PAD) - top[g]);
        chisel.bob(dst, @intCast(x0), y0, strip, @intCast(x0), sy, @intCast(x1 - x0), rows, RASTER);
        g = e;
    }
}
