// --------------------------------------------------------------------------
// The demo's data, depacked (its ZX0 v2 at $22848, LZO1X at $226DC) out of the
// UPX-unpacked 0PXL0REG.PRG by tools/private_tools/dhs_0pxl0reg_assets.py,
// through the same decoders the reference model was verified with. Words are
// little-endian here (core.le16) unless noted. Addresses: where the program
// keeps the packed stream (relocated to $10000).
// --------------------------------------------------------------------------
const DIR = "../../assets/screens/dhs_0pxl0reg/";

pub const p1_logo = @embedFile(DIR ++ "p1_logo.bin"); // $42EE4: 270 x 52 logo pixels 0..11
pub const p2_rows = @embedFile(DIR ++ "p2_rows.bin"); // $22A84/$22AC6/$22B8E: rows A 200, B 67, C 27 x 32 nibbles
pub const tr_cards = @embedFile(DIR ++ "tr_cards.bin"); // $6926E/$6937A/$69438/$694FC: 4 x 144 x 52 nibbles
pub const p5_map = @embedFile(DIR ++ "p5_map.bin"); // $3C682+$436: 128 x 128 nibble map
pub const p6_map = @embedFile(DIR ++ "p6_map.bin"); // $26DEA+$436: 128 x 128, pixel bytes doubled
pub const p6_sets = @embedFile(DIR ++ "p6_sets.bin"); // $26C4C: 60 x 13 colour words
pub const p7_anim = @embedFile(DIR ++ "p7_anim.bin"); // $27464 LZO: 216 x 25 x 48 nibbles, two a byte (high first)
pub const p8_logo = @embedFile(DIR ++ "p8_logo.bin"); // $6090E: 67 x 672 colour words (+64 zero words)
pub const p9_images = @embedFile(DIR ++ "p9_images.bin"); // $26102.. : 5 x 33 x 66 fade-level bytes, column-major
pub const p9_tex = @embedFile(DIR ++ "p9_tex.bin"); // $25AC4: 126 x 66 texture bytes
pub const p10_strip = @embedFile(DIR ++ "p10_strip.bin"); // $43CEC: 50 x 258 + 300 generated-code words
pub const p10_region = @embedFile(DIR ++ "p10_region.bin"); // $506BE..: text, glyph map, palette, font (big-endian)
pub const p10_wob = @embedFile(DIR ++ "p10_wob.bin"); // $6010C: 1024 signed words
pub const p11_map = @embedFile(DIR ++ "p11_map.bin"); // $3E3B6: 70 x 96 words
pub const p11_tex = @embedFile(DIR ++ "p11_tex.bin"); // $4033E: 64 x 64 texels as register numbers
pub const p11_scr = @embedFile(DIR ++ "p11_scr.bin"); // $40A9E: 1050 x 16 scroller cells as register numbers
pub const p12_seed = @embedFile(DIR ++ "p12_seed.bin"); // $231B4: fire seed rows
pub const p12_txt = @embedFile(DIR ++ "p12_txt.bin"); // $2326E: 1-bit text bitmap
pub const p12_heat0 = @embedFile(DIR ++ "p12_heat0.bin"); // heat buffer at init: $22EDC at +$F0, P11's opcodes past $8A0
pub const p13_tex = @embedFile(DIR ++ "p13_tex.bin"); // $40FD8: 64 x 64 texels as register numbers
pub const p13_strips = @embedFile(DIR ++ "p13_strips.bin"); // the three text strips as built at $1CBC6
pub const p14_mem = @embedFile(DIR ++ "p14_mem.bin"); // $B50EE..: 26 line-routine copies, then the $3CFA8 texture
pub const p15_img = @embedFile(DIR ++ "p15_img.bin"); // $432B4: 128 x 52 nibbles
pub const p16_opc = @embedFile(DIR ++ "p16_opc.bin"); // $3AD16: 64 x 64 map as register numbers
pub const p16_wt = @embedFile(DIR ++ "p16_wt.bin"); // $3AF66: 96-wide word table
pub const p17_text = @embedFile(DIR ++ "p17_text.bin"); // $67076+$672CA+$6766E: 8 bytes a text row
pub const p17_a5 = @embedFile(DIR ++ "p17_a5.bin"); // DATA $680A0: 512 line colours (d0)
pub const p17_a4 = @embedFile(DIR ++ "p17_a4.bin"); // DATA $684A0 + $68734 twice: line colours (d1)

comptime {
    if (p1_logo.len != 270 * 52 or p2_rows.len != 294 * 32 or tr_cards.len != 4 * 144 * 52) @compileError("dhs assets: P1/P2/TR size");
    if (p7_anim.len != 216 * 25 * 48 / 2 or p8_logo.len != (67 * 672 + 64) * 2) @compileError("dhs assets: P7/P8 size");
    if (p9_images.len != 5 * 2178 or p9_tex.len != 126 * 66 or p10_strip.len != 13200 * 2) @compileError("dhs assets: P9/P10 size");
    if (p11_scr.len != 1050 * 16 or p12_heat0.len != 0x8A0 + 256 or p15_img.len != 128 * 52) @compileError("dhs assets: P11/P12/P15 size");
    if (p17_a5.len != 1024 or p16_opc.len != 4096 or p6_sets.len != 60 * 26) @compileError("dhs assets: P6/P16/P17 size");
}

// The kernels index 14-word register files with these bytes, and P11 / P13
// with `n - 1` on a u8: a byte out of range would read past the palette (or
// wrap) silently in ReleaseSmall. Proven here instead of clamped per cell.
comptime {
    @setEvalBranchQuota(200_000);
    for (.{ p11_tex, p11_scr, p13_tex, p13_strips }) |b| if (!within(b, 1, 13)) @compileError("dhs assets: a P11/P13 register number is not d1..a5");
    if (!within(p16_opc, 0, 13)) @compileError("dhs assets: a P16 register number is past a5");
    if (!within(tr_cards, 0, 12)) @compileError("dhs assets: a TR card nibble is past its 13-word palette");
}

fn within(comptime b: []const u8, comptime lo: u8, comptime hi: u8) bool {
    for (b) |v| if (v < lo or v > hi) return false;
    return true;
}
