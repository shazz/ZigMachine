// --------------------------------------------------------------------------
// VEX 2025 assets, ripped from the original ST binary by
// tools/private_tools/vex_assets.py.  Every table here is the program's own.
// --------------------------------------------------------------------------

pub const logo = @embedFile("../../assets/screens/vex/logo.raw");
pub const vtitle = @embedFile("../../assets/screens/vex/vtitle.raw");
pub const vtitle_pal_b = @embedFile("../../assets/screens/vex/vtitle_pal.dat");
pub const bigfont = @embedFile("../../assets/screens/vex/bigfont.raw");
pub const charmap = @embedFile("../../assets/screens/vex/charmap.txt");
pub const smallfont = @embedFile("../../assets/screens/vex/smallfont.raw");
pub const creditsfont = @embedFile("../../assets/screens/vex/creditsfont.raw");
pub const cubes = @embedFile("../../assets/screens/vex/cubes.raw");
pub const wave = @embedFile("../../assets/screens/vex/wave.dat");
pub const ramp_b = @embedFile("../../assets/screens/vex/ramp.dat");
pub const speed_b = @embedFile("../../assets/screens/vex/speed.dat");
pub const scrollcol_b = @embedFile("../../assets/screens/vex/scrollcol.dat");
pub const pal_target_b = @embedFile("../../assets/screens/vex/pal_target.dat");
pub const cube_targets_b = @embedFile("../../assets/screens/vex/cube_targets.dat");
pub const scroll_big = @embedFile("../../assets/screens/vex/scroll_big.txt");
pub const scroll_small = @embedFile("../../assets/screens/vex/scroll_small.txt");
pub const credit_pages = [4][]const u8{
    @embedFile("../../assets/screens/vex/credits0.txt"),
    @embedFile("../../assets/screens/vex/credits1.txt"),
    @embedFile("../../assets/screens/vex/credits2.txt"),
    @embedFile("../../assets/screens/vex/credits3.txt"),
};

pub const LOGO_H: usize = 44;
pub const VTITLE_H: usize = 200; // $894 copies the whole 320x200 screen
pub const GLYPHS: usize = 40; // $3864 expands 4 rows of 10 cells, and no more
pub const CUBE_FRAMES: usize = 360;
pub const CUBE_LINES: usize = 28; // of the 288-byte stride, $dd2 draws 28
pub const RAMP_LEN: usize = 232;
pub const SPEED_LEN: usize = 128;

comptime {
    if (logo.len != 320 * LOGO_H) @compileError("logo.raw is not 320x44");
    if (vtitle.len != 320 * VTITLE_H) @compileError("vtitle.raw is not 320x200");
    if (vtitle_pal_b.len != 16 * 2) @compileError("vtitle_pal.dat is not 16 words");
    if (bigfont.len != GLYPHS * 64) @compileError("bigfont.raw is not 40 x 64 bytes");
    if (cubes.len != CUBE_FRAMES * CUBE_LINES * 8) @compileError("cubes.raw is not 360 x 28 lines");
    if (ramp_b.len != RAMP_LEN * 2) @compileError("ramp.dat is not 232 words");
    if (speed_b.len != SPEED_LEN * 2) @compileError("speed.dat is not 128 words");
    if (pal_target_b.len != 21 * 2) @compileError("pal_target.dat is not 21 words");
    // The tables the run-time indexing below trusts without a bounds check.
    if (wave.len != 200) @compileError("wave.dat is not 200 entries");
    if (scrollcol_b.len != 80 * 2) @compileError("scrollcol.dat is not 80 words");
    if (smallfont.len != 96 * 8 or creditsfont.len != 96 * 8) @compileError("a font sheet is not 96 x 8 bytes");
}

/// A big-endian word out of a ripped 68000 table.
pub fn be(bytes: []const u8, i: usize) u16 {
    return (@as(u16, bytes[2 * i]) << 8) | bytes[2 * i + 1];
}

/// $38b0 builds the ASCII -> glyph table by walking charmap and numbering it.
/// Only the first 40 entries have a cell; the original indexes past its own
/// font for the rest, so those characters are dropped here instead.
pub const ascii_to_glyph: [256]u8 = blk: {
    @setEvalBranchQuota(4000);
    var t = [_]u8{0xff} ** 256;
    for (charmap, 0..) |c, i| if (i < GLYPHS) {
        t[c] = @intCast(i);
    };
    break :blk t;
};

/// Glyph `g` as 32 16-bit rows: 0..15 the left half, 16..31 the right half.
/// `g` is always a cell the font has (the scroller drops 0xff), but the read is
/// unchecked in ReleaseSmall, so a stray index is clamped to blank here.
pub fn glyphWord(g: u8, i: usize) u16 {
    if (g >= GLYPHS) return 0;
    return be(bigfont, @as(usize, g) * 32 + i);
}
