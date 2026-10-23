// --------------------------------------------------------------------------
// The cube phases: $fa4 + $10fc's projection in exact 68k word math, and
// $6282/$58fa's striped triangle fill. All integer (see hmdfac.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

/// The 8 vertices, BE words at $189c2: the near 256px square at z=+120 and
/// the far 96px square at z=-56, same centre — a five-face frustum.
const VERTS = [8][3]i16{
    .{ -136, -136, 120 }, // $189c2
    .{ -136, 120, 120 }, // $189c8
    .{ 120, 120, 120 }, // $189ce
    .{ 120, -136, 120 }, // $189d4
    .{ -56, 40, -56 }, // $189da
    .{ 40, 40, -56 }, // $189e0
    .{ 40, -56, -56 }, // $189e6
    .{ -56, -56, -56 }, // $189ec
};
/// The five faces at $189f2, 16 B each: four (vertex, vertex) pairs then
/// the 16-bit pattern word. The fill machinery consumes the first vertex
/// of the first three pairs, so TRI is the geometric triangle and PAT the
/// pairing word: face 0 = (6,5)(5,4)(4,7)(7,6) $000f, face 1 =
/// (0,1)(1,2)(2,3)(3,0) $0002, face 2 = (3,2)(2,5)(5,6)(6,3) $000d,
/// face 3 = (7,4)(4,1)(1,0)(0,7) $000e, face 4 = (1,4)(4,5)(5,2)(2,1) $0007.
const TRI = [5][3]u8{ .{ 6, 5, 4 }, .{ 0, 1, 2 }, .{ 3, 2, 5 }, .{ 7, 4, 1 }, .{ 1, 4, 5 } };
const PAT = [5]u8{ 15, 2, 13, 14, 7 };
/// $58fa's ink per pattern word: {15:14, 2:6, 13:13, 14:9, 7:8}.
const INK = [5]u8{ 14, 6, 13, 9, 8 };
/// The three consecutive edges of each triangle (pts[i] -> pts[i+1]).
const EDGE = [3][2]usize{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 0 } };

pub const Proj = [VERTS.len][2]i16;

/// The wheel and camera state one frame's projection reads.
pub const Wheel = struct { ca: u16, cb: u16, cc: u16, camera: u32, sy: u16, sx: u16 };

fn low16(v: i64) u16 {
    return @truncate(@as(u64, @bitCast(v)));
}

fn s16v(u: u16) i16 {
    return @bitCast(u);
}

/// A Q9 matrix entry: the product's low 16 bits, read signed — the register
/// word the machine's next instructions see.
fn mword(v: i64) i16 {
    return s16v(low16(v));
}

/// divs.w: quotient truncates toward zero; a zero divisor or an out-of-range
/// quotient leaves the destination register (the dividend) untouched.
fn divsDest(a: i64, b: i16) i64 {
    if (b == 0) return a;
    const q = @divTrunc(a, @as(i64, b));
    if (q < -32768 or q > 32767) return a;
    return q;
}

fn sinw(c: u16, off: usize) i64 {
    return s16v(A.sine[(@as(usize, c) >> 1) + off]);
}

/// The 9-word Q9 matrix; >>9 is the 68000 asr (floor).
fn matrix(w: Wheel) [9]i16 {
    const coA = sinw(w.ca, 0);
    const sA = sinw(w.ca, 360);
    const coB = sinw(w.cb, 0);
    const sB = sinw(w.cb, 360);
    const coC = sinw(w.cc, 0);
    const sC = sinw(w.cc, 360);
    const t4 = (coC * sB) >> 9;
    const t7 = (sC * sB) >> 9;
    return .{
        mword(-sB),                 mword((coB * sA) >> 9),                         mword((coB * coA) >> 9),
        mword((coC * coB) >> 9),    mword(((t4 * sA) >> 9) - ((sC * coA) >> 9)),    mword(((t4 * coA) >> 9) + ((sC * sA) >> 9)),
        mword((sC * coB) >> 9),     mword(((t7 * sA) >> 9) + ((coC * coA) >> 9)),   mword(((t7 * coA) >> 9) - ((coC * sA) >> 9)),
    };
}

