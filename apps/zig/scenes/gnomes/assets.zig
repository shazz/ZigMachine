// --------------------------------------------------------------------------
// The intro's rips (tools/private_tools/gnomes_rip.py over a Hatari RAM dump of
// the running original; RAM addresses in each comment), the palette layout and
// the ST register-word decoder. Tables stay in the original's big-endian-free
// form: little-endian u16 files, one ST word each.
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/gnomes/";

fn words(comptime name: []const u8) [@embedFile(DIR ++ name).len / 2]u16 {
    @setEvalBranchQuota(100_000);
    const b = @embedFile(DIR ++ name);
    var out: [b.len / 2]u16 = undefined;
    for (&out, 0..) |*w, i| w.* = @as(u16, b[2 * i]) | @as(u16, b[2 * i + 1]) << 8;
    return out;
}

// --- geometry: ST screen line L is plane row L + Y0, ST x is plane x + X0 ------
pub const X0 = 40; // the 320-px screen inside the 400-wide plane (side borders closed)
pub const Y0 = 2; // the 276 lines (top + bottom borders open) centred in 280
pub const LINES = 276;

// --- palette layout (the original splits regs 2..7 three ways down the screen;
// here each region has its own entries, so no mid-frame palette rewrite) --------
pub const C0 = 0; // colour 0: copper, the background roll + the 16 bars
pub const C1 = 1; // colour 1: copper, the static per-line ink list
pub const LOGO_PAL = [6]u16{ 0x760, 0x750, 0x740, 0x730, 0x720, 0x710 }; // $14080+4: regs 2..7 at VBL ($13D30 movem; Capstone prints $1407E, PC-relative movem is off by 2)
pub const SBOB_PAL = [14]u16{ 0x774, 0x553, 0x332, 0x321, 0x210, 0x666, 0x777, 0x755, 0x701, 0x622, 0x356, 0x377, 0x555, 0x000 }; // $10A5E: regs 2..15 ($13E46)
pub const SCROLL_PAL = [6]u16{ 0x764, 0x653, 0x542, 0x431, 0x320, 0x210 }; // $14064: regs 2..7 ($13EAA, bottom border)
pub const SBOB_LO = 18; // SpongeBob's regs 2..7 live at 18..23
pub const SCROLL_LO = 34; // the scroller's regs 2..7 live at 34..39 (regs 8..15 stay SpongeBob's: 8..15)
/// First ST line with the scroller's regs 2..7: the bottom-border handler $13EAA. Measured from
/// a capture: SpongeBob's colour 7 is still $666 on line 228 and already $210 on line 235, and no
/// colour 2..7 pixel sits on 229..234, so any line there gives the same picture.
pub const SPLIT = 230;

// --- tables -----------------------------------------------------------------
pub const BG = words("bg.bin"); // $140A0: 512 colour-0 words, rolled one a frame
pub const BAR_POS = words("barpos.bin"); // $1462C: 512 bar lines
pub const BAR_COL = words("barcol.bin"); // $1602C: 90 bar colours + the 166 words after them
pub const COL1 = words("col1.bin"); // colour 1 of each of the 276 lines (init $136EA)
pub const LOGO_DX = words("logo_dx.bin"); // $14A2C: 2816 signed x offsets, logo x = 16 + dx
pub const TTY = @embedFile(DIR ++ "tty.bin"); // $16C26: the 13 pages, 0-ended, 0 0 at the end
pub const FONT32_MAP = @embedFile(DIR ++ "font32_map.bin"); // $BEE0: char - $20 -> glyph
pub const font8 = @embedFile(DIR ++ "font8.bin"); // $18D92: 256 x 8x8, 1 B a pixel
pub const logo_raw = @embedFile(DIR ++ "logo.raw"); // $AAA0: 288 x 36
pub const sbob_raw = @embedFile(DIR ++ "sbob.raw"); // $10A7A: 144 x 158
const font32_raw = @embedFile(DIR ++ "font32.raw"); // $BF56: 48 glyphs of 32 x 25

comptime {
    if (BG.len != 512 or BAR_POS.len != 512 or BAR_COL.len != 256 or COL1.len != LINES or LOGO_DX.len != 2816)
        @compileError("gnomes: a table rip has the wrong length");
    if (logo_raw.len != 288 * 36 or sbob_raw.len != 144 * 158 or font32_raw.len != 48 * 32 * 25 or font8.len != 256 * 64)
        @compileError("gnomes: a picture rip has the wrong size");
}

/// The font with regs 2..7 moved to the scroller's entries: blitted with a plain copy.
pub const font32: [font32_raw.len]u8 = blk: {
    @setEvalBranchQuota(200_000);
    var out: [font32_raw.len]u8 = undefined;
    for (font32_raw, 0..) |p, i| out[i] = if (p >= 2 and p <= 7) p - 2 + SCROLL_LO else p;
    break :blk out;
};

// --- ST register word -> palette RGBA, machine/beam.zig stToRgba verbatim ------
fn gun(n: u16) u32 {
    return @as(u32, ((n & 7) << 1) | ((n >> 3) & 1)) * 16;
}

pub fn st(w: u16) u32 {
    return 0xFF00_0000 | (gun(w) << 16) | (gun(w >> 4) << 8) | gun(w >> 8);
}

fn decode(comptime t: anytype) [t.len]u32 {
    @setEvalBranchQuota(100_000);
    var out: [t.len]u32 = undefined;
    for (t, 0..) |w, i| out[i] = st(w);
    return out;
}

pub const BG_RGBA = decode(BG);
pub const BAR_RGBA = decode(BAR_COL);
pub const COL1_RGBA = decode(COL1);

test "the rips decode" {
    try std.testing.expectEqual(@as(u32, 0xFF00_0000), st(0));
    try std.testing.expectEqual(@as(u32, 0xFFE0_E0E0), st(0x777));
}
