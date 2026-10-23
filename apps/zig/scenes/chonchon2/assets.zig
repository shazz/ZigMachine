// --------------------------------------------------------------------------
// chonchon2 assets -- every byte comes from tools/private_tools/chonchon2_assets.py,
// which rips them from github.com/olivierh59500/go-chonchon2 (vendored under
// prototypes/go-chonchon2/) and proves the reduction:
//
//   background.bin     320x200 ST 4-plane screen (160 bytes/row), verbatim
//   font.bin           184-byte 2-plane glyph bank the ribbon reads
//   message.bin        glyph cursor table (negative words are loop markers)
//   scroll-profile.bin 7000 x 6 bytes: the scroll Y profile
//   panel-script.bin   34 x {u16 y, u16 rows, u16 hold}: the sliding panels
//   panel-pattern.bin  69 rows x 160 bytes of planar panel columns
//   sprite-a-path.bin / sprite-b-path.bin   7000 x {u16 offset, u16 half}
//   palette.bin        16 ST colour words, big-endian
//   raster-background.bin  200-word background raster base
//   raster-program.bin 506 x 180 bytes (rows 68..157 of the background raster)
//   raster-base.bin    200-word foreground raster base
//   raster-scroll.bin  21-word magenta band copied at the scroll position
//   sprite-a.idx       80 x 34 PNG indices (R = index*17)
//   sprite-b.idx       80 x 194 PNG indices
//   music-1..7.seq     the seven YM dumps as per-frame DELTA streams
//                      (u32 frame count, then per frame a u16 LE mask + the
//                      changed values in ascending register order; frame 0 is
//                      a full 14-register write, so a loop resets the chip)
// --------------------------------------------------------------------------
const zg = @import("zigos");

const DIR = "../../assets/screens/chonchon2/";


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
pub const font = embed4("font.bin");
pub const message = embed4("message.bin");
pub const profile = embed4("scroll-profile.bin");
pub const panel = embed4("panel-script.bin");
pub const panel_pattern = embed4("panel-pattern.bin");
pub const path_a = embed4("sprite-a-path.bin");
pub const path_b = embed4("sprite-b-path.bin");
pub const palette_words = embed4("palette.bin");
pub const raster_bg = embed4("raster-background.bin");
pub const raster_program = embed4("raster-program.bin");
pub const raster_base = embed4("raster-base.bin");
pub const raster_scroll = embed4("raster-scroll.bin");
pub const sprite_a = embed4("sprite-a.idx");
pub const sprite_b = embed4("sprite-b.idx");

pub const sprite_a_w: usize = 80;
pub const sprite_a_h: usize = 34;
pub const sprite_b_w: usize = 80;
pub const sprite_b_h: usize = 194;

/// One delta stream per replacement YM dump the Go's F1..F7 select.
pub const music: [7][]const u8 = .{
    @embedFile(DIR ++ "music-1.seq"),
    @embedFile(DIR ++ "music-2.seq"),
    @embedFile(DIR ++ "music-3.seq"),
    @embedFile(DIR ++ "music-4.seq"),
    @embedFile(DIR ++ "music-5.seq"),
    @embedFile(DIR ++ "music-6.seq"),
    @embedFile(DIR ++ "music-7.seq"),
};

/// An ST colour word exactly as the Go's rgb() renders it: 3 bits a channel,
/// each *34. Packed in Color.toRGBA's order (a<<24 | b<<16 | g<<8 | r).
pub fn rgbw(w: u16) u32 {
    const r: u32 = @as(u32, (w >> 8) & 7) * 34;
    const g: u32 = @as(u32, (w >> 4) & 7) * 34;
    const b: u32 = @as(u32, w & 7) * 34;
    return (255 << 24) | (b << 16) | (g << 8) | r;
}

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
