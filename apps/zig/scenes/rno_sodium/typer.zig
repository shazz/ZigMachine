// --------------------------------------------------------------------------
// The text typer $19DC and its wipe $03AC (parts 3-4, 7-8, 11-12).
//
// One character a frame, spaces included, until all 240 of the page are in.
// A glyph is 8x16 out of the 4-plane font, but only font planes 0 and 1 carry
// anything, and they are written as plain BYTES into screen planes 1 and 2
// (+$4A puts the cell on plane 1's byte). Plane 0 still belongs to the
// curtain, so on the strip's white the font's background shows 7, its ink 5
// ($446) and its drop shadow 1 (black); over the pink band the same bytes read
// 6, 4 ($346) and 0.
//
// The wipe sets planes 1 and 2 back to $FFFF on px 144..303 for two lines a
// frame: line 2t top-down and line 199-2t bottom-up, t = 1..100, so the even
// lines are restored downwards and the odd ones upwards. t = 100 aims at line
// 200 and line -1, just outside the screen; those two writes are clipped.
// --------------------------------------------------------------------------
const A = @import("assets.zig");
const st = @import("st.zig");

const CELL: usize = 0x4A; // px 144, plane 1's byte
const GLYPH_ROWS: usize = 16;
const FONT_ROW: usize = 256; // 4 planes x 64 bytes
const FONT_PLANE1: usize = 0x40;
const WIPE_GROUPS: usize = 10; // px 144..303

// Every cell of the position tables, glyph and plane-2 byte included, is on
// the screen: typeChar indexes without a check.
comptime {
    @setEvalBranchQuota(10_000);
    for (0..A.TEXT_CHARS) |k| {
        const last = CELL + A.textX(k) + A.textY(k) + (GLYPH_ROWS - 1) * st.LINE + 2;
        if (last >= st.BYTES) @compileError("a text cell runs off the screen");
    }
}

/// One call of $19DC with page `page` (0..2).
pub fn typeChar(scr: *[st.BYTES]u8, m: *st.Machine, page: usize) void {
    const k: usize = m.typed;
    if (k >= A.TEXT_CHARS) return;
    const g: usize = (@as(usize, A.text_pages[page * A.TEXT_CHARS + k]) + 0x20) & 0x3F;
    const at = CELL + A.textX(k) + A.textY(k);
    for (0..GLYPH_ROWS) |r| {
        scr[at + r * st.LINE] = A.font[r * FONT_ROW + g];
        scr[at + r * st.LINE + 2] = A.font[r * FONT_ROW + FONT_PLANE1 + g];
    }
    m.typed += 1;
}

/// $03AC(t): t = C - the typer's limit, 1..100 over the wipe part.
pub fn wipe(scr: *[st.BYTES]u8, t: u32) void {
    restoreLine(scr, @as(i32, @intCast(t)) * 2);
    restoreLine(scr, 199 - @as(i32, @intCast(t)) * 2);
}

fn restoreLine(scr: *[st.BYTES]u8, line: i32) void {
    if (line < 0 or line >= st.LINES) return;
    const row = scr[@as(usize, @intCast(line)) * st.LINE + CELL ..];
    for (0..WIPE_GROUPS) |g| row[g * 8 ..][0..4].* = @splat(0xFF);
}
