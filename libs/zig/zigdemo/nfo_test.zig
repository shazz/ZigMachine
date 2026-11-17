const std = @import("std");
const expect = std.testing.expect;
const eq = std.testing.expectEqual;
const nfo = @import("nfo.zig");
const glyph = @import("nfo_glyph.zig");
const font = @import("nfo_font.zig");
const render = @import("nfo_render.zig");
const cp437 = @import("nfo_cp437.zig");

const row_px = render.row_px;

// --- the font and the glyph cell ---

test "font: 'A' and '!' rows are the pictures" {
    try eq(@as(u8, 0b0011_0000), font.ascii['A' - 32][0]); // "..##..."
    try eq(@as(u8, 0b1111_1100), font.ascii['A' - 32][4]); // "######."
    try eq(@as(u8, 0b0001_0000), font.ascii['!' - 32][6]); // "...#..." (the dot)
    try eq(@as(u8, 0), font.ascii[0][3]); // the space
}

test "font: every glyph but the space has ink, and none uses column 7" {
    for (font.ascii, 0..) |g, i| {
        var any: u8 = 0;
        for (g) |row| any |= row;
        try expect((any != 0) == (i != 0));
        try eq(@as(u8, 0), any & 1);
    }
}

test "glyph: blocks fill their halves over all nine rows, with the grid on the edge" {
    try eq(glyph.white, glyph.pix(0xDB, 3, 3, 1)); // █ body
    try eq(glyph.grid_h, glyph.pix(0xDB, 3, 8, 0)); // bottom line
    try eq(glyph.grid_v, glyph.pix(0xDB, 7, 3, 0)); // right line
    try eq(glyph.white, glyph.pix(0xDF, 0, 4, 0)); // ▀ rows 0..4
    try eq(@as(u8, 0), glyph.pix(0xDF, 0, 5, 1));
    try eq(@as(u8, 0), glyph.pix(0xDC, 0, 3, 1)); // ▄ rows 4..8
    try eq(glyph.grid_h, glyph.pix(0xDC, 0, 8, 0));
    try eq(glyph.white, glyph.pix(0xDD, 3, 8 - 1, 1)); // ▌ left half
    try eq(@as(u8, 0), glyph.pix(0xDD, 4, 2, 0));
    try eq(@as(u8, 0), glyph.pix(0xDE, 3, 2, 0)); // ▐ right half
}

test "glyph: the dither is 25 / 50 / 75 percent and runs on across cell rows" {
    var lit = [3]u32{ 0, 0, 0 };
    for (0..2) |par| for (0..2) |x| for ([3]u8{ 0xB0, 0xB1, 0xB2 }, 0..) |ch, k| {
        lit[k] += @intFromBool(glyph.pix(ch, @intCast(x), 0, @intCast(par)) != 0);
    };
    try eq([3]u32{ 1, 2, 3 }, lit);
    // rows 8 and 9 (absolute) are parity 0 and 1: the checker alternates across the cell seam
    try expect((glyph.pix(0xB1, 0, 8, 0) != 0) != (glyph.pix(0xB1, 0, 0, 1) != 0));
}

test "glyph: an unknown high byte is a visible box, a control byte is blank" {
    try expect(glyph.pix(0x90, 1, 1, 1) != 0);
    try eq(@as(u8, 0), glyph.pix(0x07, 3, 3, 1));
    try eq(@as(u8, 0), glyph.pix(0xA0, 1, 1, 1)); // no-break space
}

// --- CP437 ---

test "cp437: block characters map to their bytes, ASCII to itself" {
    var out: [16]u8 = undefined;
    const n = try cp437.decode("a▀▄█▌▐░▒▓é", &out);
    try eq(@as(usize, 10), n);
    try std.testing.expectEqualSlices(u8, &.{ 'a', 0xDF, 0xDC, 0xDB, 0xDD, 0xDE, 0xB0, 0xB1, 0xB2, 0x82 }, out[0..n]);
}

test "cp437: the whole high half round-trips, errors are errors" {
    for (0x80..0x100) |b| {
        var utf8: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(try highCp(@intCast(b)), &utf8);
        var out: [4]u8 = undefined;
        try eq(@as(usize, 1), try cp437.decode(utf8[0..len], &out));
        try eq(@as(u8, @intCast(b)), out[0]);
    }
    var out: [4]u8 = undefined;
    try std.testing.expectError(error.Unmappable, cp437.decode("日", &out));
    try std.testing.expectError(error.BadUtf8, cp437.decode(&.{0xE2}, &out));
    try std.testing.expectError(error.TooLong, cp437.decode("abcde", &out));
}

