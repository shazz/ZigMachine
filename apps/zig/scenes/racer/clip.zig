// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; his itch.io page states "Code license: MIT"), re-written in Zig integers.
// Copyright (c) freds72, MIT. The MIT licence:
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
//   associated documentation files (the "Software"), to deal in the Software without restriction,
//   including without limitation the rights to use, copy, modify, merge, publish, distribute,
//   sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
//   furnished to do so, subject to the following conditions: the above copyright notice and this
//   permission notice shall be included in all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
//   NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//   DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
//   OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// RACER: polygon clipping in view space (Q16 x, y, z; z forward), Sutherland-Hodgman against
// the near plane (z >= NEAR) and a guard band round the screen (|x| <= 3z, |y| <= 3z: 480 px past
// the edge, so every projected vertex stays inside the edge walker's i32 range). A quad gains one
// vertex a plane it crosses: at most 9.
//
// The intersection of an edge is always computed from the edge's LOWER end (lexicographic on x, y,
// z) toward the other, so two faces that share an edge cut it at the very same point: a clipped
// seam shows no gap and no double row (`--break clip` flips the direction and the harness sees it).
// Freds72's z_poly_clip is the near plane alone; the guard band is ours.
// No ZigOS import.
// --------------------------------------------------------------------------
const fx = @import("fx.zig");

pub const V3 = [3]i32;
pub const NEAR: i32 = 1 << 14; // 0.25 units
pub const MAXV = 9;
pub const Plane = enum(u3) { near, left, right, down, up };

/// Set by the harness' --break clip: intersections from the edge's first end, not its lower one.
pub var break_canonical: bool = false;

/// Set by the harness' --break clip: a polygon that needs clipping is dropped, not clipped.
pub var break_drop: bool = false;

pub const Poly = struct {
    n: usize = 0,
    p: [MAXV]V3 = undefined,
};

fn dist(pl: Plane, v: V3) i32 {
    return switch (pl) {
        .near => v[2] - NEAR,
        .left => v[0] + 3 * v[2],
        .right => 3 * v[2] - v[0],
        .down => v[1] + 3 * v[2],
        .up => 3 * v[2] - v[1],
    };
}

fn less(a: V3, b: V3) bool {
    for (a, b) |x, y| if (x != y) return x < y;
    return false;
}

fn cut(pl: Plane, a: V3, b: V3) V3 {
    const swap = if (break_canonical) false else less(b, a);
    const lo = if (swap) b else a;
    const hi = if (swap) a else b;
    const dlo: i64 = dist(pl, lo);
    const dhi: i64 = dist(pl, hi);
    const t: i32 = @intCast(@divTrunc(dlo << 16, dlo - dhi));
    var out: V3 = undefined;
    for (&out, lo, hi) |*o, l, h| o.* = l + fx.mulsh16(h - l, t);
    if (pl == .near) out[2] = NEAR;
    return out;
}

/// Clip `p` to the half space of `pl` (distance >= 0).
pub fn plane(p: *Poly, pl: Plane) void {
    var out = Poly{};
    var prev = p.p[p.n - 1];
    var dprev = dist(pl, prev);
    for (p.p[0..p.n]) |cur| {
        const dcur = dist(pl, cur);
        if ((dprev >= 0) != (dcur >= 0)) {
            out.p[out.n] = cut(pl, prev, cur);
            out.n += 1;
        }
        if (dcur >= 0) {
            out.p[out.n] = cur;
            out.n += 1;
        }
        prev = cur;
        dprev = dcur;
    }
    p.* = out;
}

/// Clip to every plane whose bit (1 << @intFromEnum) is set in `mask`; n may fall to 0.
pub fn clip(p: *Poly, mask: u8) void {
    inline for (@typeInfo(Plane).@"enum".fields) |f| {
        if (p.n != 0 and mask & (1 << f.value) != 0) plane(p, @enumFromInt(f.value));
    }
}

/// The planes a view-space vertex is outside of (bit per Plane).
pub fn outside(v: V3) u8 {
    var m: u8 = 0;
    inline for (@typeInfo(Plane).@"enum".fields) |f| {
        if (dist(@enumFromInt(f.value), v) < 0) m |= 1 << f.value;
    }
    return m;
}
