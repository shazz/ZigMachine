// --------------------------------------------------------------------------
// The Erfurt Megademo menu's data, ripped from the original disks by
// prototypes/erfurt_re/tools/erfurt_assets.py (the menu extracted from the
// protected disks, locally). Addresses are the menu's run addresses
// ($10000-based). The tables the menu GENERATES at init (drum font, the two
// colour ramps, the floor patterns) come from a RAM dump of the running menu:
// they never change after init.
// --------------------------------------------------------------------------
const DIR = "../../assets/screens/erfurt_menu/";

/// An embedded table, 4-aligned. @embedFile data is align(1) and may sit at an
/// odd address, and LLVM merges be()'s two byte loads into one u16 load: on the
/// board every such misaligned load traps (frame_cost saw ~220 a frame from
/// the shadow, the floor, the rainbow and the palettes).
fn aligned(comptime name: []const u8) []align(4) const u8 {
    const data = @embedFile(DIR ++ name);
    return &struct {
        const bytes: [data.len]u8 align(4) = data[0..data.len].*;
    }.bytes;
}

pub const logo = aligned("logo.raw"); // $2E61E: 43 lines, ST planar
pub const logo_pal = aligned("logo_pal.dat"); // $2E5FE: 16 STE words
pub const rainbow = aligned("rainbow.dat"); // $140C8: 35 hues
pub const profile = aligned("profile.dat"); // $31022 front, $310D8 back: 91 words each
pub const scrollfont = aligned("scrollfont.raw"); // $308A2: 60 glyphs 16x16
pub const scrolltext = aligned("scrolltext.txt"); // $1FB31
pub const sine = aligned("sine.dat"); // $3118E: 256 words, +-2048
pub const kick = aligned("kick.dat"); // $1F91A: the hop's 21 impulses
pub const shadow = aligned("shadow.raw"); // $14130: 8 x 12 rows x 12 words
pub const sparkle = aligned("sparkle.dat"); // $14A30: 8 band widths
pub const drumfont = aligned("drumfont.raw"); // $60CB0: 64 glyphs 16x16
pub const ramp_scroll = aligned("ramp_scroll.dat"); // $4DD36: 280 longs
pub const ramp_drum = aligned("ramp_drum.dat"); // $4E462: 280 longs
pub const floor = aligned("floor.raw"); // $4EDCE: the floor's line patterns
pub const floor_z = aligned("floor_z.dat"); // $4ED14: 31 words
pub const floor_pal = aligned("floor_pal.dat"); // 13 x colours 0-3
pub const glint = aligned("glint.dat"); // $14A40's 66 code blocks as (offset, xor)

pub const LOGO_LINES = 43;
pub const RAMP_LEN = 280;
pub const SCROLL_GLYPHS = 60;
pub const DRUM_GLYPHS = 64;
pub const GLINT_STEPS = 0x42;

comptime {
    if (logo.len != LOGO_LINES * 160) @compileError("logo.raw is not 43 lines");
    if (logo_pal.len != 32) @compileError("logo_pal.dat is not 16 words");
    if (rainbow.len != 35 * 2) @compileError("rainbow.dat is not 35 words");
    if (profile.len != 2 * 91 * 2) @compileError("profile.dat is not 2 x 91 words");
    if (scrollfont.len != SCROLL_GLYPHS * 32) @compileError("scrollfont.raw is not 60 glyphs");
    if (sine.len != 512) @compileError("sine.dat is not 256 words");
    if (kick.len != 21 * 2) @compileError("kick.dat is not 21 words");
    if (shadow.len != 8 * 0x120) @compileError("shadow.raw is not 8 x 288 bytes");
    if (sparkle.len != 16) @compileError("sparkle.dat is not 8 words");
    if (drumfont.len != DRUM_GLYPHS * 32) @compileError("drumfont.raw is not 64 glyphs");
    if (ramp_scroll.len != RAMP_LEN * 4 or ramp_drum.len != RAMP_LEN * 4) @compileError("a ramp is not 280 longs");
    if (floor.len != 0xC300) @compileError("floor.raw is not $C300 bytes");
    if (floor_z.len != 31 * 2) @compileError("floor_z.dat is not 31 words");
    if (floor_pal.len != 13 * 8) @compileError("floor_pal.dat is not 13 x 4 words");
    // smear() ($12436) shifts by 1 or 2 px only (its keep mask, and a u5 shift)
    for (0..8) |b| if (be(sparkle, b) > 2) @compileError("sparkle.dat: a band width is not 0..2");
}

/// Where each glint step's list starts in glint.dat, in words: a list is a
/// count, then (byte offset, XOR word) pairs. Walked at compile time so a bad
/// rip is a compile error rather than an XOR past the logo (no trap in ReleaseSmall).
pub const glint_start: [GLINT_STEPS]u16 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [GLINT_STEPS]u16 = undefined;
    var o: usize = 0;
    for (&t) |*s| {
        s.* = o;
        const n: usize = be(glint, o);
        for (0..n) |k| {
            if (be(glint, o + 1 + 2 * k) / 2 >= LOGO_LINES * 80) @compileError("glint.dat: an XOR outside the logo");
        }
        o += 1 + 2 * n;
    }
    if (2 * o != glint.len) @compileError("glint.dat: the 66 lists do not fill the file");
    break :blk t;
};

/// A big-endian word of a ripped 68000 table.
pub fn be(bytes: []const u8, i: usize) u16 {
    return (@as(u16, bytes[2 * i]) << 8) | bytes[2 * i + 1];
}

pub fn beSigned(bytes: []const u8, i: usize) i16 {
    return @bitCast(be(bytes, i));
}

/// The 256-entry sine as the menu reads it ($12086: `lsr.w #8` of a 16-bit phase).
pub fn sin(phase: u16) i16 {
    return beSigned(sine, phase >> 8);
}

/// Same table by direct index (the scroller's wave builders index it by entry).
pub fn sinAt(i: usize) i16 {
    return beSigned(sine, i & 255);
}
