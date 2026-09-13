// Union Demo menu assets, converted by tools/private_tools/union_demo_assets.py
// from the remake's data/ (every image halved on its own measured 2x grid).
const zg = @import("zigos");
const blit = zg.blit;

pub const map = @import("../../assets/screens/union_demo/menu_map.zig");
pub const colors = @import("../../assets/screens/union_demo/menu_colors.zig");
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_demo/pal.dat"));

pub const tileset = zg.tilemap.TileSheet{
    .raw = @embedFile("../../assets/screens/union_demo/tileset.raw"),
    .sheet_w = 352,
    .tw = 16,
    .th = 8,
    .cols = 22,
};
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
pub const charly = blit.Image.init(@embedFile("../../assets/screens/union_demo/charly.raw"), 320);
pub const charly_flip = blit.Image.init(@embedFile("../../assets/screens/union_demo/charly_flip.raw"), 320);

pub const banner = blit.Image.init(@embedFile("../../assets/screens/union_demo/banner.raw"), 320);
pub const logo = blit.Image.init(@embedFile("../../assets/screens/union_demo/logo.raw"), 128);
/// panorama.png twice side by side, as the remake's 1664-wide panocanvas.
pub const panorama = blit.Image.init(@embedFile("../../assets/screens/union_demo/panorama.raw"), 832);

pub const GLYPH_W: usize = 32;
pub const GLYPH_H: usize = 17;
pub const font = blit.Image.init(@embedFile("../../assets/screens/union_demo/font_out.raw"), 320);

/// One colour index per row: doorrasters.png (1200 rows), scrollrasters.png (45).
pub const door_rows = @embedFile("../../assets/screens/union_demo/doorrasters.dat");
pub const scroll_rows = @embedFile("../../assets/screens/union_demo/scrollrasters.dat");

pub const scrolltext = @embedFile("../../assets/screens/union_demo/scrolltext.txt");
