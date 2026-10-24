// --------------------------------------------------------------------------
// LEVEL 16's one plane and its palette, and the HBL that plays it.
//
// The screen used two FRESCO planes: the picture and the bob on top, and under
// them black, the two rasters and the scroller. Painter's order in one overscan
// plane gives the same picture for one plane's compositing (~0.6 Mc a frame
// less), but not in one 256-colour palette: picture and bob take entries 1..174,
// the rasters 2, and the scroller's Chrome blends up to 140 visible a frame
// (over its whole 287,120-frame text cycle). So the scroller's colours are
// handed out PER ROW: its column is 16 pixels wide, so a row never needs more
// than 16 entries, and the plane's HBL loads each row's 16 before the row is
// composited, after the copper's two raster entries (zg.copper, real rasters).
//
// Entries: 0 black (the bottom plane's black, under the picture's holes),
// 1..174 the picture and the bob, RASTER, WATER, then the scroller's 16.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");
const R = @import("rasters.zig");
const S = @import("scroller.zig");

pub const BLACK: u8 = 0;
pub const RASTER: u8 = 175;
pub const WATER: u8 = 176;
pub const SCROLL_FIRST: u8 = 177;
pub const SLOTS = 16; // the column's width in plane pixels

comptime {
    // The picture and bob palette leaves every entry from RASTER up unset: none of them is art.
    for (RASTER..256) |e| if (A.picture_palette[e].a != 0 or A.picture_palette[e].toRGBA() != 0)
        @compileError("pal_picture.dat defines an entry the merged plane gives to the rasters or the scroller");
    if (SCROLL_FIRST + SLOTS > 256) @compileError("scroller entries past 255");
}

/// Make `fb` the screen's one plane: overscan, borders open on every line, the
/// palette above, `picture` composed (compose) and copied in once, the HBL.
pub fn open(fb: *zg.LogicalFB, picture: []u8, holes: *[A.H]u16, rows: *RowPalettes, tables: *[2]zg.copper.Table) void {
    fb.is_enabled = true;
    fb.setOverscanBuffer();
    fb.setPalette(A.picture_palette);
    const black = zg.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    fb.setPaletteEntry(BLACK, black);
    fb.setPaletteEntry(RASTER, black);
    fb.setPaletteEntry(WATER, black);
    zg.copper.install(fb, &.{ RASTER, WATER }, tables, .{ .flicker = true });
    install(fb, rows);
    compose(picture, holes);
    @memcpy(zg.blit.Dst.plane(fb).buf[0 .. A.W * A.H], picture);
}

/// Each plane row's scroller colours (opaque RGBA as the palette stores them).
pub const RowPalettes = struct {
    colours: [A.H][SLOTS]u32,
    used: [A.H]u8,
};

// HBL handlers take no user pointer.
var active: ?*const RowPalettes = null;

/// From now on the plane's HBL is the copper's (border flicker and the two
/// raster entries, installed before this) and then `rows`' row.
pub fn install(fb: *zg.LogicalFB, rows: *RowPalettes) void {
    @memset(&rows.used, 0);
    active = rows;
    fb.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, hbl);
}

fn hbl(fb: *zg.LogicalFB, os: *zg.ZigOS, line: u16, x: u16) void {
    zg.copper.hbl(fb, os, line, x);
    const rows = active orelse return;
    if (line >= A.H) return; // an overscan plane's lines are its physical rows
    // Only the entries that change (a register already holding the colour is not rewritten).
    for (rows.colours[line][0..rows.used[line]], SCROLL_FIRST..) |c, e| {
        if (fb.palette[e] != c) fb.palette[e] = c;
    }
}

/// The picture with its holes filled once with what the bottom plane showed
/// there for good: a raster's or the water's entry (the copper colours them),
/// else black. `holes` gets, per row, the scroller column's holes (bit c =
/// column pixel c): the scroller paints only those, over black.
pub fn compose(picture: []u8, holes: *[A.H]u16) void {
    const raster = band(R.RASTER_X, R.RASTER_W);
    const water = band(R.WATER_X, R.WATER_W);
    const column: usize = @intCast(A.planeX(S.COLUMN_X));
    for (0..A.H) |y| {
        const row = picture[y * A.W ..][0..A.W];
        for (row[raster.at..][0..raster.n]) |*p| if (p.* == 0) {
            p.* = RASTER;
        };
        for (row[water.at..][0..water.n]) |*p| if (p.* == 0) {
            p.* = WATER;
        };
        var mask: u16 = 0;
        for (row[column..][0..SLOTS], 0..) |p, c| if (p == 0) {
            mask |= @as(u16, 1) << @intCast(c);
        };
        holes[y] = mask;
    }
}

comptime {
    if (@divExact(S.COLUMN_W, 2) != SLOTS) @compileError("the scroller column is not SLOTS plane pixels");
}

/// chrome_draw.mixRgb on colours packed 0x00BBGGRR, two channels a multiply:
/// each channel's (a * (16 - w) + b * w) >> 4 stays below 4,096 in its 16-bit
/// lane, so the lanes never carry into each other and the result is the same.
pub fn mixPacked(a: u32, b: u32, w: u8) u32 {
    const wb: u32 = w;
    const wa: u32 = 16 - wb;
    const rb = (((a & 0xFF_00FF) * wa + (b & 0xFF_00FF) * wb) >> 4) & 0xFF_00FF;
    const g = (((a & 0xFF00) * wa + (b & 0xFF00) * wb) >> 4) & 0xFF00;
    return rb | g;
}

fn band(canvas_x: i32, canvas_w: i32) struct { at: usize, n: usize } {
    return .{ .at = @intCast(A.planeX(canvas_x)), .n = @intCast(@divExact(canvas_w, 2)) };
}
