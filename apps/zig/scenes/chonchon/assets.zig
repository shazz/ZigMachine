// --------------------------------------------------------------------------
// chonchon assets -- every byte comes from tools/chonchon/chon_assets.py, which
// rips them from github.com/olivierh59500/go-chonchon's assets/original/ (the
// production's own files) and PROVES the result against 1200 of the Go's
// captured frames, byte for byte, plus the Go tree's two native scroll-bank
// checkpoints.
//
//   background.bin   320x200 ST 4-plane screen (160 bytes/row), verbatim
//   font-source.bin  the Huffman-unpacked glyph bank the two ring scrollers read
//   logo-path.bin    the 63-row chrome logo's per-row X (u16) and bank phase (u32)
//   logo-y.bin       the logo's vertical transport
//   scroll-y.bin     the scroller's two per-column wave tables
//   message.bin      the scroller's message cursor table
//   star-paths.bin / star-index.bin  the 100 authored star paths and their seeds
//   palette.bin      the 16 ST colour words (big-endian) -- the static palette
//   raster.bin       the 28 ST colour words the shader paints on rows 144..199
//   volume-curve.bin the YM volume -> meter height curve
//   meter-raw.bin    the meter bar mask (plane-0 words, 160 bytes/row)
//   logo.idx         96 x 1071 logo-bank.png indices (R=idx*17, alpha 0 = 0)
//   (music.seq, the YM6 register stream as per-frame deltas, is NOT embedded:
//   the cart plays rollout.sndh; only apps/chonchon_headless.mjs reads it)
// --------------------------------------------------------------------------
const zg = @import("zigos");

const DIR = "../../assets/screens/chonchon/";


/// An asset 4-byte aligned in the data segment. The big-endian word reads
/// below compile to wide loads, and a wide load off an odd/2-mod-4 address
/// TRAPS on the board (~700 cycles each); aligned, the ones at aligned
/// offsets are plain loads.
fn embed4(comptime name: []const u8) *const [@embedFile(DIR ++ name).len]u8 {
    const S = struct {
        const data: [@embedFile(DIR ++ name).len]u8 align(4) = @embedFile(DIR ++ name).*;
    };
    return &S.data;
}

pub const background = embed4("background.bin");
pub const font = embed4("font-source.bin");
pub const logo_path = embed4("logo-path.bin");
pub const logo_y = embed4("logo-y.bin");
pub const scroll_y = embed4("scroll-y.bin");
pub const message = embed4("message.bin");
pub const star_paths = embed4("star-paths.bin");
pub const star_index = embed4("star-index.bin");
pub const palette_words = embed4("palette.bin");
pub const raster_words = embed4("raster.bin");
pub const volume_curve = embed4("volume-curve.bin");
pub const meter_raw = embed4("meter-raw.bin");
pub const logo = embed4("logo.idx");

/// An ST colour word exactly as the Go's rgb() renders it: 3 bits a channel,
/// each *34. Packed in Color.toRGBA's order (a<<24 | b<<16 | g<<8 | r).
pub fn rgbw(w: u16) u32 {
    const r: u32 = @as(u32, (w >> 8) & 7) * 34;
    const g: u32 = @as(u32, (w >> 4) & 7) * 34;
    const b: u32 = @as(u32, w & 7) * 34;
    return (255 << 24) | (b << 16) | (g << 8) | r;
}

/// A big-endian u16/u32 word out of a binary blob.
pub fn beWord(b: []const u8, at: usize) u16 {
    return @as(u16, b[at]) << 8 | b[at + 1];
}

pub fn beLong(b: []const u8, at: usize) u32 {
    return @as(u32, b[at]) << 24 | @as(u32, b[at + 1]) << 16 |
        @as(u32, b[at + 2]) << 8 | b[at + 3];
}

/// Signed view of a big-endian u16 (the Go's `int16(...)`).
pub fn sWord(b: []const u8, at: usize) i16 {
    return @bitCast(beWord(b, at));
}

pub fn color(w: u32) zg.Color {
    return zg.Color.fromRGBA(w);
}
