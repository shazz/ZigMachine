// --------------------------------------------------------------------------
// Even-odd scanline polygon filler for STNICCC's polygons: 3..15 vertices,
// possibly NON-convex (format.txt says so), integer coordinates. A pixel is
// filled when its centre lies inside the polygon, so two polygons sharing an
// edge tile without a gap or a double row. Pure; tested at the bottom.
// --------------------------------------------------------------------------
const std = @import("std");

pub const MAX_VERTS: usize = 15;
pub const Point = struct { x: i32, y: i32 };

// Where to draw: `w` x `h` pixels inside `px`, starting `ox` pixels into each
// `stride`-wide row. Nothing outside that window is ever written.
pub const Target = struct { px: []u8, stride: usize, w: usize, h: usize, ox: usize };

pub fn fill(t: Target, pts: []const Point, color: u8) void {
    // A real branch, not std.debug.assert (gone in ReleaseSmall): an empty list
    // would wrap `pts.len - 1` in crossings() and more than MAX_VERTS overruns `xs`.
    if (pts.len < 3 or pts.len > MAX_VERTS) return;
    var ymin: i32 = std.math.maxInt(i32);
    var ymax: i32 = std.math.minInt(i32);
    for (pts) |p| {
        ymin = @min(ymin, p.y);
        ymax = @max(ymax, p.y);
    }
    var y = @max(ymin, 0);
    const y_end = @min(ymax, @as(i32, @intCast(t.h))); // row y's centre is y + 0.5
    while (y < y_end) : (y += 1) {
        var xs: [MAX_VERTS]i32 = undefined;
        const n = crossings(pts, y, &xs);
        var k: usize = 0;
        while (k + 1 < n) : (k += 2) span(t, xs[k], xs[k + 1], y, color);
    }
}

// Where the polygon's edges cross row y's centre line, in 16.16, sorted. Edges
// are half-open in y, so a vertex exactly on the line is counted once.
fn crossings(pts: []const Point, y: i32, xs: *[MAX_VERTS]i32) usize {
    const cy2 = 2 * y + 1; // the centre line, in half pixels
    var n: usize = 0;
    var j = pts.len - 1;
    for (pts, 0..) |a, i| {
        defer j = i;
        const b = pts[j];
        if (a.y == b.y) continue;
        const lo = if (a.y < b.y) a else b;
        const hi = if (a.y < b.y) b else a;
        if (cy2 < 2 * lo.y or cy2 >= 2 * hi.y) continue;
        const num = @as(i64, hi.x - lo.x) * (cy2 - 2 * lo.y) * 65536;
        const x = lo.x * 65536 + @as(i32, @intCast(@divFloor(num, 2 * (hi.y - lo.y))));
        var m = n; // insertion sort: at most 15 crossings
        while (m > 0 and xs[m - 1] > x) : (m -= 1) xs[m] = xs[m - 1];
        xs[m] = x;
        n += 1;
    }
    return n;
}

// Fill the pixels of row y whose centres fall in [x0, x1) (16.16).
fn span(t: Target, x0: i32, x1: i32, y: i32, color: u8) void {
    const w: i32 = @intCast(t.w);
    const start = @max(0, (x0 + 0x7FFF) >> 16);
    const end = @min(w, (x1 + 0x7FFF) >> 16);
    if (start >= end) return;
    const row = @as(usize, @intCast(y)) * t.stride + t.ox;
    @memset(t.px[row + @as(usize, @intCast(start)) .. row + @as(usize, @intCast(end))], color);
}

// --- tests ------------------------------------------------------------------
const expectEqual = std.testing.expectEqual;

fn count(px: []const u8, color: u8) usize {
    var n: usize = 0;
    for (px) |p| n += @intFromBool(p == color);
    return n;
}

test "a 3x3 square covers exactly its 9 pixel centres" {
    var px = [_]u8{0} ** (8 * 8);
    const t = Target{ .px = &px, .stride = 8, .w = 8, .h = 8, .ox = 0 };
    fill(t, &.{ .{ .x = 1, .y = 1 }, .{ .x = 4, .y = 1 }, .{ .x = 4, .y = 4 }, .{ .x = 1, .y = 4 } }, 5);
    try expectEqual(@as(usize, 9), count(&px, 5));
    try expectEqual(@as(u8, 5), px[1 * 8 + 1]);
    try expectEqual(@as(u8, 5), px[3 * 8 + 3]);
    try expectEqual(@as(u8, 0), px[4 * 8 + 4]);
}

test "a non-convex U leaves its notch empty" {
    var px = [_]u8{0} ** (8 * 8);
    const t = Target{ .px = &px, .stride = 8, .w = 8, .h = 8, .ox = 0 };
    fill(t, &.{
        .{ .x = 0, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 4 }, .{ .x = 4, .y = 4 },
        .{ .x = 4, .y = 0 }, .{ .x = 6, .y = 0 }, .{ .x = 6, .y = 6 }, .{ .x = 0, .y = 6 },
    }, 1);
    try expectEqual(@as(u8, 0), px[2 * 8 + 3]); // inside the notch
    try expectEqual(@as(u8, 1), px[2 * 8 + 1]); // left arm
    try expectEqual(@as(u8, 1), px[5 * 8 + 3]); // base
    try expectEqual(@as(usize, 36 - 8), count(&px, 1));
}

test "a vertex count outside 3..MAX_VERTS draws nothing" {
    var px = [_]u8{0} ** (8 * 8);
    const t = Target{ .px = &px, .stride = 8, .w = 8, .h = 8, .ox = 0 };
    fill(t, &.{}, 3);
    fill(t, &.{ .{ .x = 0, .y = 0 }, .{ .x = 8, .y = 8 } }, 3);
    const many = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 8, .y = 0 }, .{ .x = 8, .y = 8 } } ** 6;
    fill(t, &many, 3);
    try expectEqual(@as(usize, 0), count(&px, 3));
}

test "a polygon larger than the window is clipped to it, offset included" {
    var px = [_]u8{0} ** (10 * 4);
    const t = Target{ .px = &px, .stride = 10, .w = 6, .h = 4, .ox = 2 };
    fill(t, &.{ .{ .x = -50, .y = -50 }, .{ .x = 300, .y = -50 }, .{ .x = 300, .y = 300 } }, 7);
    for (0..4) |y| {
        try expectEqual(@as(u8, 0), px[y * 10 + 0]); // left of the window
        try expectEqual(@as(u8, 0), px[y * 10 + 9]); // right of the window
    }
    try expectEqual(@as(u8, 7), px[0 * 10 + 7]); // top-right corner of the window is inside
}
