// --------------------------------------------------------------------------
// F1's scroller and its colours (ric_model.py: scroller, scroll_colours,
// bars). The scroller is plane 0 of the top 59 lines, moved a word left each
// VBL; the colours are the Timer B table at $47524 (colour 0, colour 1 per
// line), which the VBL rewrites: colour 1 of the scroller's lines (a rainbow
// walked through a list of tables) and colour 0 of six 11-line bars.
// --------------------------------------------------------------------------
const st = @import("st.zig");

pub const TABLE: u32 = 0x47524; // Timer B: (colour 0, colour 1) a line
pub const SCROLL_LIST: u32 = 0x4790E; // the rainbow tables, from $31A0
const SCROLL_LINES = 59;
const TRIPLES: u32 = 0x78270; // each screen's (font var, text var, counter)
const TEXT_FIRST: u32 = 0x449A;

/// $129E: each screen keeps its own place in the text (its triple at $316C..).
pub fn scroller(r: *const st.Ram) void {
    var a0 = r.l(TRIPLES);
    const font_var = r.l(a0);
    const text_var = r.l(a0 + 4);
    const counter = r.l(a0 + 8);
    a0 += 12;
    r.sl(TRIPLES, if (r.l(a0) == 0) 0x316C else a0);
    var text = r.l(text_var);
    var d6: u8 = r.b(counter);
    if (d6 == 0) {
        text += 1;
        if (r.b(text) == 0) text = TEXT_FIRST;
        r.sl(text_var, text);
        d6 = width(r.b(text));
    }
    r.sb(counter, d6 -% 1);
    const column = glyph(r, r.b(text), font_var, d6);
    shift(r, r.l(0x47936), column);
}

/// Narrow letters take fewer 4-pixel columns.
fn width(c: u8) u8 {
    return switch (c) {
        0x49, 0x6A => 2,
        0x69, 0x68 => 3,
        else => 4,
    };
}

/// The column of letter `c` that comes in now, in the font the screen uses.
fn glyph(r: *const st.Ram, c0: u8, font_var: u32, d6: u8) u32 {
    const c: u8 = if (c0 == 0x67) 0x60 else c0;
    const k: u32 = (c -% 0x41) << 1; // byte arithmetic, as add.b
    const at = @as(i32, @as(i16, @bitCast(r.w(0x4446 + (k & 0xFF)))));
    const back: u32 = (@as(u32, d6) << 1) & 0xFF;
    return (r.l(font_var) +% @as(u32, @bitCast(at))) -% back;
}

fn shift(r: *const st.Ram, scr: u32, column: u32) void {
    for (0..SCROLL_LINES) |yi| {
        const y: u32 = @intCast(yi);
        const row = scr + 160 * y;
        var k: u32 = 0;
        while (k < 19) : (k += 1) r.sw(row + 8 * k, r.w(row + 8 * k + 8));
        r.sw(row + 0x98, r.w(column + 8 * y));
    }
}

/// $13CC: colour 1 of lines 0..58 from the next rainbow table.
pub fn colours(r: *const st.Ram) void {
    var a0 = r.l(SCROLL_LIST);
    const a1 = r.l(a0);
    a0 += 4;
    r.sl(SCROLL_LIST, if (r.l(a0) == 0xFFFFFFFF) 0x31A0 else a0);
    for (0..SCROLL_LINES) |yi| {
        const y: u32 = @intCast(yi);
        r.sw(TABLE + 2 + 4 * y, r.w(a1 + 6 + 2 * y));
    }
}

/// $1400: colour 0 of the six bars (lines 0, 20, 40, 60, 80, 99 on) from
/// the next table of the list at $4442.
pub fn bars(r: *const st.Ram) void {
    var a0 = r.l(0x4442);
    const a5 = r.l(a0);
    a0 += 4;
    r.sl(0x4442, if (r.l(a0) == 0) 0x35A8 else a0);
    for (0..11) |ki| {
        const k: u32 = @intCast(ki);
        const v = r.w(a5 + 2 * k);
        for ([_]u32{ 0, 20, 40, 60, 80, 99 }) |first| r.sw(TABLE + 4 * (first + k), v);
    }
}
