//! One NFO character cell, 8 pixels wide and 9 high (the reference viewer's cell, measured on
//! Matt's ascii.png: 640 / 80 columns = 8, ~8.8 a row after its 0.96 downscale = 9). The text
//! glyphs are the 8x8 font in rows 0..7 (row 8 blank); the CP437 block and shade characters are
//! drawn here, procedurally, over all 9 rows so stacked blocks join, with the viewer's faint
//! grid on solid areas (a bottom line, a right line) and its dither on the shades.
const font = @import("nfo_font.zig");

pub const cell_w: u32 = 8;
pub const cell_h: u32 = 9;

/// Palette indices. 0 is "no ink" for a glyph pixel and the background for the picture.
pub const bg: u8 = 0;
pub const white: u8 = 1;
pub const shadow: u8 = 2; // the viewer's dark drop shadow, one pixel down and right of every ink pixel
pub const grid_h: u8 = 3; // faint line on the bottom row of a solid cell
pub const grid_v: u8 = 4; // faint line on the right column of a solid cell
pub const bar_bg: u8 = 5; // the prompt bar
pub const bar_shadow: u8 = 6;
pub const bar_line: u8 = 7; // the bar's top rule

/// 0xAABBGGRR words, as zigos palettes want them; every unused entry stays black.
pub const palette = blk: {
    var p = [_]u32{0xFF00_0000} ** 256;
    p[bg] = rgb(0x40, 0x5F, 0x89); // the reference's blue (a muted Workbench blue)
    p[white] = rgb(0xFF, 0xFF, 0xFF);
    p[shadow] = rgb(0x1F, 0x3B, 0x67);
    p[grid_h] = rgb(0xE2, 0xE6, 0xEB);
    p[grid_v] = rgb(0xE5, 0xDA, 0xF0);
    p[bar_bg] = rgb(0x1F, 0x3B, 0x67);
    p[bar_shadow] = rgb(0x12, 0x25, 0x45);
    p[bar_line] = rgb(0xA3, 0xE1, 0xFF); // the reference's light blue
    break :blk p;
};

fn rgb(r: u32, g: u32, b: u32) u32 {
    return r | g << 8 | b << 16 | 0xFF00_0000;
}

/// True for the characters whose ink reaches the cell's last column or row, so their shadow
/// (and a neighbour's) can fall into the next cell: the blocks and shades.
pub fn bleeds(ch: u8) bool {
    return ch >= 0xB0 and ch <= 0xB2 or ch >= 0xDB and ch <= 0xDF;
}

/// True when the cell has no ink at all.
pub fn blank(ch: u8) bool {
    return ch <= 0x20 or ch == 0x7F or ch == 0xA0 or ch == 0xFF;
}

/// The colour index of pixel (x, ly) of character `ch`, 0 for none. `ly` is 0..8; `par` is the
/// parity of the pixel's ABSOLUTE row, so a dither runs on across cell rows without a seam.
pub fn pix(ch: u8, x: u32, ly: u32, par: u32) u8 {
    if (ch >= 0x20 and ch < 0x7F) {
        if (ly > 7) return 0;
        return @intFromBool(font.ascii[ch - 0x20][ly] & (@as(u8, 0x80) >> @intCast(x)) != 0);
    }
    return switch (ch) {
        0xDB => solid(x, ly),
        0xDF => if (ly <= 4) solid(x, ly) else 0,
        0xDC => if (ly >= 4) solid(x, ly) else 0,
        0xDD => if (x <= 3) solid(x, ly) else 0,
        0xDE => if (x >= 4) solid(x, ly) else 0,
        0xB0 => dither(x, par, 1),
        0xB1 => dither(x, par, 2),
        0xB2 => dither(x, par, 3),
        0xFE => @intFromBool(x >= 2 and x <= 5 and ly >= 2 and ly <= 5), // ■
        0xF9, 0xFA => @intFromBool(x >= 3 and x <= 4 and ly >= 3 and ly <= 4), // ∙ ·
        else => if (blank(ch)) 0 else unknown(x, ly),
    };
}

fn solid(x: u32, ly: u32) u8 {
    if (ly == 8) return grid_h;
    return if (x == 7) grid_v else white;
}

// 25 / 50 / 75 % white in a 2x2 pattern; `level` is the number of the four positions lit.
fn dither(x: u32, par: u32, level: u32) u8 {
    const pos = (x & 1) + 2 * par;
    const lit = switch (level) {
        1 => pos == 0,
        2 => pos == 0 or pos == 3,
        else => pos != 3,
    };
    return @intFromBool(lit);
}

// An accented letter, Greek or line-drawing character: not drawn yet, shown as a hollow box so it
// is visible rather than silently absent.
fn unknown(x: u32, ly: u32) u8 {
    const edge = x == 1 or x == 5 or ly == 1 or ly == 6;
    return @intFromBool(x >= 1 and x <= 5 and ly >= 1 and ly <= 6 and edge);
}
