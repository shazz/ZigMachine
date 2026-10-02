// --------------------------------------------------------------------------
// F1's start, before its figure choice ($800..$A3E): the title picture onto
// its screen, the scroller font built as columns of three plane words (59
// lines each) and three copies of it, each 4 pixels further on (roxl through
// the whole copy with the X flag carried across the passes).
// prototypes/naos_nitrowave_re/ric_pre.py is the same, = Hatari's RAM at the
// choice to the byte.
// --------------------------------------------------------------------------
const st = @import("st.zig");

pub const TITLE: u32 = 0x13BC0; // a PI1: palette at +2, picture at +$22
pub const TITLE_SCREEN: u32 = 0x6E700; // (($6E66E & ~$FF) + $100)
pub const FONTS = [4]u32{ 0x346C4, 0x3925C, 0x3DDF4, 0x4298C };
const FONT_BYTES: u32 = 4 * 0x12E6;
const COLUMN_LINES = 0x3B;

pub fn run(r: *const st.Ram) void {
    r.sl(0x4791C, TITLE_SCREEN); // $85E: the background screen
    r.cp(TITLE_SCREEN, TITLE + 0x22, 32000);
    font(r);
    var x: u16 = 0;
    for (FONTS[0..3], FONTS[1..]) |src, dst| {
        r.cp(dst, src, FONT_BYTES);
        for (0..4) |_| x = roxl(r, dst, x);
    }
}

/// $894..$988: the letters' columns from the sheets at $FB38 and $12950.
fn font(r: *const st.Ram) void {
    var a1 = FONTS[0];
    for (0..5) |row| {
        for (0..6) |c| a1 = column(r, a1, 0xFB38 + 0x938 * @as(u32, @intCast(row)) + 6 * @as(u32, @intCast(c)), 3);
    }
    a1 = column(r, a1, 0xFB38 + 0x984, 1);
    a1 = column(r, a1, 0xFB38 + 0x12BC, 1);
    for (0..6) |c| a1 = column(r, a1, 0x12950 + 6 * @as(u32, @intCast(c)), 3);
    for (0..3) |c| a1 = column(r, a1, 0x12950 + 0x938 + 6 * @as(u32, @intCast(c)), 3);
    var a0 = FONTS[0] + 0xEC0; // $972: one column doubled
    for (0..COLUMN_LINES) |_| {
        r.sl(a0 + 4, r.l(a0));
        a0 += 8;
    }
}

/// One column: `words` plane words a line into planes 1.. of a group.
fn column(r: *const st.Ram, dst: u32, src0: u32, words: u32) u32 {
    var a1 = dst;
    var src = src0;
    for (0..COLUMN_LINES) |_| {
        var k: u32 = 0;
        while (k < words) : (k += 1) r.sw(a1 + 2 + 2 * k, r.w(src + 2 * k));
        a1 += 8;
        src += 0x28;
    }
    return a1;
}

/// roxl.w -(a1) over the copy, from its end: one pixel left.
fn roxl(r: *const st.Ram, dst: u32, x0: u16) u16 {
    var x = x0;
    var a = dst + FONT_BYTES;
    while (a > dst) {
        a -= 2;
        const v = r.w(a);
        r.sw(a, (v << 1) | x);
        x = v >> 15;
    }
    return x;
}
