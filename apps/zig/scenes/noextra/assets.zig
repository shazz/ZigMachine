// --------------------------------------------------------------------------
// NOEXTRA's assets, ripped from the ORIGINAL intro: fujiology.org
// ST/N/NOEXTRA/RASTERS.ZIP -> RASTERS.PRG (25,246 bytes). Its 222-byte TEXT is
// a depacker: an LZ whose flag byte is read MSB first, 1 = match (b1, b2 ->
// offset ((b1 >> 4) << 8) | b2, length (b1 & 15) + 3), 0 = literal byte. It
// unpacks the DATA segment to an 88,670-byte PRG (TEXT $37E2, DATA $12144,
// BSS $23C12) and runs it. The offsets below are into that depacked file (its
// 28-byte header included); in Hatari its TEXT loaded at $AA9A, so RAM address
// = offset + $AA7E. Every .raw/.pal/.bin here is those bytes, converted only
// from planar to chunky for the three pictures (prototypes/noextra_re/tools/
// noextra_assets.py does the whole rip):
//
//   toplogo.raw    320x69   +0x38DA  NOEXTRA + "MISTER.A", top palette
//   bottomlogo.raw 320x100  +0x8332  ZORRO 2, bottom palette (+15 an index)
//   dhs.raw        192x112  +0xC272  D.H.S ONLINE COMPO 2005 with its erase margins
//   pal_top.pal    16 words +0x380E  installed by the main VBL
//   pal_bottom.pal 16 words +0x8312  installed by Timer B after the band
//   pal_dhs.pal    16 words +0xC252  the intro's
//   ramp.pal       96 words +0x64E0  the band's rainbow, one colour-0 write each
//   gradbar.pal    40 words +0x649A  the one-line bars above and below the band
//   sine.bin      252 words +0x65A8  byte offsets into ramp.pal (0..58)
//   wave.bin      200 words +0x7280  scroller column heights, lines * 160
//   bob.bin        74 words +0x3844  the screen's (and the intro logo's) bounce
//   font.bin       52 x 64  +0x7412  32x16, ONE plane: two 16-px halves of 16 words
//   charset.bin    52 bytes +0x6B90  the order of font.bin's glyphs
//   scrolltext.bin           +0x6BC4  1,723 bytes up to the terminating zero
//
// THE COLOURS ARE STE WORDS. No STE register is touched and the intro runs the
// same on an STF, but the rainbow (008 001 009 002 ...) and the bottom logo's
// palette ($0BDD $0ABC $09AB) use the STE's fourth bit. On an ST the shifter
// drops it, and neighbouring ramp entries pair up. ST is the default here (every
// channel nibble * 32, as the screen showed on the machine it was entered for);
// STE = true decodes the same words the STE way.
// No ZigOS import: tests natively (scene_tests.zig).
// --------------------------------------------------------------------------
pub const STE = false;

const DIR = "../../assets/screens/noextra/";
pub const toplogo = @embedFile(DIR ++ "toplogo.raw");
pub const bottomlogo = @embedFile(DIR ++ "bottomlogo.raw");
pub const dhs = @embedFile(DIR ++ "dhs.raw");
pub const font = @embedFile(DIR ++ "font.bin");
pub const charset = @embedFile(DIR ++ "charset.bin");
pub const text = @embedFile(DIR ++ "scrolltext.bin");

pub const LOGO_W = 320;
pub const TOP_H = 69;
pub const BOTTOM_H = 100;
pub const DHS_W = 192;
pub const DHS_H = 112;

pub const pal_top = words(16, @embedFile(DIR ++ "pal_top.pal"));
pub const pal_bottom = words(16, @embedFile(DIR ++ "pal_bottom.pal"));
pub const pal_dhs = words(16, @embedFile(DIR ++ "pal_dhs.pal"));
pub const ramp = words(96, @embedFile(DIR ++ "ramp.pal"));
pub const gradbar = words(40, @embedFile(DIR ++ "gradbar.pal"));
pub const sine = words(252, @embedFile(DIR ++ "sine.bin"));
pub const wave = words(200, @embedFile(DIR ++ "wave.bin"));
pub const bob = words(74, @embedFile(DIR ++ "bob.bin"));

/// Big-endian words, as the 68000 stored them.
fn words(comptime n: usize, comptime b: []const u8) [n]u16 {
    if (b.len != 2 * n) @compileError("noextra: an asset is not the size the rip wrote");
    var out: [n]u16 = undefined;
    for (&out, 0..) |*w, i| w.* = (@as(u16, b[2 * i]) << 8) | b[2 * i + 1];
    return out;
}

/// One channel nibble of a palette word, 0..255.
fn channel(n: u16) u32 {
    if (STE) return (((n & 7) << 1) | ((n >> 3) & 1)) * 17;
    return (n & 7) * 32;
}

/// A palette word as the plane stores it (zg.Color.toRGBA: A B G R), opaque.
pub fn rgba(w: u16) u32 {
    return 0xFF00_0000 | (channel(w) << 16) | (channel(w >> 4) << 8) | channel(w >> 8);
}

// --- the one plane's palette -----------------------------------------------
// 0 black ground; 1..15 the top logo (and the intro's D.H.S logo); 16..30 the
// bottom logo; 31 the scroller's ink; then the band's raster blocks and the
// bars' blocks. Only BAND's entries change per line.
pub const TOP: u8 = 0; // top logo pixel p -> TOP + p
pub const BOTTOM: u8 = 15; // bottom logo pixel p -> BOTTOM + p (p > 0)
pub const INK: u8 = 31;
pub const BAND: u8 = 32; // 35 visible colour-0 blocks of the rainbow
pub const BAND_BLOCKS = 35;
pub const BAR: u8 = BAND + BAND_BLOCKS; // 35 visible blocks of the gradient bars

/// The palette entries every frame of `main` starts from (BAND's are the HBL's).
pub fn mainPalette() [256]u32 {
    var p = [_]u32{rgba(0)} ** 256;
    for (1..16) |i| p[TOP + i] = rgba(pal_top[i]);
    for (1..16) |i| p[BOTTOM + i] = rgba(pal_bottom[i]);
    p[INK] = rgba(pal_top[1]); // the letters are plane 0 only: colour 1, $777
    for (0..BAND_BLOCKS) |j| p[BAR + j] = rgba(gradbar[j]);
    return p;
}

test "noextra: the rip is the size and shape the scene reads" {
    const std = @import("std");
    try std.testing.expectEqual(@as(usize, LOGO_W * TOP_H), toplogo.len);
    try std.testing.expectEqual(@as(usize, LOGO_W * BOTTOM_H), bottomlogo.len);
    try std.testing.expectEqual(@as(usize, DHS_W * DHS_H), dhs.len);
    try std.testing.expectEqual(@as(usize, 52 * 64), font.len);
    try std.testing.expectEqual(@as(usize, 1723), text.len);
    try std.testing.expectEqual(@as(u16, 0x0777), pal_top[1]);
    try std.testing.expectEqual(@as(u32, 0xFFE0E0E0), rgba(0x0777));
    for (sine) |s| try std.testing.expect(s % 2 == 0 and s <= 58);
}
