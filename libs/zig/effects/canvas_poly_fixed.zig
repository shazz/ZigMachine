// --------------------------------------------------------------------------
// canvas_poly.fill in integers: the same doubled-canvas path fill shown halved
// (an ST pixel (X, Y) is ink when the canvas sample (2X + 0.5, 2Y + 0.5) is
// inside the path, nonzero rule), for paths in fixed-point canvas pixels such as
// zig3d_fixed's (1 px = 2^PX, zig3d_fixed_math.PX).
//
// Why: canvas_poly computes every edge crossing of every sample row as an f64
// expression with a divide, which on the board's FPU-less cart CPU is a chain
// of soft-float calls per row per edge. Here the decision is EXACT for the
// fixed-point path, with no rounding at all: along the row sy, an edge
// (p0, p1) with p0.y <= sy < p1.y (or the reverse) crosses at x = x0 + n/d,
// n = (sy - y0)(x1 - x0), d = y1 - y0, and the first sample at or right of it is
//   k = ceil((x - HALF) / TWO) = ceil((d (x0 - HALF) + n) / (TWO d))   (d > 0)
// (sample 2k + 0.5 canvas px = TWO k + HALF). Crossings are ordered
// by k: two crossings with the same k bound an empty span, so their order
// cannot change a pixel.
//
// Incremental, the way a span filler steps an edge: k is divided out once at
// an edge's first row, then each row adds the edge's whole step (q) and carries
// its remainder, so a row costs additions and compares, not a 64-bit divide
// (a libgcc call on the rv32 cart CPU). The numbers are the same as dividing
// on every row, exactly.
//
// Coordinates must stay within +-2^30 (zig3d_fixed holds them to +-2^30).
// No ZigOS import: canvas_poly_fixed_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const Dst = @import("blit.zig").Dst;
const span_fill = @import("span_fill.zig");
const PX = @import("zig3d_fixed_math.zig").PX;
const HALF: i64 = 1 << (PX - 1); // 0.5 canvas px
const TWO: i64 = 2 << PX; // 2 canvas px: one ST pixel

pub const MAX_POINTS = 16;

/// One edge over the sample rows [y, end): k = ceil(num / den) on row y, held
/// as k and r = k den - num (0 <= r < den); a row adds step = sq den + sr.
/// k is i32: on a row the edge spans, its crossing lies between its end points
/// (|x| <= 2^30, so |k| <= 2^15 + 1); the steps wrap (+%) so the value after the
/// last row, which is never read, cannot overflow. r and den stay i64.
const Edge = struct { y: i32, end: i32, k: i32, sq: i32, r: i64, sr: i64, den: i64, dir: i8 };

/// Fill the closed path `pts` (fixed-point canvas pixels, doubled) with `ink`.
pub fn fill(dst: Dst, pts: []const [2]i32, ink: u8) void {
    if (pts.len < 3 or pts.len > MAX_POINTS or dst.w == 0) return;
    const h: i64 = @intCast(dst.h);
    var edges: [MAX_POINTS]Edge = undefined;
    var n: usize = 0;
    var top: i32 = std.math.maxInt(i32);
    var bottom: i32 = 0;
    for (pts, 0..) |p0, i| {
        const e = edge(p0, pts[(i + 1) % pts.len], h) orelse continue;
        edges[n] = e;
        n += 1;
        top = @min(top, e.y);
        bottom = @max(bottom, e.end);
    }
    var y = top;
    while (y < bottom) : (y += 1) row(dst, edges[0..n], y, ink);
}

/// The edge p0 -> p1 on the rows whose sample it spans, clipped to 0..h;
/// null when it spans none (a horizontal edge spans none).
fn edge(p0: [2]i32, p1: [2]i32, h: i64) ?Edge {
    const down = p0[1] < p1[1];
    const a = if (down) p0 else p1;
    const b = if (down) p1 else p0;
    const y = @max(firstSample(a[1]), 0);
    const end = @min(firstSample(b[1]), h); // exclusive: sample < b.y
    if (y >= end) return null;
    const d: i64 = @as(i64, b[1]) - a[1];
    const dx: i64 = @as(i64, b[0]) - a[0];
    const den = TWO * d;
    const num = (y * TWO + HALF - a[1]) * dx + d * (@as(i64, a[0]) - HALF);
    const k = ceilDiv(num, den);
    const step = TWO * dx;
    const sq = @divFloor(step, den);
    return .{
        .y = @intCast(y),
        .end = @intCast(end),
        .k = @intCast(k),
        .sq = @truncate(sq), // only ever added mod 2^32 to an in-range k
        .r = k * den - num,
        .sr = step - sq * den,
        .den = den,
        .dir = if (down) 1 else -1,
    };
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
        const ck: u32 = @intCast(std.math.clamp(e.k, 0, w));
        xs[n] = ck << 2 | @as(u32, @intCast(e.dir + 1));
        n += 1;
        // next row: num += step, so k += sq and r -= sr, carrying one when r < 0
        e.k +%= e.sq;
        e.r -= e.sr;
        if (e.r < 0) {
            e.r += e.den;
            e.k +%= 1;
        }
    }
    std.sort.insertion(u32, xs[0..n], {}, std.sort.asc(u32));
    const line = dst.buf[@as(usize, @intCast(y)) * dst.stride ..][0..dst.w];
    var winding: i32 = 0;
    for (xs[0..n], 0..) |c, i| {
        winding += @as(i32, @intCast(c & 3)) - 1;
        if (winding == 0 or i + 1 == n) continue;
        const a = c >> 2;
        const b = xs[i + 1] >> 2;
        if (a < b) span_fill.fill(line[a..b], ink);
    }
}

/// The first ST index whose sample TWO k + HALF is >= c, unclamped.
fn firstSample(c: i32) i64 {
    return ceilDiv(@as(i64, c) - HALF, TWO);
}

/// ceil(a / b) for b > 0.
fn ceilDiv(a: i64, b: i64) i64 {
    return -@divFloor(-a, b);
}
