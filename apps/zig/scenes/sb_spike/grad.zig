// --------------------------------------------------------------------------
// SB SPIKE: a triangle's texture plane (du/dx, du/dy, dv/dx, dv/dy) without 64-bit maths.
//
// d/dx = num / area with num = d1 * ac.y - d2 * ab.y (deltas 8.8 texels, positions Q4,
// area Q8): 16.16 texels a pixel is (num << 12) / area. One u32 divide a triangle
// gives inv = 2^31 / |area|; while the triangle is under 512 px (positions under 2^13
// Q4) every num fits an i32, so each gradient is ONE 32 x 32 -> 64 multiply and a
// shift (~20 cycles in apps/perf/cost_model.mjs; normalising num and inv with clz
// to stay in 32 bits measured ~25 % dearer: rv32im has no clz). A triangle reaching
// far off screen takes the all-64-bit path.
// No ZigOS import.
// --------------------------------------------------------------------------
pub const Grad = struct { dudx: u32, dudy: u32, dvdx: u32, dvdy: u32 };
pub const V2 = [2]i32; // a Q4 edge vector
const BIG: i32 = 1 << 13;

/// The plane over vertices a, b, c (b - a = ab, c - a = ac, both Q4), its texel
/// deltas du = (ub - ua, uc - ua), dv likewise (8.8), area = ab x ac (Q8, non-zero).
pub fn plane(ab: V2, ac: V2, du: V2, dv: V2, area: i64) Grad {
    const small = @abs(ab[0]) < BIG and @abs(ab[1]) < BIG and @abs(ac[0]) < BIG and @abs(ac[1]) < BIG;
    if (!small or @abs(area) >= (1 << 30)) return exact(ab, ac, du, dv, area);
    const inv: i64 = @as(u32, 1 << 31) / @as(u32, @intCast(@abs(area))); // the one divide
    const k = Recip{ .inv = if (area < 0) -inv else inv };
    return .{
        .dudx = k.mul(du[0] * ac[1] - du[1] * ab[1]),
        .dudy = k.mul(du[1] * ab[0] - du[0] * ac[0]),
        .dvdx = k.mul(dv[0] * ac[1] - dv[1] * ab[1]),
        .dvdy = k.mul(dv[1] * ab[0] - dv[0] * ac[0]),
    };
}

const Recip = struct {
    inv: i64, // +-2^31 / area

    /// (num << 12) / area = num * inv >> 19: one 32 x 32 -> 64 multiply (num fits an i32).
    inline fn mul(k: Recip, num: i32) u32 {
        return @bitCast(@as(i32, @truncate((@as(i64, num) * k.inv) >> 19)));
    }
};

/// The 64-bit path for triangles reaching far off screen.
fn exact(ab: V2, ac: V2, du: V2, dv: V2, area: i64) Grad {
    const s: u6 = if (@abs(area) >= (1 << 31)) 2 else 0;
    const ar: u32 = @intCast(@abs(area) >> (2 * s));
    const inv: i64 = @as(u32, 1 << 31) / @max(ar, 1);
    const sh: u6 = 19 + s;
    const f = struct {
        fn g(d1: i32, d2: i32, p1: i32, p2: i32, iv: i64, shift: u6, ss: u6, neg: bool) u32 {
            const num = @as(i64, d1) * (p1 >> @intCast(ss)) - @as(i64, d2) * (p2 >> @intCast(ss));
            var v: i32 = @truncate((num * iv) >> shift);
            if (neg) v = -%v;
            return @bitCast(v);
        }
    }.g;
    const n = area < 0;
    return .{
        .dudx = f(du[0], du[1], ac[1], ab[1], inv, sh, s, n),
        .dudy = f(du[1], du[0], ab[0], ac[0], inv, sh, s, n),
        .dvdx = f(dv[0], dv[1], ac[1], ab[1], inv, sh, s, n),
        .dvdy = f(dv[1], dv[0], ab[0], ac[0], inv, sh, s, n),
    };
}
