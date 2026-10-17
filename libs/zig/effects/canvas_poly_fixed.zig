// --------------------------------------------------------------------------
// canvas_poly.fill in integers: the same doubled-canvas path fill shown halved
// (an ST pixel (X, Y) is ink when the canvas sample (2X + 0.5, 2Y + 0.5) is
// inside the path, nonzero rule), for paths in fixed-point canvas pixels such as
// zig3d_fixed's (1 px = 2^PX, zig3d_fixed_math.PX).
//
// Why: canvas_poly computes every edge crossing of every sample row as an f64
// expression with a divide, which on the board's FPU-less cart CPU is a chain
// of soft-float calls per row per edge. Here the decision is EXACT for the
// fixed-point path, with no rounding at all: along the row sy, an edge (p0, p1) with
// p0.y <= sy < p1.y (or the reverse) crosses at x = x0 + n/d, n = (sy - y0)
// (x1 - x0), d = y1 - y0, and the first sample at or right of it is
//   k = ceil((x - HALF) / TWO) = ceil((d (x0 - HALF) + n) / (TWO d))   (d > 0)
// (sample 2k + 0.5 canvas px = TWO k + HALF). Crossings are ordered
// by k: two crossings with the same k bound an empty span, so their order
// cannot change a pixel.
//
// Coordinates must stay within +-2^30 (zig3d_fixed holds them to +-2^30).
// No ZigOS import: canvas_poly_fixed_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const Dst = @import("blit.zig").Dst;
const PX = @import("zig3d_fixed_math.zig").PX;
const HALF: i64 = 1 << (PX - 1); // 0.5 canvas px
const TWO: i64 = 2 << PX; // 2 canvas px: one ST pixel

pub const MAX_POINTS = 16;

const Crossing = struct { k: i64, dir: i8 };

/// Fill the closed path `pts` (fixed-point canvas pixels, doubled) with `ink`.
pub fn fill(dst: Dst, pts: []const [2]i32, ink: u8) void {
    if (pts.len < 3 or pts.len > MAX_POINTS or dst.w == 0) return;
    var lo = pts[0][1];
    var hi = pts[0][1];
    for (pts[1..]) |p| {
        lo = @min(lo, p[1]);
        hi = @max(hi, p[1]);
    }
    const h: i64 = @intCast(dst.h);
    const first = clampK(firstSample(lo), h);
    const last = clampK(firstSample(hi), h); // exclusive: sample < hi
    var y = first;
    while (y < last) : (y += 1) row(dst, pts, @intCast(y), ink);
}

fn row(dst: Dst, pts: []const [2]i32, y: usize, ink: u8) void {
    const sy: i64 = @as(i64, @intCast(y)) * TWO + HALF;
    var xs: [MAX_POINTS]Crossing = undefined;
    var n: usize = 0;
    for (pts, 0..) |p0, i| {
        const p1 = pts[(i + 1) % pts.len];
        const y0: i64 = p0[1];
        const y1: i64 = p1[1];
        const down = y0 <= sy and sy < y1;
        if (!down and !(y1 <= sy and sy < y0)) continue;
        // the same crossing from either end, with a positive divisor
        const a = if (down) p0 else p1;
        const b = if (down) p1 else p0;
        const d: i64 = @as(i64, b[1]) - a[1];
        const num = (sy - a[1]) * (@as(i64, b[0]) - a[0]) + d * (@as(i64, a[0]) - HALF);
        xs[n] = .{ .k = ceilDiv(num, TWO * d), .dir = if (down) 1 else -1 };
        n += 1;
    }
    std.sort.insertion(Crossing, xs[0..n], {}, leftOf);
    const w: i64 = @intCast(dst.w);
    const line = dst.buf[y * dst.stride ..][0..dst.w];
    var winding: i32 = 0;
    for (xs[0..n], 0..) |c, i| {
        winding += c.dir;
        if (winding == 0 or i + 1 == n) continue;
        const a = clampK(c.k, w);
        const b = clampK(xs[i + 1].k, w);
        if (a < b) @memset(line[@intCast(a)..@intCast(b)], ink);
    }
}

/// The first ST index whose sample TWO k + HALF is >= c, unclamped.
fn firstSample(c: i32) i64 {
    return ceilDiv(@as(i64, c) - HALF, TWO);
}

fn clampK(k: i64, limit: i64) i64 {
    return std.math.clamp(k, 0, limit);
}

/// ceil(a / b) for b > 0.
fn ceilDiv(a: i64, b: i64) i64 {
    return -@divFloor(-a, b);
}

fn leftOf(_: void, a: Crossing, b: Crossing) bool {
    return a.k < b.k;
}
