// --------------------------------------------------------------------------
// The ball-oid's rasteriser: a convex polygon of 3 or 4 vertices (a whole quad in one row
// walk), affine env-mapped, rows at pixel centres, top-left fill, clipped to the part's box.
// The DSP did this on the Falcon and sent finished texels; here it is the cart CPU's.
//
// Cost rules (KESTREL model): no i64, no struct copies (wasm copies them with i64 accesses,
// unaligned), divides only per edge and per polygon (and most go through a reciprocal
// table), and the per-row work is adds plus two multiplies. Spans walk a PACKED u,v
// (u 6.10 in the high half, v 6.10 in the low half): one add a pixel, and pixel pairs go out
// as one aligned u32.
// Bounds: `vertex` clamps the screen to an 800 px window (12800 in 28.4) and u,v stay in
// 0..64 texels (2^22 in 16.16), so every product below fits i32 (the native sweep test runs
// it with overflow checks on).
// --------------------------------------------------------------------------
const std = @import("std");
const balloid = @import("balloid.zig");
const SV = balloid.SV;
const Cfg = balloid.Cfg;

// d/dx above 16 texels a pixel only happens on sub-pixel slivers; the clamp keeps the span
// start's product in i32 and the texel mask keeps any overshoot inside the map.
const GRAD_LIM = 1 << 20;

// rcp[d] = 2^20 / d for a 28.4 extent d < 16 px: most edges of this mesh are that short.
const RCP_N = 256;
const rcp: [RCP_N]i32 = blk: {
    var t: [RCP_N]i32 = undefined;
    t[0] = 0;
    for (1..RCP_N) |d| t[d] = (1 << 20) / d;
    break :blk t;
};

/// (n << s) / d. Short extents multiply by the reciprocal when the product fits i32
/// (error < 2^-12 relative, under 1/10 px or texel over an edge); the rest divide.
inline fn ratio(n0: i32, comptime s: u5, d0: i32) i32 {
    const n = if (d0 < 0) -n0 else n0;
    const d = if (d0 < 0) -d0 else d0;
    if (d < RCP_N) {
        const r = rcp[@intCast(d)];
        const an = if (n < 0) -n else n;
        switch (s) {
            16 => if (an < d << 11) return (n * r) >> 4,
            15 => if (an < d << 11) return (n * r) >> 5,
            4 => if (an < d << 15) return ((n >> 4) * r) >> 12,
            else => @compileError("ratio: shift not tabled"),
        }
    }
    return @divTrunc(n << s, d);
}

/// Value at row offset d16 (1/16 px past the edge's start) of a quantity stepping `step` a
/// row. Whole rows plus a 4-bit fraction, so no product leaves i32: d16 < the edge's dy.
inline fn prestep(base: i32, step: i32, d16: i32) i32 {
    return base + (d16 >> 4) * step + (((d16 & 15) * step) >> 4);
}

// One chain of the polygon: the current edge from vertex `i` to the next one down.
const Side = struct {
    i: usize,
    end: i32 = 0, // the edge's bottom y (28.4)
    x: i32 = 0,
    dx: i32 = 0,
    u: i32 = 0,
    du: i32 = 0,
    v: i32 = 0,
    dv: i32 = 0,
};

// Move `s` to the edge that contains row centre ys and set it up. Front faces wind so that
// the left chain runs forward through the vertices and the right chain backward.
fn setSide(s: *Side, p: []const *const SV, comptime fwd: bool, comptime uv: bool, ys: i32) void {
    const n = p.len;
    var nx = if (fwd) (s.i + 1) % n else (s.i + n - 1) % n;
    while (ys >= p[nx].y) {
        s.i = nx;
        nx = if (fwd) (nx + 1) % n else (nx + n - 1) % n;
    }
    const a = p[s.i];
    const b = p[nx];
    const dy = b.y - a.y; // > 0: a.y <= ys < b.y
    s.end = b.y;
    s.dx = ratio(b.x - a.x, 16, dy);
    s.x = prestep(a.x << 12, s.dx, ys - a.y);
    if (uv) {
        s.du = ratio(b.u - a.u, 4, dy);
        s.dv = ratio(b.v - a.v, 4, dy);
        s.u = prestep(a.u, s.du, ys - a.y);
        s.v = prestep(a.v, s.dv, ys - a.y);
    }
}

// Constant d/dx of (u, v) from one triangle, read off its widest row (at the middle
// vertex): the long edge's point there minus the middle vertex.
pub fn gradients(p0: *const SV, p1: *const SV, p2: *const SV) [2]i32 {
    var a = p0;
    var b = p1;
    var d = p2;
    if (b.y < a.y) std.mem.swap(*const SV, &a, &b);
    if (d.y < a.y) std.mem.swap(*const SV, &a, &d);
    if (d.y < b.y) std.mem.swap(*const SV, &b, &d);
    const hy = d.y - a.y;
    if (hy == 0) return .{ 0, 0 };
    const t15 = ratio(b.y - a.y, 15, hy);
    const w = a.x + ((d.x - a.x) * t15 >> 15) - b.x; // 28.4
    if (w == 0) return .{ 0, 0 };
    const ul = a.u + (((d.u - a.u) >> 8) * t15 >> 7);
    const vl = a.v + (((d.v - a.v) >> 8) * t15 >> 7);
    return .{
        std.math.clamp(ratio(ul - b.u, 4, w), -GRAD_LIM, GRAD_LIM),
        std.math.clamp(ratio(vl - b.v, 4, w), -GRAD_LIM, GRAD_LIM),
    };
}