fn highCp(b: u8) !u21 {
    // the inverse of fromCodepoint, by search: the table is private, so ask every code point
    var cp: u21 = 0x80;
    while (cp < 0x2600) : (cp += 1) if ((cp437.fromCodepoint(cp) catch continue) == b) return cp;
    return error.Unmappable;
}

test "cp437: comptimeFromUtf8 converts while compiling" {
    const bytes = comptime cp437.comptimeFromUtf8("█▀\n");
    try std.testing.expectEqualSlices(u8, &.{ 0xDB, 0xDF, '\n' }, bytes);
}

// --- text layout ---

test "text: lines, CRLF, the cut at 80 columns, a final newline, DOS end-of-file" {
    const t = try render.Text.parse("one\r\ntwo\n\n" ++ "x" ** 90 ++ "\nlast\x1A junk");
    try eq(@as(u32, 5), t.n);
    try std.testing.expectEqualStrings("one", t.line(0));
    try std.testing.expectEqualStrings("two", t.line(1));
    try std.testing.expectEqualStrings("", t.line(2));
    try eq(@as(usize, 80), t.line(3).len);
    try std.testing.expectEqualStrings("last", t.line(4));
    try std.testing.expectEqualStrings("", t.line(99));
    try eq(@as(u32, 45), t.height());
    try eq(@as(u32, 1), (try render.Text.parse("a\n")).n);
}

test "text: more than max_lines is an error, not a truncation" {
    const many = "x\n" ** (render.max_lines + 1);
    try std.testing.expectError(error.TooManyLines, render.Text.parse(many));
    _ = try render.Text.parse("x\n" ** render.max_lines);
}

test "renderRow: ink, the drop shadow one pixel down and right, the rest background" {
    const t = try render.Text.parse("A");
    var row: [row_px]u8 = undefined;
    render.renderRow(&t, 0, &row); // "..##..." : ink at x = 2, 3
    try eq(@as(u8, 0), row[1]);
    try eq(glyph.white, row[2]);
    try eq(glyph.white, row[3]);
    try eq(@as(u8, 0), row[4]);
    render.renderRow(&t, 1, &row); // ".#..#.." : ink at 1, 4; the shadow of row 0 lands at 3 (4 is ink)
    try eq(glyph.white, row[1]);
    try eq(glyph.shadow, row[3]);
    try eq(glyph.white, row[4]);
    render.renderRow(&t, 7, &row); // "A" row 6 is "#....#.": its shadow is row 7's x = 1 and 6
    try eq(glyph.shadow, row[1]);
    try eq(glyph.shadow, row[6]);
    render.renderRow(&t, 8, &row); // row 7 is blank: nothing falls into row 8
    try expect(std.mem.allEqual(u8, &row, glyph.bg));
    render.renderRow(&t, 100, &row); // below the text
    try expect(std.mem.allEqual(u8, &row, glyph.bg));
}

test "renderRow: a block's shadow falls into the next cell and the row below" {
    const t = try render.Text.parse("\xDB\xDB\n");
    var row: [row_px]u8 = undefined;
    render.renderRow(&t, 4, &row);
    try eq(glyph.white, row[0]);
    try eq(glyph.grid_v, row[7]);
    try eq(glyph.white, row[8]);
    try eq(glyph.grid_v, row[15]); // the last block's right line
    try eq(glyph.shadow, row[16]); // its shadow, one pixel past the cell
    render.renderRow(&t, 9, &row); // the row under the blocks: shadow from x = 1
    try eq(@as(u8, 0), row[0]);
    try eq(glyph.shadow, row[1]);
    try eq(glyph.shadow, row[16]);
}

test "buildBar: a rule on top, the text centred, too long is an error" {
    var bar: [render.bar_h * row_px]u8 = undefined;
    try render.buildBar("X", &bar);
    try eq(glyph.bar_line, bar[10]);
    try eq(glyph.bar_bg, bar[row_px + 10]);
    const x0 = (row_px - 8) / 2;
    try eq(glyph.white, bar[5 * row_px + x0]); // the X's top row "#....#." starts at the text's row 5
    try eq(glyph.white, bar[5 * row_px + x0 + 5]);
    try eq(glyph.bar_shadow, bar[6 * row_px + x0 + 6]); // its shadow, one down and right of x = 5
    try std.testing.expectError(error.PromptTooLong, render.buildBar("x" ** 81, &bar));
}

