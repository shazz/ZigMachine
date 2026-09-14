// Tests for effects/spanfont.zig: the run lookup over shared rows, and the
// half-resolution column mapping at both parities and off the left edge.
const std = @import("std");
const sf = @import("spanfont.zig");
const expectEqual = std.testing.expectEqual;

// 2 glyphs of 2 rows; unique rows: 0 = [74,98), 1 = none, 2 = [0,2) [5,9)
const font = sf.SpanFont{
    .row_ids = &.{ 0, 1, 2, 0 },
    .first = &.{ 0, 0, 1, 0, 1, 0, 3, 0 },
    .spans = &.{ 74, 0, 98, 0, 0, 0, 2, 0, 5, 0, 9, 0 },
    .rows_per_glyph = 2,
};

fn collect(glyph: usize, row: usize, out: []sf.Run) usize {
    var it = font.runs(glyph, row);
    var k: usize = 0;
    while (it.next()) |r| : (k += 1) out[k] = r;
    return k;
}

test "runs follow the row id, and rows are shared" {
    var buf: [4]sf.Run = undefined;
    try expectEqual(@as(usize, 1), collect(0, 0, &buf));
    try expectEqual(sf.Run{ .x0 = 74, .x1 = 98 }, buf[0]);
    try expectEqual(@as(usize, 0), collect(0, 1, &buf));
    try expectEqual(@as(usize, 2), collect(1, 0, &buf));
    try expectEqual(sf.Run{ .x0 = 5, .x1 = 9 }, buf[1]);
    try expectEqual(@as(usize, 1), collect(1, 1, &buf)); // glyph 1 row 1 is row 0 again
    try expectEqual(@as(usize, 2), font.glyphs());
}

test "glyphs and rows past the font have no runs" {
    var buf: [4]sf.Run = undefined;
    try expectEqual(@as(usize, 0), collect(2, 0, &buf));
    try expectEqual(@as(usize, 0), collect(0, 2, &buf));
}

test "halfColumns takes the columns whose canvas column 2x is in the run" {
    const run = sf.Run{ .x0 = 74, .x1 = 98 };
    try expectEqual([2]i32{ 37, 49 }, sf.halfColumns(0, run)); // 74..96 even columns
    try expectEqual([2]i32{ 38, 50 }, sf.halfColumns(1, run)); // 2*38-1 = 75 in, 2*37-1 = 73 out
    try expectEqual([2]i32{ -3, 1 }, sf.halfColumns(-7, .{ .x0 = 0, .x1 = 8 })); // -6+7 = 1 in
    const empty = sf.halfColumns(0, .{ .x0 = 5, .x1 = 6 }); // only canvas column 5: odd
    try std.testing.expect(empty[1] <= empty[0]);
}
