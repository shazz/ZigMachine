// --------------------------------------------------------------------------
// HMDFAC's rips (hmdfac.zig lists each one's depacked.bin offset) and the ST
// register-word decoder. The word tables are decoded to u16 arrays at comptime.
// --------------------------------------------------------------------------
const DIR = "../../assets/screens/hmdfac/";
pub const logo_data = @embedFile(DIR ++ "logo.raw"); // 320x249 chunky indices
pub const band_a_data = @embedFile(DIR ++ "band_a.raw"); // 320x46
pub const band_b_data = @embedFile(DIR ++ "band_b.raw"); // 320x51
const sine_data = @embedFile(DIR ++ "sine.blob"); // 720 LE words
const queue_data = @embedFile(DIR ++ "queue.raw"); // 360 x 2 LE words
const rows_data = @embedFile(DIR ++ "rows.raw"); // 5040 LE words
const wave_data = @embedFile(DIR ++ "wave.raw"); // 189 LE words
const boot_pal_data = @embedFile(DIR ++ "boot_pal.raw"); // 16 LE words
const art_pal_data = @embedFile(DIR ++ "art_pal.raw"); // 16 LE words
const pal4_data = @embedFile(DIR ++ "pal4.raw"); // 16 LE words
const band_pal_data = @embedFile(DIR ++ "band_pal.raw"); // 16 LE words
const laser_data = @embedFile(DIR ++ "laser.raw"); // 124 LE words
const bob_data = @embedFile(DIR ++ "bob.raw"); // 192 LE words
pub const text_data = @embedFile(DIR ++ "text.raw"); // 2105 chars + 0xFF
pub const font = @embedFile(DIR ++ "font_machine.bin"); // $148e2: 50 glyphs x 64 B
pub const charmap = @embedFile(DIR ++ "charmap.bin"); // $144a8: text byte -> glyph

comptime {
    if (logo_data.len != 320 * 249) @compileError("logo.raw must be 320x249 chunky");
    if (band_a_data.len != 320 * 46) @compileError("band_a.raw must be 320x46");
    if (band_b_data.len != 320 * 51) @compileError("band_b.raw must be 320x51");
    if (sine_data.len != 720 * 2) @compileError("sine.blob must be 720 words");
    if (queue_data.len != 360 * 2 * 2) @compileError("queue.raw must be 360 pairs");
    if (rows_data.len != 5040 * 2) @compileError("rows.raw must be 5040 words");
    if (wave_data.len != 189 * 2) @compileError("wave.raw must be 189 words");
    if (laser_data.len != LASER_N * 2 or bob_data.len != BOB_N * 2) @compileError("laser.raw / bob.raw sizes");
    if (boot_pal_data.len != 32 or art_pal_data.len != 32 or pal4_data.len != 32 or band_pal_data.len != 32)
        @compileError("palette rips must be 16 words");
    if (text_data.len != 2105 + 1) @compileError("text.raw must be 2105 chars + terminator");
    if (font.len != 50 * 64 or charmap.len != 256) @compileError("font_machine.bin / charmap.bin sizes");
}

pub const TEXT_LEN = 2105;
pub const ROWS_N = 5040;
pub const WAVE_N = 189;
pub const QUEUE_PAIRS = 360;
pub const LASER_N = 124;
pub const BOB_N = 192;

// --- geometry: the 320x249 plate at (40,15) of the 400x280 plane ----------
pub const ART_X = 40;
pub const ART_Y = 15;
pub const ART_W = 320;
pub const ART_H = 249;
pub const BAND_A_Y = 194; // $7940 page offset / 160 B rows
pub const BAND_A_H = 46;
pub const BAND_B_Y = 199; // $7c60 page offset / 160 B rows

// --- ST register word -> RGBA (machine/beam.zig stToRgba, verbatim) -----------
fn gun(nibble: u16) u32 {
    const level: u32 = ((nibble & 7) << 1) | ((nibble >> 3) & 1);
    return level * 16;
}

pub fn st(word: u16) u32 {
    return 0xFF00_0000 | (gun(word) << 16) | (gun(word >> 4) << 8) | gun(word >> 8);
}

/// A little-endian word table decoded at comptime into a u16 array. NOT read
/// in place: an @embedFile has byte alignment, and a u16 load at an odd
/// address traps on the board (~700 cycles; phase 4's walk hit 151 a frame).
fn words(comptime data: []const u8) [data.len / 2]u16 {
    @setEvalBranchQuota(100_000);
    var out: [data.len / 2]u16 = undefined;
    for (&out, 0..) |*w, i| w.* = @as(u16, data[2 * i]) | (@as(u16, data[2 * i + 1]) << 8);
    return out;
}

pub const sine: [720]u16 = words(sine_data); // cos 0..359, then sin
pub const queue: [720]u16 = words(queue_data); // 360 (sy, sx) pairs
pub const rows: [ROWS_N]u16 = words(rows_data);
pub const wave: [WAVE_N]u16 = words(wave_data);
pub const boot_pal: [16]u16 = words(boot_pal_data);
pub const art_pal: [16]u16 = words(art_pal_data);
pub const pal4: [16]u16 = words(pal4_data);
pub const band_pal: [16]u16 = words(band_pal_data);
pub const laser: [LASER_N]u16 = words(laser_data);
pub const bob: [BOB_N]u16 = words(bob_data);
