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
/// `rect`, when set, fills a rectangle (x counted from the row start, so `ox`
/// is included) instead of the CPU writing the bytes: the scene routes it to the blitter.
pub const Target = struct {
    px: []u8,
    stride: usize,
    w: usize,
    h: usize,
    ox: usize,
    rect: ?*const fn (x: usize, y: usize, w: usize, h: usize, color: u8) void = null,
};

// One non-horizontal edge, walked a row at a time. Row y's centre crossing is
//   x = lo.x * 65536 + floor(dx * 32768 * (2k + 1) / dy)      (k = y - lo.y)
// and the numerator grows by A = dx * 65536 a row, so the floor is stepped as a
// quotient and a remainder (0 <= r < dy): no divide per row. The old code did an
// i64 divide per edge per row (a soft routine on rv32: ~3 Mc a frame on the board).
const Edge = struct {
    y_lo: i32, // first row the edge crosses
    y_hi: i32, // one past the last
    base: i32, // lo.x * 65536
    q: i32, // floor(numerator / dy) at the next row
    r: i32, // the remainder of that division
    dy: i32,
    qs: i32, // floor(A / dy)
    rs: i32, // A mod dy
};

fn edgeAt(lo: Point, hi: Point, y_first: i32) Edge {
    const dx = hi.x - lo.x;
    const dy = hi.y - lo.y;
    const a = dx * 65536;
    var e = Edge{ .y_lo = lo.y, .y_hi = hi.y, .base = lo.x * 65536, .q = 0, .r = 0, .dy = dy, .qs = @divFloor(a, dy), .rs = @mod(a, dy) };
    const k = y_first - lo.y;
    if (k == 0) { // the usual start: a 32-bit numerator
        e.q = @divFloor(dx * 32768, dy);
        e.r = @mod(dx * 32768, dy);
    } else { // a polygon clipped at the top: its numerator may not fit 32 bits
        const n = @as(i64, dx) * 32768 * (2 * @as(i64, k) + 1);
        e.q = @intCast(@divFloor(n, dy));
        e.r = @intCast(@mod(n, dy));
    }
    return e;
}

inline fn step(e: *Edge) void {
    e.q += e.qs;
    e.r += e.rs;
    if (e.r >= e.dy) {
        e.r -= e.dy;
        e.q += 1;
    }
}

/// The span [start, end) of a row's pixels whose centres fall in [x0, x1) (16.16).
const Span = struct { start: i32, end: i32 };
fn clip(t: Target, x0: i32, x1: i32) Span {
    const w: i32 = @intCast(t.w);
    return .{ .start = @max(0, (x0 + 0x7FFF) >> 16), .end = @min(w, (x1 + 0x7FFF) >> 16) };
}

pub fn fill(t: Target, pts: []const Point, color: u8) void {
    // A real branch, not std.debug.assert (gone in ReleaseSmall): an empty list
    // would wrap `pts.len - 1` and more than MAX_VERTS overruns `edges`.
    if (pts.len < 3 or pts.len > MAX_VERTS) return;
    var ymin: i32 = std.math.maxInt(i32);
    var ymax: i32 = std.math.minInt(i32);
    for (pts) |p| {
        ymin = @min(ymin, p.y);
        ymax = @max(ymax, p.y);
    }
    var y = @max(ymin, 0);
    const y_end = @min(ymax, @as(i32, @intCast(t.h))); // row y's centre is y + 0.5
    var edges: [MAX_VERTS]Edge = undefined;
    var ne: usize = 0;
    var j = pts.len - 1;
    for (pts, 0..) |a, i| {
        defer j = i;
        const b = pts[j];
        if (a.y == b.y) continue;
        const lo = if (a.y < b.y) a else b;
        const hi = if (a.y < b.y) b else a;
        if (hi.y <= y or lo.y >= y_end) continue; // never crosses a drawn row
        edges[ne] = edgeAt(lo, hi, @max(lo.y, y));
        ne += 1;
    }
    var run = Run{};
    while (y < y_end) : (y += 1) {
        var xs: [MAX_VERTS]i32 = undefined;
        var n: usize = 0;
        for (edges[0..ne]) |*e| {
            if (y < e.y_lo or y >= e.y_hi) continue;
            const x = e.base + e.q;
            step(e);
            var m = n; // insertion sort: at most 15 crossings
            while (m > 0 and xs[m - 1] > x) : (m -= 1) xs[m] = xs[m - 1];
            xs[m] = x;
            n += 1;
        }
        var k: usize = 0;
        while (k + 1 < n) : (k += 2) {
            const sp = clip(t, xs[k], xs[k + 1]);
            if (sp.start >= sp.end) continue;
            if (n == 2 and run.extend(sp, y)) continue; // the same span as the row above: one taller fill
            run.flush(t, color);
            if (n == 2) run = .{ .sp = sp, .y = y, .h = 1 } else emit(t, sp, y, 1, color);
        }
        if (n != 2) run.flush(t, color);
    }
    run.flush(t, color);
}