// (num << 11) / den without overflow: the remainder is shifted only as far as it fits.
fn div11(num: i32, den: i32) i32 {
    const q = std.math.clamp(@divTrunc(num, den), -(1 << 9), 1 << 9); // |result| <= 2^20
    const r = num - q * den;
    if (@abs(r) >= @abs(den)) return q << 11; // clamped: a sliver, the value is moot
    const hr: u5 = @intCast(@min(11, @as(u32, @clz(@abs(den))) - 1));
    return (q << 11) + (@divTrunc(r << hr, den) << (11 - hr));
}

/// d/dx of (u, v) for a convex quad from its two diagonals AC and BD: they cross, so the
/// system is well conditioned even for the long thin strips this mesh makes edge-on
/// (each half alone is a sliver there). Inputs at reduced precision (u >> 7) so the
/// products fit i32.
pub fn quadGradients(a: *const SV, b: *const SV, c: *const SV, d: *const SV) [2]i32 {
    const x1 = c.x - a.x;
    const y1 = c.y - a.y;
    const x2 = d.x - b.x;
    const y2 = d.y - b.y;
    const den = x1 * y2 - x2 * y1;
    if (den == 0) return .{ 0, 0 };
    const ua = (c.u - a.u) >> 7;
    const ub = (d.u - b.u) >> 7;
    const va = (c.v - a.v) >> 7;
    const vb = (d.v - b.v) >> 7;
    return .{ div11(ua * y2 - ub * y1, den), div11(va * y2 - vb * y1, den) };
}

/// A front-facing convex polygon (3 or 4 vertices in mesh order) with constant d/dx `g`
/// (from `gradients`); the left chain carries u,v exactly, so neighbouring
/// polygons meet without seams on their shared left edges.
pub fn poly(p: []const *const SV, g: [2]i32, env: [*]const u16, pix: [*]align(4) u16, stride: usize, c: *const Cfg) void {
    var top: usize = 0;
    var bot: usize = 0;
    var minx = p[0].x;
    var maxx = p[0].x;
    for (p[1..], 1..) |q, i| {
        if (q.y < p[top].y) top = i;
        if (q.y > p[bot].y) bot = i;
        minx = @min(minx, q.x);
        maxx = @max(maxx, q.x);
    }
    if ((maxx + 7) >> 4 <= c.x0 or (minx + 7) >> 4 >= c.x1) return; // wholly outside the box
    var y = @max((p[top].y + 7) >> 4, c.y0); // first row whose centre is at or below the top
    const ye = @min((p[bot].y + 7) >> 4, c.y1);
    if (y >= ye) return;
    const dudx8 = g[0] >> 8; // for the span start's sub-pixel offset
    const dvdx8 = g[1] >> 8;
    // Packed per-pixel step: (du << 16) + dv in 6.10; wrapping adds keep it exact.
    const step: u32 = (@as(u32, @bitCast(g[0] >> 6)) << 16) +% @as(u32, @bitCast(g[1] >> 6));
    var l = Side{ .i = top };
    var r = Side{ .i = top };
    setSide(&l, p, true, true, y * 16 + 8);
    setSide(&r, p, false, false, y * 16 + 8);
    var row: [*]u16 = pix + @as(usize, @intCast(y)) * stride;
    while (y < ye) : (y += 1) {
        const ys = y * 16 + 8;
        if (ys >= l.end) setSide(&l, p, true, true, ys);
        if (ys >= r.end) setSide(&r, p, false, false, ys);
        const x0 = @max((l.x + 0x7FFF) >> 16, c.x0);
        const x1 = @min((r.x + 0x7FFF) >> 16, c.x1);
        if (x0 < x1) {
            const off = ((x0 << 16) + 0x8000 - l.x) >> 8; // >= 0: x0's centre past the edge
            const u = l.u + off * dudx8;
            const v = l.v + off * dvdx8;
            const uv: u32 = (@as(u32, @bitCast(u >> 6)) << 16) +% @as(u32, @bitCast(v >> 6));
            span(row, @intCast(x0), @intCast(x1 - x0), uv, step, env);
        }
        l.x += l.dx;
        l.u += l.du;
        l.v += l.dv;
        r.x += r.dx;
        row += stride;
    }
}

// Texel at a packed u,v: u's integer is the top 6 bits, v's is bits 10..15. A sub-pixel
// overshoot wraps to the opposite rim (the same dark rim colour in both env maps).
inline fn texel(env: [*]const u16, uv: u32) u32 {
    return env[(uv >> 26) | ((uv >> 4) & 0xFC0)];
}

// Pixel pairs as one aligned u32 store (row base 4-aligned: pixels align(4), stride even);
// an odd first pixel and an odd last pixel are single u16 stores.
inline fn span(row: [*]u16, x0: usize, n0: usize, uv0: u32, step: u32, env: [*]const u16) void {
    var uv = uv0;
    var x = x0;
    var n = n0;
    if (x & 1 != 0) {
        row[x] = @intCast(texel(env, uv));
        uv +%= step;
        x += 1;
        n -= 1;
    }
    const q: [*]u32 = @ptrCast(@alignCast(row + x));
    const step2 = step *% 2;
    for (0..n >> 1) |i| {
        q[i] = texel(env, uv) | texel(env, uv +% step) << 16; // left pixel in the low half
        uv +%= step2;
    }
    if (n & 1 != 0) row[x + n - 1] = @intCast(texel(env, uv));
}
