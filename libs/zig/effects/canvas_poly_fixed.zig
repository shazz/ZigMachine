// --------------------------------------------------------------------------
// canvas_poly.fill in integers: the same doubled-canvas path fill shown halved
// (an ST pixel (X, Y) is ink when the canvas sample (2X + 0.5, 2Y + 0.5) is
// inside the path, nonzero rule), for paths in fixed-point canvas pixels such as
// zig3d_fixed's (1 px = 2^PX, zig3d_fixed_math.PX).
//
// Why: canvas_poly computes every edge crossing of every sample row as an f64
// expression with a divide, which on the board's cart CPU is a chain of
// soft-float calls per row per edge. Here the decision is EXACT for the
// fixed-point path, with no rounding at all (canvas_poly_fixed_edge.zig: one
// divide per edge, then additions down its rows).
//
// Two fills, the same pixels:
//   - a y-monotone path (its y goes down once and up once, as every projected
//     face does) is walked as two chains, the span filler's way: each row has
//     exactly one crossing from each chain (their edges tile the rows
//     half-open), and with two crossings the nonzero rule fills between them
//     whichever comes first. The edges stay in registers; the only stores are
//     the span's, four pixels a store (every store blocks on DDR on the board);
//   - any other path collects each row's crossings and sorts them by k: two
//     crossings with the same k bound an empty span, so their order cannot
//     change a pixel. Each crossing is one packed u32 key (see row).
//
// Both fills store a span's bytes only where they change (span_fill.zig): a
// face redrawn over its own previous frame is mostly there already, and on the
// board a store blocks on DDR while a load hits the cache.
//
// Coordinates must stay within +-2^30 (zig3d_fixed holds them to +-2^30).
// No ZigOS import: canvas_poly_fixed_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const Dst = @import("blit.zig").Dst;
const E = @import("canvas_poly_fixed_edge.zig");
const Edge = E.Edge;

pub const MAX_POINTS = 16;

/// Fill the closed path `pts` (fixed-point canvas pixels, doubled) with `ink`.
pub fn fill(dst: Dst, pts: []const [2]i32, ink: u8) void {
    if (pts.len < 3 or pts.len > MAX_POINTS or dst.w == 0) return;
    if (monotoneStart(pts)) |s| return fillMonotone(dst, pts, s, ink);
    fillGeneral(dst, pts, ink);
}

/// The y direction of edge i -> i + 1 (cyclic): -1, 0 or 1.
fn sign(pts: []const [2]i32, i: usize) i32 {
    const j = if (i + 1 == pts.len) 0 else i + 1;
    return std.math.sign(pts[j][1] - pts[i][1]);
}

/// The first edge of the path's one downward run when its y turns exactly twice
/// (horizontal edges turn nothing); null otherwise, or when it is flat.
fn monotoneStart(pts: []const [2]i32) ?usize {
    var last: i32 = 0;
    var i = pts.len;
    while (i > 0 and last == 0) : (i -= 1) last = sign(pts, i - 1);
    if (last == 0) return null;
    var turns: u32 = 0;
    var start: usize = 0;
    for (0..pts.len) |e| {
        const s = sign(pts, e);
        if (s == 0 or s == last) continue;
        turns += 1;
        if (s > 0) start = e;
        last = s;
    }
    return if (turns == 2) start else null;
}

/// One chain: edges taken forward or backward from `at` while their y does
/// not turn back.
const Chain = struct {
    pts: []const [2]i32,
    at: usize,
    fwd: bool,
    h: i64,

    /// Its next edge spanning a sample row, or null at the chain's bottom.
    inline fn next(c: *Chain) ?Edge {
        const n = c.pts.len;
        while (true) {
            const i = if (c.fwd) c.at else (c.at + n - 1) % n;
            const s = sign(c.pts, i);
            if ((c.fwd and s < 0) or (!c.fwd and s > 0)) return null;
            c.at = if (c.fwd) (c.at + 1) % n else i;
            if (E.edge(c.pts[i], c.pts[(i + 1) % n], c.h)) |e| return e;
        }
    }
};

fn fillMonotone(dst: Dst, pts: []const [2]i32, s: usize, ink: u8) void {
    const h: i64 = @intCast(dst.h);
    const w: i32 = @intCast(dst.w);
    var lc = Chain{ .pts = pts, .at = s, .fwd = true, .h = h };
    var rc = Chain{ .pts = pts, .at = s, .fwd = false, .h = h };
    var l = lc.next() orelse return;
    var r = rc.next() orelse return;
    std.debug.assert(l.y == r.y); // both chains cover the same rows
    var y = l.y;
    var line = dst.buf.ptr + @as(usize, @intCast(y)) * dst.stride;
    while (true) {
        if (y >= l.end) l = lc.next() orelse return;
        if (y >= r.end) r = rc.next() orelse return;
        const stop = @min(l.end, r.end);
        while (y < stop) : (y += 1) {
            const a = E.clampK(l.k, w);
            const b = E.clampK(r.k, w);
            if (a < b) E.span(line, a, b, ink) else E.span(line, b, a, ink);
            line += dst.stride;
            l.step();
            r.step();
        }
    }
}

fn fillGeneral(dst: Dst, pts: []const [2]i32, ink: u8) void {
    const h: i64 = @intCast(dst.h);
    var edges: [MAX_POINTS]Edge = undefined;
    var n: usize = 0;
    var top: i32 = @intCast(h);
    var bottom: i32 = 0;
    for (pts, 0..) |p0, i| {
        const e = E.edge(p0, pts[(i + 1) % pts.len], h) orelse continue;
        edges[n] = e;
        n += 1;
        top = @min(top, e.y);
        bottom = @max(bottom, e.end);
    }
    var y = top;
    while (y < bottom) : (y += 1) row(dst, edges[0..n], y, ink);
}

/// One sample row. A crossing is packed as (clamped k) << 2 | (dir + 1): a
/// pixel's ink depends only on how many crossings, of which direction, lie at
/// or left of it, and k <= x is clampK(k) <= x for every x in 0..w, so sorting
/// the clamped keys (one u32 each, no struct swaps) fills the same spans.
fn row(dst: Dst, edges: []Edge, y: i32, ink: u8) void {
    var xs: [MAX_POINTS]u32 = undefined;
    var n: usize = 0;
    const w: i32 = @intCast(dst.w);
    for (edges) |*e| {
        if (y < e.y or y >= e.end) continue;
        const ck: u32 = @intCast(E.clampK(e.k, w));
        xs[n] = ck << 2 | @as(u32, @intCast(e.dir + 1));
        n += 1;
        e.step();
    }
    std.sort.insertion(u32, xs[0..n], {}, std.sort.asc(u32));
    const line = dst.buf.ptr + @as(usize, @intCast(y)) * dst.stride;
    var winding: i32 = 0;
    for (xs[0..n], 0..) |c, i| {
        winding += @as(i32, @intCast(c & 3)) - 1;
        if (winding == 0 or i + 1 == n) continue;
        const a = c >> 2;
        const b = xs[i + 1] >> 2;
        if (a < b) E.span(line, a, b, ink);
    }
}
