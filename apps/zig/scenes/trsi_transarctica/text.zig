// --------------------------------------------------------------------------
// A text page into the 320x136 window: $570 fills it with 128 + hump value
// (plane 7 set, planes 0-6 = the bg map), then $5C2 writes every 8x8 cell:
// cell lines 0-6 keep a pixel only where the glyph bit is set (plane 7 :=
// glyph row, planes 0-6 &= glyph row), line 7 is cleared. So ink = 128+bg,
// paper = 0. The pages are centred by spaces in the data; the code does not
// centre anything.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub const COLS = 40;
pub const ROWS = 17;
const CR = 0x0D;
const END_PAGE = 0xFF;

/// Byte offset of each page in the text: the pointer at $B74 walks them in
/// turn and a $00 wraps it back to the first ($B78).
const pages = findPages();
pub const PAGES = pages.len;

fn findPages() [6]u32 {
    @setEvalBranchQuota(20000);
    var out: [6]u32 = undefined;
    var n: usize = 0;
    var start: u32 = 0;
    for (assets.text, 0..) |ch, i| {
        if (ch == 0 and n == out.len and i == assets.text.len - 1) return out;
        if (ch == END_PAGE) {
            out[n] = start;
            n += 1;
            start = i + 1;
            continue;
        }
        if (ch != CR and (ch < 0x20 or slotOf(ch) >= assets.FONT_SLOTS)) @compileError("text byte outside the font");
    }
    @compileError("text.bin must be six $FF-terminated pages and a $00");
}

/// $5F6..$616: below $61 set A (space..Z); $61..$A0 set B, the small caps
/// that lowercase is drawn with; from $A1 set B again, unused by the text.
fn slotOf(ch: u8) u32 {
    return if (ch < 0x61) ch - 0x20 else if (ch < 0xA1) ch - 0x40 else ch - 0xA0;
}
fn glyphRow(ch: u8, r: usize) u8 {
    const set_b: usize = @intFromBool(ch >= 0x61);
    return assets.font[slotOf(ch) * 14 + 2 * r + set_b];
}

/// Draw page `page` (0..5) into the window at `dst` (its top-left pixel).
pub fn draw(dst: [*]u8, stride: usize, page: usize) void {
    for (0..assets.BG_H) |y| {
        const row = dst + y * stride;
        const bg = assets.bg_map[y * assets.W ..][0..assets.W];
        for (row[0..assets.W], bg) |*px, v| px.* = 128 + v;
    }
    var row: usize = 0;
    var col: usize = 0;
    var i: usize = pages[page];
    while (assets.text[i] != END_PAGE) : (i += 1) {
        const ch = assets.text[i];
        if (ch == CR) {
            row += 1;
            col = 0;
            continue;
        }
        if (row < ROWS) cell(dst + row * 8 * stride + col * 8, stride, ch);
        col += 1;
    }
}

fn cell(dst: [*]u8, stride: usize, ch: u8) void {
    for (0..8) |r| {
        const bits: u8 = if (r < 7) glyphRow(ch, r) else 0;
        const line = dst + r * stride;
        for (0..8) |x| {
            if (bits >> @intCast(7 - x) & 1 == 0) line[x] = 0;
        }
    }
}

comptime {
    // Every page is 17 rows of exactly 40 cells, so the cell loop never
    // crosses the window's right edge or its bottom.
    @setEvalBranchQuota(40000);
    for (pages) |start| {
        var rows: usize = 0;
        var cols: usize = 0;
        var i: usize = start;
        while (assets.text[i] != END_PAGE) : (i += 1) {
            if (assets.text[i] == CR) {
                if (cols != COLS) @compileError("a text row is not 40 chars");
                rows += 1;
                cols = 0;
            } else cols += 1;
        }
        if (rows != ROWS or cols != 0) @compileError("a text page is not 17 rows");
    }
}
