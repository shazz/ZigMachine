// --------------------------------------------------------------------------
// OBJ demo: the per-frame 3D in integers (no float per frame, CLAUDE.md).
//
// Vertices and normals are Q14 (16384 = the model's unit radius), the rotation
// is a Q14 matrix built once a frame from three u32 angles (a full turn is
// 2^32) through an interpolated Q16 sine table made at compile time, and the
// perspective is one u32 divide per vertex. The maths is the old f32 path's
// (rotate about x, then y, then z; screen = centre + p * FOV / (z + DIST)),
// so the picture only moves where rounding lands on the other side of a pixel.
// No ZigOS import: obj/tests.zig tests it natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Q = 14;
pub const ONE: i32 = 1 << Q;
pub const Angle = u32;
pub const Vec3 = [3]i32;
pub const Mat = [3][3]i32; // rows, Q14
/// A stored vertex or normal: Q14 x, y, z and a pad, 8 bytes so arrays of them
/// stay word-aligned (a misaligned word access traps on the board).
pub const V = [4]i16;

pub const DIST: i32 = 52429; // 3.2 in Q14: the eye sits at z = -DIST
pub const FOV: u32 = 150;
pub const CX: i32 = 160;
pub const CY: i32 = 100;

const BITS = 12; // 4096 entries a turn, linearly interpolated
const N = 1 << BITS;
const FRAC = 32 - BITS;

const SIN: [N + 1]i32 = blk: {
    @setEvalBranchQuota(N * 200);
    var t: [N + 1]i32 = undefined;
    for (&t, 0..) |*v, i| {
        const a = @as(f64, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f64, N));
        v.* = @intFromFloat(@round(@sin(a) * 65536.0));
    }
    t[0] = 0;
    t[N / 4] = 65536;
    t[N / 2] = 0;
    t[3 * N / 4] = -65536;
    t[N] = 0;
    break :blk t;
};

/// sin(a) in Q16.
pub fn sin16(a: Angle) i32 {
    const i = a >> FRAC;
    const f: i32 = @intCast((a >> (FRAC - 16)) & 0xFFFF);
    const s0 = SIN[i];
    return s0 + (((SIN[i + 1] - s0) * f) >> 16);
}
pub fn cos16(a: Angle) i32 {
    return sin16(a +% (1 << 30));
}

/// A compile-time angle in radians as an Angle.
pub fn angle(comptime rad: f64) Angle {
    const raw: i64 = @intFromFloat(@round(rad / (2.0 * std.math.pi) * 4294967296.0));
    return @truncate(@as(u64, @bitCast(raw)));
}

fn m16(a: i32, b: i32) i32 {
    return @truncate((@as(i64, a) * b) >> 16);
}

/// The old project()'s three rotations, applied to v (Q16 trig, Q16 vector).
fn turn(v: Vec3, s: [3]i32, c: [3]i32) Vec3 {
    const y1 = m16(v[1], c[0]) - m16(v[2], s[0]);
    const z1 = m16(v[1], s[0]) + m16(v[2], c[0]);
    const x2 = m16(v[0], c[1]) + m16(z1, s[1]);
    const z2 = -m16(v[0], s[1]) + m16(z1, c[1]);
    return .{ m16(x2, c[2]) - m16(y1, s[2]), m16(x2, s[2]) + m16(y1, c[2]), z2 };
}

/// The rotation as a Q14 matrix: its columns are the turned unit axes.
pub fn rotation(ax: Angle, ay: Angle, az: Angle) Mat {
    const s = [3]i32{ sin16(ax), sin16(ay), sin16(az) };
    const c = [3]i32{ cos16(ax), cos16(ay), cos16(az) };
    var m: Mat = undefined;
    for (0..3) |col| {
        var e = Vec3{ 0, 0, 0 };
        e[col] = 65536;
        const t = turn(e, s, c);
        for (0..3) |row| m[row][col] = (t[row] + 2) >> 2;
    }
    return m;
}

/// m * v, both Q14 (|v| <= 2 so no product overflows).
pub inline fn apply(m: *const Mat, v: V) Vec3 {
    var r: Vec3 = undefined;
    for (0..3) |k| r[k] = (m[k][0] * v[0] + m[k][1] * v[1] + m[k][2] * v[2]) >> Q;
    return r;
}

/// The light in object space: mᵀ L, so a face's light is n · (mᵀ L), 3 muls.
pub fn lightInObject(m: *const Mat, l: Vec3) Vec3 {
    var r: Vec3 = undefined;
    for (0..3) |k| r[k] = (m[0][k] * l[0] + m[1][k] * l[1] + m[2][k] * l[2]) >> Q;
    return r;
}

pub inline fn dot(a: V, b: Vec3) i32 {
    return (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) >> Q;
}

/// (0.36, 0.48, -0.80) in Q14: the old LIGHT, unit length.
pub const LIGHT = Vec3{ 5898, 7864, -13107 };

/// Screen point of a rotated vertex: floor(centre + p * FOV / (z + DIST)),
/// through one u32 reciprocal (FOV << 23 / depth) and two 32-bit products
/// (|p| <= 16400 and inv <= 76800 while depth >= 1.0: no overflow).
pub inline fn project(p: Vec3) [2]i16 {
    const depth: u32 = @intCast(@max(p[2] + DIST, ONE));
    const inv: i32 = @intCast((@as(u32, FOV) << 23) / depth);
    return .{ @intCast(CX + ((p[0] * inv) >> 23)), @intCast(CY + ((p[1] * inv) >> 23)) };
}

/// Twice the signed screen area of a triangle; > 0 when it faces the eye
/// (for a face wound counter-clockwise seen from outside; screen y grows down).
pub inline fn area2(a: [2]i16, b: [2]i16, c: [2]i16) i32 {
    const abx: i32 = @as(i32, b[0]) - a[0];
    const aby: i32 = @as(i32, b[1]) - a[1];
    const acx: i32 = @as(i32, c[0]) - a[0];
    const acy: i32 = @as(i32, c[1]) - a[1];
    return acx * aby - abx * acy;
}
