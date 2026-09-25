// --------------------------------------------------------------------------
// What was ripped out of SODIUM (SOD_UNP.PRG, the UPX-unpacked program), by
// tools/private_tools/rno_sodium_assets.py. Addresses are TEXT offsets
// (file offset - 28); every file is a byte-for-byte slice of the program, or
// of its RAM after init where init converted it (the ILBM pictures).
//
// All of it is big-endian 68000 data and stays that way: the effects write it
// into ST screen memory exactly as the original did (st.zig).
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/rno_sodium/";

/// $079A: 1280 signed words, amplitude 256, period 1024. NOT exactly
/// round(256 sin) — it is off by one here and there — so it is shipped, never
/// regenerated. Entries 1024.. repeat 0.., which is how $099A reads as cos.
const sine = @embedFile(DIR ++ "sine.bin");
/// ILBM #2's BODY ($13F6E): PO·RNO, 256x256, one bitplane, 32 bytes a row.
pub const porno = @embedFile(DIR ++ "porno.bin");
/// ILBM #3's BODY ($15FE2): 512x16, 4 planes, 256 bytes a row, glyph g = byte g.
pub const font = @embedFile(DIR ++ "font.bin");
/// $254E: three 240-character pages, 12 rows of 20.
pub const text_pages = @embedFile(DIR ++ "text_pages.bin");
/// $1AE2 / $1CC2: 240 words each, the byte offset of every character cell.
const text_x = @embedFile(DIR ++ "text_x.bin");
const text_y = @embedFile(DIR ++ "text_y.bin");
/// $16FE2: the prism texture, 64x64 chunky bytes 0..7 (the raw tail of TEXT).
pub const prism_tex = @embedFile(DIR ++ "prism_tex.bin");
/// $16B6: 33 rows of 8, the fog/shade ramp from far (all 7) to near (identity).
pub const prism_shade = @embedFile(DIR ++ "prism_shade.bin");
/// ILBM #0 converted at init to ST interleave ($5E0E4): 192x256, 96 bytes a row.
pub const pic0 = @embedFile(DIR ++ "pic0.bin");
/// ILBM #1 converted at init ($640E4): the eye + RNO picture, a whole screen.
pub const pic1 = @embedFile(DIR ++ "pic1.bin");
/// $1F42 onwards as RAM holds it after init: the curtain table (inverted by
/// $0620) followed by the program's own bytes, which the curtain reads on the
/// one frame its row list is stale (curtain.zig).
pub const curtain_tail = @embedFile(DIR ++ "curtain_tail.bin");
/// $1EA2..$1F41: the five 16-word palettes, in address order.
const palettes = @embedFile(DIR ++ "palettes.bin");

pub const CURTAIN_ROWS: usize = 64;
pub const CURTAIN_ROW_BYTES: usize = 24; // 192 px, one plane
pub const CURTAIN_TABLE: usize = CURTAIN_ROWS * CURTAIN_ROW_BYTES;
pub const TEXT_CHARS: usize = 240;
pub const PIC0_ROW: usize = 96;

/// The five palette blocks, named for the address movem.l reads them from.
pub const Palette = enum(u3) {
    init = 0, // $1EA2: black, then 15 x $777
    distort = 1, // $1EC2
    porno = 2, // $1EE2: popcount greys, the ghost trail's palette
    eye = 3, // $1F02: eye picture, curtain and text
    prism = 4, // $1F22
};

pub fn paletteWord(p: Palette, i: usize) u16 {
    return be16(palettes, @as(usize, @intFromEnum(p)) * 32 + i * 2);
}

/// sw(a): the sine word at BYTE offset `a` of $079A, as every walker reads it.
pub fn sw(a: u32) i32 {
    return @as(i16, @bitCast(be16(sine, a)));
}

/// The entry at WORD index `i` (0..1279), for the $099A cos reads.
pub fn sineEntry(i: usize) i32 {
    return @as(i16, @bitCast(be16(sine, i * 2)));
}

/// The walkers' seeds: `mulu.w #k` / `muls.w #k` of the frame word, and.w #$7FE.
pub fn seedU(f: u16, k: u32) u32 {
    return (@as(u32, f) * k) & 0x7FE;
}
pub fn seedS(f: u16, k: i32) u32 {
    const p = @as(i32, @as(i16, @bitCast(f))) * k;
    return @as(u32, @bitCast(p)) & 0x7FE;
}
/// A walker's step: add, then and.w #$7FE — which drops the low bit of an odd
/// add. Reproduced literally, never converted to entries first.
pub fn step(a: u32, k: u32) u32 {
    return (a + k) & 0x7FE;
}

pub fn textX(k: usize) usize {
    return be16(text_x, k * 2);
}
pub fn textY(k: usize) usize {
    return be16(text_y, k * 2);
}

pub fn be16(b: []const u8, off: usize) u16 {
    return std.mem.readInt(u16, b[off..][0..2], .big);
}

comptime {
    if (sine.len != 1280 * 2) @compileError("sine.bin is not 1280 words");
    if (porno.len != 256 * 32) @compileError("porno.bin is not 256 rows of 32 bytes");
    if (font.len != 16 * 256) @compileError("font.bin is not 16 rows of 256 bytes");
    if (text_pages.len != 3 * TEXT_CHARS) @compileError("text_pages.bin is not 3 pages");
    if (text_x.len != TEXT_CHARS * 2 or text_y.len != TEXT_CHARS * 2) @compileError("a text position table is not 240 words");
    if (prism_tex.len != 64 * 64) @compileError("prism_tex.bin is not 64x64");
    if (prism_shade.len != 33 * 8) @compileError("prism_shade.bin is not 33x8");
    if (pic0.len != 256 * PIC0_ROW) @compileError("pic0.bin is not 256 rows of 96 bytes");
    if (pic1.len != 32000) @compileError("pic1.bin is not one ST screen");
    if (palettes.len != 5 * 32) @compileError("palettes.bin is not five palettes");
    // Every walker's range rests on |S[i]| <= 256: the curtain's sum + $200
    // is never negative (its @intCast), and the prism's edge lines stay in
    // 8..192 (its list index). ReleaseSmall would not trap on either.
    @setEvalBranchQuota(10_000);
    for (0..1280) |i| {
        const v = sineEntry(i);
        if (v < -256 or v > 256) @compileError("sine.bin leaves -256..256");
    }
    // The farthest a stale row list can point: the distorter's row 255 * 96.
    if (curtain_tail.len != 255 * PIC0_ROW + CURTAIN_ROW_BYTES) @compileError("curtain_tail.bin is short");
}
