// Union Demo menu assets, converted by tools/private_tools/union_demo_assets.py
// from the remake's data/ (every image halved on its own measured 2x grid).
//
// The graphics (tileset, Charly, banner, logo, panorama, font, scrolltext) ship
// as ONE ZX0-packed blob, menu_assets.bin, and depack behind menuloader.js's TEX
// panel at every start (loading.zig). bind() points the views below into it.
const zg = @import("zigos");
const blit = zg.blit;

pub const map = @import("../../assets/screens/union_demo/menu_map.zig");
pub const colors = @import("../../assets/screens/union_demo/menu_colors.zig");
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_demo/pal.dat"));

/// Foreground tile gids and Collision kinds, in the ORIGINAL map pixels (32x16).
pub const foreground = zg.tilemap.Grid{
    .cells = @embedFile("../../assets/screens/union_demo/foreground.dat"),
    .cols = map.COLS,
    .rows = map.ROWS,
    .tw = map.TILE_W,
    .th = map.TILE_H,
};
pub const collision = zg.tilemap.Grid{
    .cells = @embedFile("../../assets/screens/union_demo/collision.dat"),
    .cols = map.COLS,
    .rows = map.ROWS,
    .tw = map.TILE_W,
    .th = map.TILE_H,
};

pub const CHARLY_W: usize = 40;
pub const CHARLY_H: usize = 51;
pub const GLYPH_W: usize = 32;
pub const GLYPH_H: usize = 17;

/// One colour index per row: doorrasters.png (1200 rows), scrollrasters.png (45).
pub const door_rows = @embedFile("../../assets/screens/union_demo/doorrasters.dat");
pub const scroll_rows = @embedFile("../../assets/screens/union_demo/scrollrasters.dat");

// menu_assets.bin, in this order (the raws the asset script writes, concatenated).
const TILESET_LEN = 22528; // tileset.raw, 352 wide
const CHARLY_LEN = 16320; // charly.raw and charly_flip.raw, 320 wide
const BANNER_LEN = 12800; // banner.raw, 320 wide
const LOGO_LEN = 3712; // logo.raw, 128 wide
const PANORAMA_LEN = 13312; // panorama.raw, 832 wide
const FONT_LEN = 32640; // font_out.raw, 320 wide
const SCROLLTEXT_LEN = 16128; // scrolltext.txt
pub const BLOB_LEN = TILESET_LEN + 2 * CHARLY_LEN + BANNER_LEN + LOGO_LEN + PANORAMA_LEN + FONT_LEN + SCROLLTEXT_LEN;

pub var tileset: zg.tilemap.TileSheet = undefined;
pub var charly: blit.Image = undefined;
pub var charly_flip: blit.Image = undefined;
pub var banner: blit.Image = undefined;
pub var logo: blit.Image = undefined;
/// panorama.png twice side by side, as the remake's 1664-wide panocanvas.
pub var panorama: blit.Image = undefined;
pub var font: blit.Image = undefined;
pub var scrolltext: []const u8 = undefined;

/// Point every view into the depacked blob (BLOB_LEN bytes).
pub fn bind(blob: []const u8) void {
    var at: usize = 0;
    const take = struct {
        fn f(b: []const u8, pos: *usize, len: usize) []const u8 {
            defer pos.* += len;
            return b[pos.*..][0..len];
        }
    }.f;
    tileset = .{ .raw = take(blob, &at, TILESET_LEN), .sheet_w = 352, .tw = 16, .th = 8, .cols = 22 };
    charly = blit.Image.init(take(blob, &at, CHARLY_LEN), 320);
    charly_flip = blit.Image.init(take(blob, &at, CHARLY_LEN), 320);
    banner = blit.Image.init(take(blob, &at, BANNER_LEN), 320);
    logo = blit.Image.init(take(blob, &at, LOGO_LEN), 128);
    panorama = blit.Image.init(take(blob, &at, PANORAMA_LEN), 832);
    font = blit.Image.init(take(blob, &at, FONT_LEN), 320);
    scrolltext = take(blob, &at, SCROLLTEXT_LEN);
}
