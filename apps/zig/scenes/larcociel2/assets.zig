// --------------------------------------------------------------------------
// larcociel2 assets -- every byte comes from tools/larcociel2/larco_assets.py,
// which rips them from github.com/olivierh59500/go-larcociel2's
// assets/original/ (the production's own files) and PROVES the result against
// 1200 of the Go's captured frames, byte for byte.
//
//   bg-static.bin      rows 0..142 of the background: palette index/4 (0..3),
//                      2 bits a pixel, 4 a byte, LSB pixel first. The
//                      backgrounds only ever hold indices 0/4/8/12, so two bits
//                      carry everything the Go's i/4 ball rule needs.
//   bg-band.bin        36 frames x rows 143..199 (57 rows), the same packing.
//                      These rows change every tick and are not a rotation of
//                      one another, so all 36 are stored.
//   balls.bin          16 x 32x32 2-bit sprites: 0 = transparent, 1..3 = shade
//                      (the Go's ball.a>0 then (i/4)*4+ball.r).
//   font.bin           31 glyphs x 32x16 1-bit alpha (font.png; the Go's text
//                      rule reads the glyph's alpha only).
//   palette.bin / raster.bin / message.txt / font-order.txt
//                      verbatim originals (the ST colour words, the feed)
//   initial-motion.bin / initial-history.bin
//                      verbatim: the trail clock's seed and 66-point history
//   (music.seq, the YM6 register stream as per-frame deltas, is NOT embedded:
//   the cart plays an SNDH; only the headless harness reads it)
// --------------------------------------------------------------------------
const zg = @import("zigos");

const DIR = "../../assets/screens/larcociel2/";

pub const bg_static = @embedFile(DIR ++ "bg-static.bin");
pub const bg_band = @embedFile(DIR ++ "bg-band.bin");
pub const balls = @embedFile(DIR ++ "balls.bin");
pub const font = @embedFile(DIR ++ "font.bin");
pub const palette_words = @embedFile(DIR ++ "palette.bin");
pub const raster_words = @embedFile(DIR ++ "raster.bin");
pub const message = @embedFile(DIR ++ "message.txt");
pub const font_order = @embedFile(DIR ++ "font-order.txt");
pub const initial_motion = @embedFile(DIR ++ "initial-motion.bin");
pub const initial_history = @embedFile(DIR ++ "initial-history.bin");

/// The band the 36 backgrounds animate; rows above it are static all run long.
pub const BAND_TOP = 143;
pub const BAND_ROWS = 57;
pub const BAND_FRAMES = 36;

/// One 2-bit pixel out of a packed plane (LSB pixel first).
pub inline fn p2(buf: []const u8, p: usize) u8 {
    return (buf[p >> 2] >> @intCast(2 * (p & 3))) & 3;
}

/// One 1-bit pixel out of a packed mask (MSB pixel first).
pub inline fn bit(buf: []const u8, p: usize) u1 {
    return @intCast((buf[p >> 3] >> @intCast(7 - (p & 7))) & 1);
}

/// An ST colour word exactly as the Go's rgb() renders it: 3 bits a channel,
/// each *34. Packed in Color.toRGBA's order (a<<24 | b<<16 | g<<8 | r).
pub fn rgbw(w: u16) u32 {
    const r: u32 = @as(u32, (w >> 8) & 7) * 34;
    const g: u32 = @as(u32, (w >> 4) & 7) * 34;
    const b: u32 = @as(u32, w & 7) * 34;
    return (255 << 24) | (b << 16) | (g << 8) | r;
}

/// A big-endian u16 word out of a binary blob.
pub fn beWord(b: []const u8, at: usize) u16 {
    return @as(u16, b[at]) << 8 | b[at + 1];
}
