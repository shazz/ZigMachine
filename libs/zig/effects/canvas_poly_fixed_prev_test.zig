// Tests for effects/canvas_poly_fixed.zig against its previous version, kept
// verbatim below (i64 k, Crossing structs sorted by k, @memset spans): the i32
// k, packed clamped keys and store-only-changes spans must fill the same pixels
// for paths over the whole +-2^30 range the fill accepts, and leave untouched
// bytes alone, on random backgrounds.
const std = @import("std");
const Dst = @import("blit.zig").Dst;
const PX = @import("zig3d_fixed_math.zig").PX;
const qfill = @import("canvas_poly_fixed.zig");

test "random paths, up to +-2^30: the same bytes as the previous fill" {
    var prng = std.Random.DefaultPrng.init(0xc0ffee);
    const r = prng.random();
    var a: [96 * 50]u8 = undefined;
    var b: [96 * 50]u8 = undefined;
    for (0..6000) |i| {
        const n: usize = 3 + i % 6;
        var q: [8][2]i32 = undefined;
        const span: i32 = switch (i % 3) {
            0 => 120 << PX,
            1 => 3000 << PX,
            else => 1 << 30,
        };
        for (q[0..n]) |*p| p.* = .{ r.intRangeAtMost(i32, -span, span), r.intRangeAtMost(i32, -span, span) };
        r.bytes(&a);
        b = a;
        const ink = r.int(u8);
        oldFill(Dst.buffer(&a, 96), q[0..n], ink);
        qfill.fill(Dst.buffer(&b, 96), q[0..n], ink);
        try std.testing.expectEqualSlices(u8, &a, &b);
    }
}

// --- the previous canvas_poly_fixed.zig, verbatim from `const HALF` on ---
const HALF: i64 = 1 << (PX - 1); // 0.5 canvas px
const TWO: i64 = 2 << PX; // 2 canvas px: one ST pixel

const MAX_POINTS = 16;

const Crossing = struct { k: i64, dir: i8 };

/// One edge over the sample rows [y, end): k = ceil(num / den) on row y, held
/// as k and r = k den - num (0 <= r < den); a row adds step = sq den + sr.
const Edge = struct { y: i64, end: i64, k: i64, r: i64, sq: i64, sr: i64, den: i64, dir: i8 };

/// Fill the closed path `pts` (fixed-point canvas pixels, doubled) with `ink`.
fn oldFill(dst: Dst, pts: []const [2]i32, ink: u8) void {
    if (pts.len < 3 or pts.len > MAX_POINTS or dst.w == 0) return;
    const h: i64 = @intCast(dst.h);
    var edges: [MAX_POINTS]Edge = undefined;
    var n: usize = 0;
    var top: i64 = h;
    var bottom: i64 = 0;
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
    return .{ .y = y, .end = end, .k = k, .r = k * den - num, .sq = sq, .sr = step - sq * den, .den = den, .dir = if (down) 1 else -1 };
}

fn row(dst: Dst, edges: []Edge, y: i64, ink: u8) void {
    var xs: [MAX_POINTS]Crossing = undefined;
    var n: usize = 0;
    for (edges) |*e| {
        if (y < e.y or y >= e.end) continue;
        xs[n] = .{ .k = e.k, .dir = e.dir };
        n += 1;
        // next row: num += step, so k += sq and r -= sr, carrying one when r < 0
        e.k += e.sq;
        e.r -= e.sr;
        if (e.r < 0) {
            e.r += e.den;
            e.k += 1;
        }
    }
    std.sort.insertion(Crossing, xs[0..n], {}, leftOf);
    const w: i64 = @intCast(dst.w);
    const line = dst.buf[@as(usize, @intCast(y)) * dst.stride ..][0..dst.w];
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
