// --------------------------------------------------------------------------
// What was ripped out of stcs_3.prg, by tools/private_tools/stcs_css3_assets.py:
// the start-of-intro RAM that the reference model's boot_ram() rebuilds from the
// program alone (the HARTMANNS EASYPACKER wrapper undone, TEXT+DATA relocated,
// the init at $54..$1D8 replayed), sliced into the regions the effects touch.
// Addresses are TEXT offsets of the unpacked program. All of it is big-endian
// 68000 data and stays that way: the effects work on ST screen memory.
// --------------------------------------------------------------------------
const std = @import("std");

const DIR = "../../assets/screens/stcs_css3/";

/// The ST screen at the start of the star release ($1F2): pic1 (ByteRun1,
/// DATA $4100) with the four STCS letters already lifted off it by $A7C.
pub const screen = @embedFile(DIR ++ "screen.bin");
/// $E720: the lifted letters S, T, C, S, 17 words each at a $22 stride.
pub const letters = @embedFile(DIR ++ "letters.bin");
/// $16E24: pic2 lines 0..111, the scroller font (every glyph the scroller
/// reads lies there; lines 112.. are the scroll buffers' at run time).
pub const font = @embedFile(DIR ++ "font.bin");
/// $D3FE..$D668: the top palette, the 16 Timer B blocks, the 28-word bar
/// ring at $D620 and the 17 Timer B event counts at $D658.
pub const raster = @embedFile(DIR ++ "raster.bin");
/// $5E6A and $992A: the letters' path, one byte a step (Billy Octet's).
pub const path_x = @embedFile(DIR ++ "path_x.bin");
pub const path_y = @embedFile(DIR ++ "path_y.bin");
/// $D6AA: 3335 character codes then $3F (wrap). $F0 = pause.
pub const text = @embedFile(DIR ++ "text.bin");
/// The four scroll buffers' 19 lines at start: pic2 is decoded after the BSS
/// clear, so its tail sits in $1B452 and $1DE52 until the scroller shifts it
/// out (and line 18 of each buffer, which the shift never writes, keeps it).
pub const scrollbuf = @embedFile(DIR ++ "scrollbuf.bin");

pub const SCREEN_BYTES: usize = 32000;
pub const LINE: usize = 160;
pub const LETTER_WORDS: usize = 17;
pub const PATH_LEN: usize = 15040;
pub const SCROLL_LINES: usize = 19;
pub const BUF_BYTES: usize = SCROLL_LINES * LINE;

pub const TEXT_WRAP: u8 = 0x3F;
pub const TEXT_PAUSE: u8 = 0xF0;
/// $17C: 60 glyph addresses, 10 a row at 16 bytes, rows 17 lines ($AA0) apart.
pub const GLYPHS: usize = 60;

comptime {
    std.debug.assert(screen.len == SCREEN_BYTES);
    std.debug.assert(letters.len == 4 * LETTER_WORDS * 2);
    std.debug.assert(font.len == 112 * LINE);
    std.debug.assert(raster.len == 0xD669 - 0xD3FE);
    std.debug.assert(path_x.len == PATH_LEN and path_y.len == PATH_LEN);
    std.debug.assert(scrollbuf.len == 4 * BUF_BYTES);
    // every code is a glyph, the wrap or the pause: the table is never overrun
    @setEvalBranchQuota(20_000);
    for (text) |c| std.debug.assert(c < GLYPHS or c == TEXT_WRAP or c == TEXT_PAUSE);
    std.debug.assert(text[text.len - 1] == TEXT_WRAP);
    std.debug.assert(text[0] != TEXT_PAUSE and text[0] != TEXT_WRAP);
}

pub fn glyph(code: u8) u32 {
    const c: u32 = code;
    return (c / 10) * 0xAA0 + (c % 10) * 16;
}

pub fn be16(b: []const u8, a: usize) u16 {
    return std.mem.readInt(u16, b[a..][0..2], .big);
}
pub fn be32(b: []const u8, a: usize) u32 {
    return std.mem.readInt(u32, b[a..][0..4], .big);
}
pub fn put16(b: []u8, a: usize, v: u16) void {
    std.mem.writeInt(u16, b[a..][0..2], v, .big);
}
pub fn put32(b: []u8, a: usize, v: u32) void {
    std.mem.writeInt(u32, b[a..][0..4], v, .big);
}
