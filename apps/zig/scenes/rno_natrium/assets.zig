// --------------------------------------------------------------------------
// NATRIUM assets, ripped out of the program's own TEXT (load base $AA9A) by
// tools/private_tools/rno_natrium_assets.py, which checks each one against the
// reverse-engineering artefacts that were verified on Hatari RAM snapshots.
//
// Only what the program generates from a SIMPLE, exact rule is built here at
// comptime instead of embedded: the bit-doubling LUTs ($C348) and the
// reciprocal table ($C454). Everything else is the original's data.
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/rno_natrium/";

pub const tunnel_map = @embedFile(DIR ++ "tunnel_map.bin"); // $144C8, 160x100 words as stored
pub const dot_tex = @embedFile(DIR ++ "dot_tex.bin"); // $241C8, 32 x 16 bytes, bit 0
pub const rno_rows = @embedFile(DIR ++ "rno_rows.bin"); // RNO ILBM body, rows 72..127
pub const natrium_rows = @embedFile(DIR ++ "natrium_rows.bin"); // NATRIUM ILBM body, rows 72..127
pub const girl_grey = @embedFile(DIR ++ "girl_grey.bin"); // $37F54 body, 320x200x4
pub const girl_recline = @embedFile(DIR ++ "girl_recline.bin"); // $3FCD4 body
pub const girl_red = @embedFile(DIR ++ "girl_red.bin"); // $47A54 body
pub const tex_skin = @embedFile(DIR ++ "tex_skin.bin"); // $201C8, 128x128, 0..6
pub const tex_face = @embedFile(DIR ++ "tex_face.bin"); // $1C1C8, 128x128, 0..6
pub const chunky_lut = @embedFile(DIR ++ "chunky_lut.bin"); // $56492, 4 x 8 words
pub const env_tex = @embedFile(DIR ++ "env_tex.bin"); // $52492, 128x128, 0..12
pub const dither = @embedFile(DIR ++ "dither.bin"); // $EE1A, 16 x 4 bytes
pub const cube = @embedFile(DIR ++ "cube.bin"); // $14128
pub const prism = @embedFile(DIR ++ "prism.bin"); // $13F38
pub const chrome = @embedFile(DIR ++ "chrome.bin"); // $243C8+$8C, 512x64x4 ILBM body
pub const greet = @embedFile(DIR ++ "greet.bin"); // $4F7D4+$4A, 224x128x1
pub const strip = @embedFile(DIR ++ "strip.bin"); // $5061E+$74, 320x48x4 ILBM body
pub const sin_tab = @embedFile(DIR ++ "sin.bin"); // $CA72, 1280 s16 (cos at +256)
pub const palettes = @embedFile(DIR ++ "palettes.bin"); // $14360..$1449F

/// The palette blocks, by their address in the original.
pub const PAL_BLACK: u32 = 0x14360;
pub const PAL_WHITE: u32 = 0x14380; // colour 0 black, 1..15 white
pub const PAL_ROTO: u32 = 0x143A0;
pub const PAL_CUBE: u32 = 0x143C0;
pub const PAL_TUNNEL: u32 = 0x143E0;
pub const PAL_BOX: u32 = 0x14400;
pub const PAL_TWIST: u32 = 0x14420; // 32 words: the fade slides a 16-word window along it
pub const PAL_CREDITS: u32 = 0x14460;
pub const PAL_PRISM: u32 = 0x14480;

pub const PICTURE = 32000;
pub const LOGO_TOP = 72; // the reveals only ever touch rows 72..127
pub const LOGO_ROWS = 56;

comptime {
    if (tunnel_map.len != 32000) @compileError("tunnel_map.bin is not 160x100 words");
    if (dot_tex.len != 512) @compileError("dot_tex.bin is not 32x16");
    if (rno_rows.len != LOGO_ROWS * 160 or natrium_rows.len != LOGO_ROWS * 160) @compileError("logo rows");
    if (girl_grey.len != PICTURE or girl_recline.len != PICTURE or girl_red.len != PICTURE) @compileError("pictures");
    if (tex_skin.len != 0x4000 or tex_face.len != 0x4000 or env_tex.len != 0x4000) @compileError("textures");
    if (chunky_lut.len != 64 or dither.len != 64) @compileError("c2p tables");
    if (cube.len != 568 or prism.len != 496) @compileError("objects");
    if (chrome.len != 16384 or greet.len != 3584 or strip.len != 7680) @compileError("twister/credits art");
    if (sin_tab.len != 2560) @compileError("sin.bin is not 1280 words");
    if (palettes.len != 0x140) @compileError("palettes.bin is not $14360..$1449F");
}

pub inline fn be16(b: []const u8, i: usize) u16 {
    return (@as(u16, b[2 * i]) << 8) | b[2 * i + 1];
}

/// SIN[i]: amplitude 256, period 1024, cos(i) = SIN[i + 256].
pub inline fn sin(i: usize) i32 {
    return @as(i16, @bitCast(be16(sin_tab, i)));
}

/// Entry `i` of the 16-word palette at `addr` (the fade reads up to $14460).
pub fn pal(addr: u32, i: usize) u16 {
    return be16(palettes, (addr - PAL_BLACK) / 2 + i);
}

/// $B751A (built at $C348): every bit of a byte doubled, bit 7 -> pixels 0-1.
pub const pix_double: [256]u16 = blk: {
    @setEvalBranchQuota(10000);
    var t: [256]u16 = undefined;
    for (0..256) |n| {
        var v: u16 = 0;
        for (0..8) |k| {
            if ((n >> (7 - k)) & 1 != 0) v |= @as(u16, 0xC000) >> (2 * k);
        }
        t[n] = v;
    }
    break :blk t;
};

/// $B771A: the byte bit-REVERSED, then doubled, then inverted: the bottom half
/// of the dot tunnel is the top half turned 180 degrees and colour-inverted.
pub const pix_mirror: [256]u16 = blk: {
    @setEvalBranchQuota(10000);
    var t: [256]u16 = undefined;
    for (0..256) |n| {
        var v: u16 = 0;
        for (0..8) |k| {
            if ((n >> k) & 1 != 0) v |= @as(u16, 0xC000) >> (2 * k);
        }
        t[n] = ~v;
    }
    break :blk t;
};

/// $13D38 (built at $C454): [0] = $4000, [1] = $7FFF, [n] = $8000 divs n.
pub const recip: [256]i32 = blk: {
    @setEvalBranchQuota(10000);
    var t: [256]i32 = undefined;
    t[0] = 0x4000;
    t[1] = 0x7FFF;
    for (2..256) |n| t[n] = @divTrunc(0x8000, @as(i32, n));
    break :blk t;
};