/// All eight vertices projected to art-local (sy, sx), exact 68k semantics.
pub fn project(w: Wheel) Proj {
    const m = matrix(w);
    var proj: Proj = undefined;
    for (VERTS, 0..) |v, n| {
        const x0: i64 = v[0];
        const y0: i64 = v[1];
        const z0: i64 = v[2];
        const dot0 = x0 * m[0] + y0 * m[1] + z0 * m[2];
        const depth = low16(-(dot0 >> 8)); // asr #8, then neg.l
        const dist: i16 = @bitCast(@as(u16, @truncate(w.camera)) -% depth);
        const sy_reg = divsDest(x0 * m[3] + y0 * m[4] + z0 * m[5], dist);
        const sx_reg = divsDest(x0 * m[6] + y0 * m[7] + z0 * m[8], dist);
        // add.w the queue's pair, 16-bit wraps, then read signed
        proj[n] = .{ s16v(low16(sy_reg) +% w.sy), s16v(low16(sx_reg) +% w.sx) };
    }
    return proj;
}

/// Rows [lo, hi] a fill touched; lo > hi = none.
pub const Rows = struct { lo: i32 = 0, hi: i32 = -1 };

/// The faces in reverse file order; a row paints only when the face's pattern
/// word has bit (y&3) set. Returns the rows drawn on. Crossings are integer.
pub fn drawFaces(d: blit.Dst, proj: Proj) Rows {
    var dirty = Rows{};
    var fi: usize = TRI.len;
    while (fi > 0) {
        fi -= 1;
        const t = TRI[fi];
        const p = [3][2]i32{ .{ proj[t[0]][0], proj[t[0]][1] }, .{ proj[t[1]][0], proj[t[1]][1] }, .{ proj[t[2]][0], proj[t[2]][1] } };
        // $58fa's facing test (i64: the products exceed 16 bits)
        const cross = @as(i64, p[2][1] - p[0][1]) * (p[1][0] - p[0][0]) - @as(i64, p[2][0] - p[0][0]) * (p[1][1] - p[0][1]);
        if (cross >= 0) continue;
        const ylo: i32 = @max(@min(@min(p[0][0], p[1][0]), p[2][0]), 0);
        const yhi: i32 = @min(@max(@max(p[0][0], p[1][0]), p[2][0]), A.ART_H - 1);
        var y: i32 = ylo;
        while (y <= yhi) : (y += 1) {
            if (((PAT[fi] >> @intCast(y & 3)) & 1) == 0) continue;
            var xl: i64 = X_MAX;
            var xr: i64 = X_MIN;
            var n: usize = 0;
            for (EDGE) |e| {
                const ay = p[e[0]][0];
                const by = p[e[1]][0];
                if (ay == by or y < @min(ay, by) or y >= @max(ay, by)) continue;
                const num = @as(i64, y - ay) * (p[e[1]][1] - p[e[0]][1]);
                const x = p[e[0]][1] + @divTrunc(num, by - ay);
                xl = @min(xl, x);
                xr = @max(xr, x);
                n += 1;
            }
            if (n < 2) continue;
            const x0: i64 = @max(xl, 0);
            const x1: i64 = @min(xr + 1, A.ART_W);
            if (x0 >= x1) continue;
            d.fill(@intCast(x0), y, @intCast(x1 - x0), 1, INK[fi]);
            if (dirty.lo > dirty.hi) dirty = .{ .lo = y, .hi = y } else {
                dirty.lo = @min(dirty.lo, y);
                dirty.hi = @max(dirty.hi, y);
            }
        }
    }
    return dirty;
}

const X_MAX: i64 = 1 << 40;
const X_MIN: i64 = -(1 << 40);
