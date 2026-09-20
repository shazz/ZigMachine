// --------------------------------------------------------------------------
// VEX's two raster handlers and the per-row palette they read.
//
// $e90a's Timer-B chain: 71 splits of two scanlines over rows 47..188, writing
// the six entries the layers are coloured from.  vex.zig fills row_pal once a
// frame; these two only install it.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;

const P = @import("planes.zig");

pub const SPLITS: usize = 71; // $30dee ships as $47
pub const SPLIT_TOP: usize = 47; // the two lines $e90a paints before the chain
pub const SPLIT_END: usize = SPLIT_TOP + 2 * SPLITS; // 189

pub var row_pal: [P.ROWS][P.DRIVEN]u32 = undefined;

/// On a real ST the BORDER *is* colour 0, and $e90a rewrites colour 0 per
/// scanline — so the border tracks the bands rather than sitting black: navy
/// beside the logo and the bottom scroller, near-black beside the panel. The
/// 320x200 plane is centred in the 400x280 raster, so a physical line maps to
/// a logical row by subtracting this; above and below the plane the border
/// keeps the nearest row's colour, which is what the chain leaves behind.
pub const VBORDER: u16 = (zg.PHYSICAL_HEIGHT - zg.HEIGHT) / 2;

/// The pre-title drives colour 0 too, but from op 4's band rather than the
/// Timer-B table: black inside the cleared rows, white outside.  Set by vex.zig
/// while that screen is up; `rows == 0` means "use row_pal", i.e. the intro.
pub var band_top: u16 = 0;
pub var band_rows: u16 = 0;
pub var band_in: u32 = 0;
pub var band_out: u32 = 0;

pub fn borderHbl(zigos: *ZigOS, line: u16) void {
    const y: usize = if (line < VBORDER) 0 else @min(line - VBORDER, P.ROWS - 1);
    if (band_rows != 0) {
        const inside = y >= band_top and y < band_top + band_rows;
        return zigos.setBackgroundColor(Color.fromRGBA(if (inside) band_in else band_out));
    }
    zigos.setBackgroundColor(Color.fromRGBA(row_pal[y][0]));
}

pub fn rasterHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    if (line >= P.ROWS) return;
    for (row_pal[line], 0..) |c, i| fb.palette[P.BG + i] = c;
}

/// The pre-title's split: colour 0 is black down the band and white outside,
/// on the PLANE as well as the border, because on the ST they are one colour.
pub fn preTitleHbl(fb: *LogicalFB, _: *ZigOS, line: u16, _: u16) void {
    const inside = line >= band_top and line < band_top + band_rows;
    fb.palette[0] = if (inside) band_in else band_out;
}

/// Which Timer-B split owns `y`, clamped to the chain's own first and last.
pub fn splitOf(y: usize) usize {
    if (y <= SPLIT_TOP) return 0;
    if (y >= SPLIT_END) return SPLITS - 1;
    return (y - SPLIT_TOP) / 2;
}
