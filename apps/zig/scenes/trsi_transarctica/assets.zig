// --------------------------------------------------------------------------
// TRANSARCTICA assets, ripped out of the depacked TRSI_FAL.PRG (addresses are
// TEXT-relative, base 0) and checked against the Hatari RAM snapshots by the
// reverse-engineering model (logo planes and palette equal the RAM's).
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/trsi_transarctica/";

pub const W = 320;

/// Image lines 10..111 of the Prism Paint PNT at DATA $2B2E, remapped through
/// the VDI->hardware table ($946) and cut to planes 0-4 as $3AC copies it:
/// 320x102 indices, 0..31.
pub const logo = @embedFile(DIR ++ "logo_idx.bin");
pub const LOGO_H = 102;
/// The PNT's permille palette through $235C: 256 big-endian Falcon longs
/// (RRRRRRxx GGGGGGxx 00 BBBBBBxx).
pub const logo_pal = @embedFile(DIR ++ "logo_pal.bin");
/// $1C22 as stored in the file: the intro handler's palette buffer, all white.
pub const init_pal = @embedFile(DIR ++ "init_pal.bin");
/// Planes 0-6 of the 320x136 bitmap at DATA $171AE: the "hump", 0..127.
pub const bg_map = @embedFile(DIR ++ "bg_map.bin");
pub const BG_H = 136;
/// $2022: 59 slots of 7 words, 8x7 1bpp; the high byte of each word is set A
/// (space..Z), the low byte set B (the small caps).
pub const font = @embedFile(DIR ++ "font.bin");
pub const FONT_SLOTS = 59;
/// DATA $B78..$1BD4: 6 pages of 17 rows x 40 chars, rows end $0D, pages $FF,
/// a final $00 wraps to the first page.
pub const text = @embedFile(DIR ++ "text.bin");
/// DATA $29DB2: the colour list, 2108 big-endian Falcon longs with $FFFE page
/// markers and a $FFFF restart.
pub const colours = @embedFile(DIR ++ "colours.bin");
pub const COLOURS = colours.len / 4;

pub fn long(bytes: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, bytes[i * 4 ..][0..4], .big);
}

comptime {
    if (logo.len != W * LOGO_H) @compileError("logo_idx.bin is not 320x102");
    if (bg_map.len != W * BG_H) @compileError("bg_map.bin is not 320x136");
    if (logo_pal.len != 1024 or init_pal.len != 1024) @compileError("a palette is not 256 longs");
    if (font.len != FONT_SLOTS * 14) @compileError("font.bin is not 59 x 7 words");
    if (colours.len != 2108 * 4) @compileError("colours.bin is not 2108 longs");
}
