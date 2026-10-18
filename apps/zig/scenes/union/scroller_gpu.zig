// --------------------------------------------------------------------------
// Union main -- the scrolltext's glyphs on CHISEL.
//
// scrolltext2's drawGlyph stored every pixel by the CPU (one blocking DDR write each
// on the board): per pixel the outline where it is non-zero, else the raster pixel
// where the font's interior bit is set, else nothing. Two blits do the same:
//   1. the raster, through a byte MASK (0xFF where the interior bit is set), by the
//      classic cookie-cut minterm D = (A & B) | (~A & D)  -- A the mask, B the raster;
//   2. the outline over it, colour 0 clear.
// The outline wins where it is non-zero in both versions; where it is 0 and the bit is
// set the raster shows; elsewhere the destination is untouched. The glyphs go into a
// 400 x 32 strip held in a scratch plane (a blit writes video memory only), and the wave
// copies column groups of it to the real plane.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cookie = @import("../cookie_gpu.zig");
const LogicalFB = zg.LogicalFB;

const GLYPH: usize = 32;
const SHEET_W: usize = 320; // font sheets: 10 glyphs across
const SHEET_ROWS: usize = 192; // 6 glyph rows
const COLS: usize = 10;
const ASCII_BASE: u8 = 32;
const RASTER_W: usize = 384;

var mask: []u8 = &.{}; // fontsin as bytes, 0xFF = interior
var chisel: zg.Blitter = .{};

/// Expand the 1bpp interior bits into the byte mask (once per cart load, on zg.mem).
pub fn init(font_in_bits: []const u8) void {
    chisel.init();
    if (mask.len != 0) return;
    mask = zg.mem.mustAlloc(u8, SHEET_W * SHEET_ROWS);
    for (mask, 0..) |*m, so| m.* = if ((font_in_bits[so >> 3] >> @intCast(7 - (so & 7))) & 1 == 1) 0xFF else 0;
}

fn isBlank(c: u8) bool {
    return c >= 92 or c == '/';
}

/// D = (A & B) | (~A & D) over a w x GLYPH rectangle of `dst` at (x, 0): A the mask sheet at
/// (ax, ay), B the raster at (bx, 0), both read from cart RAM.
fn maskedRaster(dst: *LogicalFB, x: usize, ax: usize, ay: usize, bx: usize, raster: []const u8, w: usize) void {
    cookie.masked(dst, x, 0, w, GLYPH, mask.ptr + ay * SHEET_W + ax, SHEET_W, raster.ptr + bx, RASTER_W);
}

/// Every visible slot of `fx` into the (cleared) strip plane `dst`: the same bytes as
/// scrolltext2's draw into a flat strip of dst.stride columns.
pub fn draw(fx: anytype, dst: *LogicalFB, font_out: []const u8, raster: []const u8) void {
    const width: i32 = @intCast(dst.fb_w);
    for (fx.slot_x, fx.slot_ch) |x, ch| {
        if (isBlank(ch)) continue;
        const idx: usize = ch - ASCII_BASE;
        const gx0: i32 = @max(0, -x);
        const gx1: i32 = @max(0, @min(@as(i32, GLYPH), width - x));
        if (gx1 <= gx0) continue;
        const dpx0: usize = @intCast(x + gx0);
        const n: usize = @intCast(gx1 - gx0);
        const sx: usize = (idx % COLS) * GLYPH + @as(usize, @intCast(gx0));
        const sy: usize = (idx / COLS) * GLYPH;
        const rx0 = dpx0 % RASTER_W;
        const first = @min(n, RASTER_W - rx0); // the raster wraps at its width
        maskedRaster(dst, dpx0, sx, sy, rx0, raster, first);
        if (first < n) maskedRaster(dst, dpx0 + first, sx + first, sy, 0, raster, n - first);
        chisel.blitImage(dst, @intCast(dpx0), 0, font_out, SHEET_W, @intCast(sx), @intCast(sy), @intCast(n), GLYPH, 0);
    }
}

/// One keyed copy of the strip's column group at `x` (w wide) down to `dy` on the real plane.
pub fn group(real: *LogicalFB, strip: *LogicalFB, x: u16, dy: i32, w: u16) void {
    chisel.bob(real, @intCast(x), @intCast(dy), strip, @intCast(x), 0, w, @intCast(GLYPH), 0);
}
