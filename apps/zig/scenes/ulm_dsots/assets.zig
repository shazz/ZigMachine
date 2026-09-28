// --------------------------------------------------------------------------
// The menu's assets, converted by tools/private_tools/ulm_dsots_assets.py from
// the remake's data/ (every image halved on its measured (0, 0) 2x grid; one
// shared palette, 0 transparent and 1 an opaque black).
//
// Two views are BUILT once per load, into zg.mem (prepare()):
//   griffin_flip  the sprite sheet with every 32x32 frame mirrored in place, as
//                 flipX(true) draws it (canvas scale(-1, 1) about the frame);
//   back_rows     back.png tiled across one 400-wide row per image row, so a
//                 frame's background is one copy per line at the parallax
//                 offset instead of a modulo per pixel.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const Level = @import("level.zig").Level;

pub const map = @import("../../assets/screens/ulm_dsots/map.zig");
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/ulm_dsots/pal.dat"));
pub const BLACK: u8 = 1; // the opaque black of pal.dat (the overlay's #000000)

pub const TILE: usize = 16; // a 32x32 map tile, halved
pub const SHEET_COLS: usize = 16; // tileset.png is 16 tiles wide
pub const FRAME: usize = 32; // a 64x64 griffin frame, halved
pub const tileset = blit.Image.init(@embedFile("../../assets/screens/ulm_dsots/tileset.raw"), SHEET_COLS * TILE);
pub const griffin = blit.Image.init(@embedFile("../../assets/screens/ulm_dsots/griffin.raw"), 4 * FRAME);
/// Foreground gids (0 empty), map.COLS x map.DATA_ROWS.
pub const foreground: []const u8 = @embedFile("../../assets/screens/ulm_dsots/foreground.dat");
pub const level = Level{ .cells = @embedFile("../../assets/screens/ulm_dsots/collision.dat") };

const back = @embedFile("../../assets/screens/ulm_dsots/back.raw");
pub const BACK_W: usize = 16;
pub const BACK_H: usize = back.len / BACK_W; // 256
pub const BACK_ROW: usize = 400; // >= the 384-wide canvas + one image width

pub var griffin_flip: blit.Image = undefined;
pub var back_rows: []u8 = undefined;

comptime {
    if (foreground.len != map.COLS * map.DATA_ROWS) @compileError("foreground.dat does not match map.zig");
    if (BACK_ROW < 384 + BACK_W) @compileError("a background row must cover the canvas at any offset");
}

/// Build the two views. False when zg.mem refuses them (counted by the machine).
pub fn prepare() bool {
    const flip = zg.mem.alloc(u8, griffin.data.len) orelse return false;
    for (0..griffin.h) |y| {
        const row = griffin.data[y * griffin.w ..][0..griffin.w];
        for (0..griffin.w) |x| flip[y * griffin.w + x] = row[(x / FRAME) * FRAME + FRAME - 1 - x % FRAME];
    }
    griffin_flip = blit.Image.init(flip, griffin.w);
    back_rows = zg.mem.alloc(u8, BACK_H * BACK_ROW) orelse return false;
    for (0..BACK_H) |y| {
        for (0..BACK_ROW) |x| back_rows[y * BACK_ROW + x] = back[y * BACK_W + x % BACK_W];
    }
    return true;
}
