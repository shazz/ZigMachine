// Tests for effects/spans.zig: runs per row, row boundaries, the key, and that
// both hand-written forms (garfield's per-row runs, dd2's flat start/len over
// the whole buffer) are reproduced exactly.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const spans = @import("spans.zig");

const IMG = [_]u8{
    0, 1, 1, 0, 2, //
    3, 3, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    4, 4, 4, 4, 4, //
};
const runs = spans.build(&IMG, 5, 0);

test "runs stop at the key and at the row's end" {
    try expectEqual(@as(usize, 4), runs.spans.len);
    try expectEqual(@as(usize, 2), runs.row(0).len);
    try expectEqual(spans.Span{ .x0 = 1, .x1 = 3 }, runs.row(0)[0]);
    try expectEqual(spans.Span{ .x0 = 4, .x1 = 5 }, runs.row(0)[1]);
    try expectEqual(spans.Span{ .x0 = 0, .x1 = 2 }, runs.row(1)[0]);
    try expectEqual(@as(usize, 0), runs.row(2).len);
    try expectEqual(spans.Span{ .x0 = 0, .x1 = 5 }, runs.row(3)[0]);
}

test "a run ending a row does not merge with ink starting the next" {
    const img = [_]u8{ 0, 7, 7, 0 };
    const r = spans.build(&img, 2, 0);
    try expectEqual(@as(usize, 2), r.spans.len);
    try expectEqual(spans.Span{ .x0 = 1, .x1 = 2 }, r.row(0)[0]);
    try expectEqual(spans.Span{ .x0 = 0, .x1 = 1 }, r.row(1)[0]);
}

test "row past the image is empty; height is exposed" {
    try expectEqual(@as(usize, 4), @TypeOf(runs).height);
    try expectEqual(@as(usize, 0), runs.row(4).len);
    try expectEqual(@as(usize, 0), runs.row(1000).len);
}

test "all-key, all-ink and one-pixel-wide images" {
    const none = spans.build(&[_]u8{ 0, 0, 0, 0 }, 2, 0);
    try expectEqual(@as(usize, 0), none.spans.len);
    const full = spans.build(&[_]u8{ 1, 1, 1, 1, 1, 1 }, 3, 0);
    try expectEqual(spans.Span{ .x0 = 0, .x1 = 3 }, full.row(1)[0]);
    const narrow = spans.build(&[_]u8{ 1, 0, 1 }, 1, 0);
    try expectEqual(@as(usize, 2), narrow.spans.len);
}

test "a build inside a function is still comptime" {
    const local = spans.build(&IMG, 5, 0);
    try expectEqual(runs.spans, local.spans);
}

test "a non-zero key" {
    const img = [_]u8{ 9, 0, 9, 0 };
    const r = spans.build(&img, 4, 9);
    try expectEqual(@as(usize, 2), r.spans.len);
    try expectEqual(spans.Span{ .x0 = 3, .x1 = 4 }, r.spans[1]);
}

const S = struct { start: u32, len: u16 };

fn ddTwoForm(comptime img: []const u8, comptime w: usize) []const S {
    comptime var list: []const S = &.{};
    comptime var x: usize = 0;
    inline while (x < img.len) {
        if (img[x] == 0) {
            x += 1;
            continue;
        }
        const start = x;
        const row_end = (x / w + 1) * w;
        while (x < row_end and img[x] != 0) x += 1;
        list = list ++ &[_]S{.{ .start = start, .len = x - start }};
    }
    return list;
}

test "matches dd2's flat start/len runs, in order" {
    const flat = comptime ddTwoForm(&IMG, 5);
    var i: usize = 0;
    for (0..runs.row_first.len - 1) |y| {
        for (runs.row(y)) |s| {
            try expectEqual(flat[i].start, @as(u32, @intCast(y * runs.w + s.x0)));
            try expectEqual(flat[i].len, s.x1 - s.x0);
            i += 1;
        }
    }
    try expectEqual(flat.len, i);
}

test "draws the image back exactly" {
    var buf = [_]u8{0} ** IMG.len;
    for (0..runs.row_first.len - 1) |y| {
        for (runs.row(y)) |s| {
            @memcpy(buf[y * 5 + s.x0 .. y * 5 + s.x1], IMG[y * 5 + s.x0 .. y * 5 + s.x1]);
        }
    }
    try expectEqual(IMG, buf);
}
