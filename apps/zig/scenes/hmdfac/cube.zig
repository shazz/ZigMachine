// --------------------------------------------------------------------------
// The cube phases: $ba3e's projection in exact 68k word math and $10d1c's
// face loop (RAM addresses at load base $aa9a). The span fill itself is in
// cube_fill.zig. All integer (see hmdfac.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const F = @import("cube_fill.zig");

/// The 8 vertices, BE words at $2345c: the near 256px square at z=+120 and
/// the far 96px square at z=-56, same centre — a frustum.
const VERTS = [8][3]i16{
    .{ -136, -136, 120 }, .{ -136, 120, 120 }, .{ 120, 120, 120 }, .{ 120, -136, 120 },
    .{ -56, 40, -56 },    .{ 40, 40, -56 },    .{ 40, -56, -56 },  .{ -56, -56, -56 },
};
/// The six faces at $2348c: a count word (5), then per face n = 3, four
/// (a, b) vertex pairs and the face's COLOUR — a palette index the fill
/// expands to plane words. Each quad below is the pairs' first vertices.
const QUAD = [6][4]u8{ .{ 6, 5, 4, 7 }, .{ 0, 1, 2, 3 }, .{ 3, 2, 5, 6 }, .{ 7, 4, 1, 0 }, .{ 1, 4, 5, 2 }, .{ 7, 0, 3, 6 } };
const INK = [6]u8{ 15, 2, 13, 14, 7, 6 };

/// Projected (x, y) per vertex, plate coordinates.
pub const Proj = [VERTS.len][2]i16;

/// The wheel and camera state one frame's projection reads; (qx, qy) is the
/// frame's pair from the $210ac queue, added to (x, y).
pub const Wheel = struct { ca: u16, cb: u16, cc: u16, camera: u32, qx: u16, qy: u16 };

fn low16(v: i64) u16 {
    return @truncate(@as(u64, @bitCast(v)));
}

fn s16v(u: u16) i16 {
    return @bitCast(u);
}

fn sinw(c: u16, off: usize) i64 {
    return s16v(A.sine[(@as(usize, c) >> 1) + off]);
}

/// The 9-word Q9 matrix; >>9 is the 68000 asr (floor); each entry is the
/// low word of the product, read signed.
fn matrix(w: Wheel) [9]i16 {
    const coA = sinw(w.ca, 0);
    const sA = sinw(w.ca, 360);
    const coB = sinw(w.cb, 0);
    const sB = sinw(w.cb, 360);
    const coC = sinw(w.cc, 0);
    const sC = sinw(w.cc, 360);
    const t4 = (coC * sB) >> 9;
    const t7 = (sC * sB) >> 9;
    const m = [9]i64{
        -sB,                                    (coB * sA) >> 9,                        (coB * coA) >> 9,
        (coC * coB) >> 9,                       ((t4 * sA) >> 9) - ((sC * coA) >> 9),   ((t4 * coA) >> 9) + ((sC * sA) >> 9),
        (sC * coB) >> 9,                        ((t7 * sA) >> 9) + ((coC * coA) >> 9),  ((t7 * coA) >> 9) - ((coC * sA) >> 9),
    };
    var out: [9]i16 = undefined;
    for (m, 0..) |v, i| out[i] = s16v(low16(v));
    return out;
}

/// All eight vertices projected, exact 68k semantics (asr #8 + neg.l for the
/// depth, divs.w with the overflow rule, add.w wraps for the queue pair).
pub fn project(w: Wheel) Proj {
    const m = matrix(w);
    var proj: Proj = undefined;
    for (VERTS, 0..) |v, n| {
        const x0: i64 = v[0];
        const y0: i64 = v[1];
        const z0: i64 = v[2];
        const depth = low16(-((x0 * m[0] + y0 * m[1] + z0 * m[2]) >> 8));
        const dist: i64 = s16v(@as(u16, @truncate(w.camera)) -% depth);
        const px = F.divs(x0 * m[3] + y0 * m[4] + z0 * m[5], dist).v;
        const py = F.divs(x0 * m[6] + y0 * m[7] + z0 * m[8], dist).v;
        proj[n] = .{ s16v(low16(px) +% w.qx), s16v(low16(py) +% w.qy) };
    }
    return proj;
}

/// Plate rows [lo, hi] a frame drew on; lo > hi = none.
pub const Rows = struct { lo: i32 = 0, hi: i32 = -1 };

var tables: F.Tables = .{};

pub fn reset() void {
    tables = .{};
}

/// $10d1c: each face in file order; a face is drawn when $10394's facing
/// test on its first three vertices is negative, edges into the tables, then
/// the span fill over the face's vertex rows.
pub fn drawFaces(d: blit.Dst, p: Proj) Rows {
    var dirty = Rows{};
    for (QUAD, INK) |q, ink| {
        const a = p[q[0]];
        const b = p[q[1]];
        const c = p[q[2]];
        const facing = @as(i64, b[1] - a[1]) * (c[0] - a[0]) - @as(i64, b[0] - a[0]) * (c[1] - a[1]);
        if (facing >= 0) continue;
        var ylo: i32 = 200;
        var yhi: i32 = 0;
        for (0..4) |i| {
            const va = p[q[i]];
            const vb = p[q[(i + 1) % 4]];
            F.edge(&tables, vb[0], vb[1], va[0], va[1]);
            ylo = @min(ylo, va[1]);
            yhi = @max(yhi, va[1]);
        }
        const r = F.fill(d, &tables, ylo, yhi, ink);
        if (r[0] > r[1]) continue;
        if (dirty.lo > dirty.hi) dirty = .{ .lo = r[0], .hi = r[1] } else {
            dirty.lo = @min(dirty.lo, r[0]);
            dirty.hi = @max(dirty.hi, r[1]);
        }
    }
    return dirty;
}
