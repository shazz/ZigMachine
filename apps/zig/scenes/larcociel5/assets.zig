// --------------------------------------------------------------------------
// larcociel5 assets -- every byte comes from tools/larcociel5/larco_assets.py,
// which rips them from github.com/olivierh59500/go-larcociel5's
// assets/original/ (the production's own files) and PROVES the result against
// 1200 of the Go's captured frames, byte for byte.
//
//   bg.idx            320x200 palette indices 0..15 (background.png, R=idx*17)
//   ribbon.bin        112x50, palette index 1..3 where opaque, 0 = transparent
//   bats.bin          15 x 64x32 1-bit masks (bat-*.png; covered pixel R=68 -> 4)
//   palette.bin       16 ST colour words (big-endian), the static palette
//   raster.bin        33 ST colour words; rows 33..63 are the 0x700 fallback
//   font-colors.bin   30 glyphs x 17 rows x 15 cols of ST colour words
//   message.txt       the stencil's character feed
//   initial-motion.bin / initial-history.bin  the clock's seed and 50-row trail
//   (music.seq, the YM6 register stream as per-frame deltas, is NOT embedded:
//   the cart plays an SNDH; only the headless harness reads it)
// --------------------------------------------------------------------------
const zg = @import("zigos");

const DIR = "../../assets/screens/larcociel5/";


/// An asset 4-byte aligned in the data segment. The big-endian word reads
/// compile to wide loads, and a wide load off an odd address TRAPS on the
/// board (~700 cycles each: 3,300 a frame from the colour bank's font reads).
fn embed4(comptime name: []const u8) *const [@embedFile(DIR ++ name).len]u8 {
    const S = struct {
        const data: [@embedFile(DIR ++ name).len]u8 align(4) = @embedFile(DIR ++ name).*;
    };
    return &S.data;
}

pub const bg = embed4("bg.idx");
pub const ribbon = embed4("ribbon.bin");
pub const bats = embed4("bats.bin");
pub const palette_words = embed4("palette.bin");
pub const raster_words = embed4("raster.bin");
pub const font_colors = embed4("font-colors.bin");
pub const message = embed4("message.txt");
pub const initial_motion = embed4("initial-motion.bin");
pub const initial_history = embed4("initial-history.bin");

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

/// One bit of bat mask `k` (64x32, MSB first, row-major).
pub inline fn batBit(k: usize, x: usize, y: usize) u1 {
    const o = y * 64 + x;
    return @intCast((bats[k * 256 + (o >> 3)] >> @intCast(7 - (o & 7))) & 1);
}

pub fn color(w: u32) zg.Color {
    return zg.Color.fromRGBA(w);
}