// A pending fill: the rows from `y` that all show span `sp` (a polygon's vertical
// sides repeat it row after row), flushed as ONE rectangle. Same pixels.
const Run = struct {
    sp: Span = .{ .start = 0, .end = 0 },
    y: i32 = 0,
    h: i32 = 0,

    fn extend(r: *Run, sp: Span, y: i32) bool {
        if (r.h == 0 or r.sp.start != sp.start or r.sp.end != sp.end or r.y + r.h != y) return false;
        r.h += 1;
        return true;
    }

    fn flush(r: *Run, t: Target, color: u8) void {
        if (r.h > 0) emit(t, r.sp, r.y, r.h, color);
        r.h = 0;
    }
};

fn emit(t: Target, sp: Span, y: i32, h: i32, color: u8) void {
    const start: usize = @intCast(sp.start);
    const end: usize = @intCast(sp.end);
    if (t.rect) |rect| return rect(t.ox + start, @intCast(y), end - start, @intCast(h), color);
    var row = @as(usize, @intCast(y)) * t.stride + t.ox;
    for (0..@as(usize, @intCast(h))) |_| {
        @memset(t.px[row + start .. row + end], color);
        row += t.stride;
    }
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

// The filler as it was (an i64 divide per edge per row, one span at a time), kept as
// the reference the stepped edges and the merged rows must reproduce pixel for pixel.
fn refFill(t: Target, pts: []const Point, color: u8) void {
    var ymin: i32 = std.math.maxInt(i32);
    var ymax: i32 = std.math.minInt(i32);
    for (pts) |p| {
        ymin = @min(ymin, p.y);
        ymax = @max(ymax, p.y);
    }
    var y = @max(ymin, 0);
    const y_end = @min(ymax, @as(i32, @intCast(t.h)));
    while (y < y_end) : (y += 1) {
        const cy2 = 2 * y + 1;
        var xs: [MAX_VERTS]i32 = undefined;
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
            var m = n;
            while (m > 0 and xs[m - 1] > x) : (m -= 1) xs[m] = xs[m - 1];
            xs[m] = x;
            n += 1;
        }
        var k: usize = 0;
        while (k + 1 < n) : (k += 2) {
            const sp = clip(t, xs[k], xs[k + 1]);
            if (sp.start >= sp.end) continue;
            const row = @as(usize, @intCast(y)) * t.stride + t.ox;
            @memset(t.px[row + @as(usize, @intCast(sp.start)) .. row + @as(usize, @intCast(sp.end))], color);
        }
    }
}

test "stepped edges and merged rows draw what the divide-per-row filler drew" {
    var prng = std.Random.DefaultPrng.init(0x57a1c);
    const rnd = prng.random();
    var a = [_]u8{0} ** (64 * 48);
    var b = [_]u8{0} ** (64 * 48);
    for (0..4000) |_| {
        var pts: [MAX_VERTS]Point = undefined;
        const n = 3 + rnd.uintLessThan(usize, MAX_VERTS - 2);
        for (pts[0..n]) |*p| p.* = .{ .x = rnd.intRangeAtMost(i32, -20, 90), .y = rnd.intRangeAtMost(i32, -20, 70) };
        if (rnd.boolean()) { // vertical sides, as a rectangle: rows that repeat
            pts[1] = .{ .x = pts[0].x, .y = pts[1].y };
            pts[2] = .{ .x = pts[3 % n].x, .y = pts[2].y };
        }
        @memset(&a, 0);
        @memset(&b, 0);
        const ta = Target{ .px = &a, .stride = 64, .w = 56, .h = 48, .ox = 4 };
        const tb = Target{ .px = &b, .stride = 64, .w = 56, .h = 48, .ox = 4 };
        fill(ta, pts[0..n], 9);
        refFill(tb, pts[0..n], 9);
        try expectEqual(b, a);
    }
}
