// --------------------------------------------------------------------------
// DELTA FORCE assets: the layout of deltaforce.bin, the one image this screen
// depacks (tools/private_tools/union_deltaforce_assets.py writes it from the
// remake's screens/deltaforce/*.png). Index 0 is transparent; 1 is opaque black.
//
// The pictures are clean 2x grids, halved exactly. questfont.png is not: its
// glyphs carry a one-pixel outline at full resolution, so it is halved by area
// into alpha LEVELS, twice, once per vertical parity the sine can put it on.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;

pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_deltaforce/pal.dat"));
pub const BLACK: u8 = 1;

pub const FLOOR_W = 298; // floor.png 596x62
pub const FLOOR_H = 31;
pub const LOGO_W = 320; // logos.png 640x256: initTile(640, 256/2), two logos
pub const LOGO_TILE_H = 64;
pub const BALLS_W = 768; // balls.png 1536x114: 16 frames of 96x114
pub const BALL_W = 48;
pub const BALL_H = 57;
pub const GOLD_W = 320; // gold_backdrop.png 640x118, a 2-D texture
pub const GOLD_H = 59;
pub const FONT_W = 320; // questfont.png 640x238: initTile(64,34,32), 10 x 7 tiles
const TILE_W = 32;
const TILES_PER_ROW = 10;
const TILE_ROWS = 7;
/// Rows per tile in each halving: the text canvas is 32 rows high, so parity 0
/// pairs rows 0..31 into 16, parity 1 pairs (-1,0)..(31,32) into 17.
pub const GLYPH_ROWS = [2]usize{ 16, 17 };
const FIRST_CHAR = 32;

/// Text colours: TEXT_BASE + (gold - 1) * LEVELS + (level - 1), the gold
/// backdrop's colour 1..6 at level/LEVELS of its brightness (the text is drawn
/// over black). The asset script prints TEXT_BASE; the harness checks the RGB.
pub const TEXT_BASE: u8 = 41;
pub const LEVELS = 8;

pub const TOTAL = FLOOR_W * FLOOR_H + LOGO_W * 2 * LOGO_TILE_H + BALLS_W * BALL_H + GOLD_W * GOLD_H +
    FONT_W * TILE_ROWS * (GLYPH_ROWS[0] + GLYPH_ROWS[1]);

comptime {
    std.debug.assert(TEXT_BASE + 6 * LEVELS <= 256);
}

pub const Images = struct {
    floor: blit.Image,
    logos: blit.Image,
    balls: blit.Image,
    gold: blit.Image, // colour 0..6 of gold_backdrop.png
    font: [2]blit.Image, // alpha levels 0..LEVELS, parity 0 and 1

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        var at: usize = 0;
        const take = struct {
            fn f(b: []const u8, pos: *usize, n: usize) []const u8 {
                defer pos.* += n;
                return b[pos.*..][0..n];
            }
        }.f;
        return .{
            .floor = blit.Image.init(take(buf, &at, FLOOR_W * FLOOR_H), FLOOR_W),
            .logos = blit.Image.init(take(buf, &at, LOGO_W * 2 * LOGO_TILE_H), LOGO_W),
            .balls = blit.Image.init(take(buf, &at, BALLS_W * BALL_H), BALLS_W),
            .gold = blit.Image.init(take(buf, &at, GOLD_W * GOLD_H), GOLD_W),
            .font = .{
                blit.Image.init(take(buf, &at, FONT_W * TILE_ROWS * GLYPH_ROWS[0]), FONT_W),
                blit.Image.init(take(buf, &at, FONT_W * TILE_ROWS * GLYPH_ROWS[1]), FONT_W),
            },
        };
    }

    /// logo.drawTile(nb): tile `nb` of the two.
    pub fn logo(self: *const Images, nb: u1) blit.Image {
        const rows = LOGO_W * LOGO_TILE_H;
        return blit.Image.init(self.logos.data[@as(usize, nb) * rows ..][0..rows], LOGO_W);
    }
};

/// drawTile(ch - 32) on the halving of `parity`; null past the sheet.
pub fn glyph(ch: u8, parity: u1) ?blit.Rect {
    if (ch < FIRST_CHAR) return null;
    const nb: usize = ch - FIRST_CHAR;
    if (nb >= TILES_PER_ROW * TILE_ROWS) return null;
    const h = GLYPH_ROWS[parity];
    return .{ .x = nb % TILES_PER_ROW * TILE_W, .y = nb / TILES_PER_ROW * h, .w = TILE_W, .h = h };
}

/// A text pixel of alpha `level` (1..LEVELS) over the gold colour under it.
pub fn textColour(gold: u8, level: u8) u8 {
    if (gold == 0) return BLACK;
    return TEXT_BASE + (gold - 1) * LEVELS + (level - 1);
}
