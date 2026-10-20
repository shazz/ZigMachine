// --------------------------------------------------------------------------
// LOCKBUSTER 3 assets -- every byte comes from
// tools/private_tools/lockbuster3_assets.py, which rips
// github.com/olivierh59500/go-lockbuster3's assets/original/ (itself the
// original 1989 intro's data) and asserts the red=index*17 invariant, the
// font's 0/255 bits and ROLLOUT2.YM's YM6 header/lane layout.
//
//   background.bin   320x40 indices, artwork rows 35..74 (tiled 5x to 320x240)
//   bars.bin         320x50 indices, artwork rows 75..124 (20 32x25 meters)
//   letters.bin      3x48x35 indices, 0 = transparent (d, m, a)
//   panels-{0,1,2}.bin  320x160 indices, nibble-packed (20 64x40 frames each)
//   font-{0,1}.bin   512x320 1-bit glyph cells, 64 bytes/row
//   palette.bin      16 big-endian ST colour words (the Go's `Palette`)
//   raster.bin       39 words, the Go loop's effective `Rasters` table
//   message.bin      the scroll clock's message bytes
//   panel-order.bin  64 big-endian u32 panel-clock entries
//   motion.bin       3 x 8 signed big-endian words (d, m, a)
// --------------------------------------------------------------------------
const zg = @import("zigos");

const DIR = "../../assets/screens/lockbuster3/";

pub const background = @embedFile(DIR ++ "background.bin");
pub const bars = @embedFile(DIR ++ "bars.bin");
pub const letters = @embedFile(DIR ++ "letters.bin");
pub const panels = [3][]const u8{
    @embedFile(DIR ++ "panels-0.bin"),
    @embedFile(DIR ++ "panels-1.bin"),
    @embedFile(DIR ++ "panels-2.bin"),
};
pub const fonts = [2][]const u8{
    @embedFile(DIR ++ "font-0.bin"),
    @embedFile(DIR ++ "font-1.bin"),
};
pub const palette = @embedFile(DIR ++ "palette.bin");
pub const raster = @embedFile(DIR ++ "raster.bin");
pub const message = @embedFile(DIR ++ "message.bin");
pub const panel_order = @embedFile(DIR ++ "panel-order.bin");
pub const motion = @embedFile(DIR ++ "motion.bin");

/// The Go's putRGB(): ST colour word -> RGBA, each 3-bit gun *34. The machine's
/// palette entries are RGBA in the same byte order as `Color`.
pub fn wordColor(w: u16) zg.Color {
    return .{
        .r = @intCast(((w >> 8) & 7) * 34),
        .g = @intCast(((w >> 4) & 7) * 34),
        .b = @intCast((w & 7) * 34),
        .a = 255,
    };
}

pub fn beWord(b: []const u8, at: usize) u16 {
    return @as(u16, b[at]) << 8 | b[at + 1];
}

pub fn beLong(b: []const u8, at: usize) u32 {
    return @as(u32, b[at]) << 24 | @as(u32, b[at + 1]) << 16 |
        @as(u32, b[at + 2]) << 8 | b[at + 3];
}

pub fn sWord(b: []const u8, at: usize) i16 {
    return @bitCast(beWord(b, at));
}
