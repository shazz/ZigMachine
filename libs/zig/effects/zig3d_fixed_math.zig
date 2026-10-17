// --------------------------------------------------------------------------
// The integer arithmetic under zig3d_fixed.zig: a Q30 sine/cosine, the Euler
// XYZ rotation matrix from it, and the small helpers a projector needs.
//
// Why Q30 and not zg.fixtrig's Q16: zig3d_fixed stands in for zig3d, whose
// output is pinned to three.js's doubles. A Q16 table interpolated linearly is
// 2.6e-5 off, which on a 150-unit cube is 0.004 px: enough to move a rounded
// vertex a whole pixel every few frames. Here a quarter-wave table of Q30
// values is refined by the angle's remainder d (< 2*pi/1024) with
// sin(A + d) = sin A cos d + cos A sin d, cos d = 1 - d^2/2, sin d = d - d^3/6:
// the terms left out are under 6e-11, and the whole result is within a few
// 2^-30 of the true sine. The cost is a handful of 32x32->64 multiplies, the
// kind an rv32im does in two instructions, against fdlibm's soft-float sin.
//
//   Angle   u32, one turn = 2^32 (a u64 phase's top word: see Spin)
//   Q30     1.0 = 2^30, for sines and matrix entries
//
// No ZigOS import: zig3d_fixed_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const ONE30: i32 = 1 << 30;
pub const Angle = u32;

/// sin(k * 2pi / 1024) for k = 0..256, Q30. Rounded integers, so the
/// compiler's float sine (comptime) cannot leak into a result.
const QUARTER: [257]i32 = blk: {
    @setEvalBranchQuota(20_000);
    var t: [257]i32 = undefined;
    for (&t, 0..) |*v, k| v.* = @intFromFloat(@round(@sin(@as(f64, @floatFromInt(k)) * std.math.pi / 512.0) * 1073741824.0));
    t[0] = 0;
    t[256] = ONE30;
    break :blk t;
};

/// sin(i * 2pi / 1024), Q30, for any i (taken mod 1024).
fn tableSin(i: u32) i32 {
    const k = i & 255;
    return switch ((i >> 8) & 3) {
        0 => QUARTER[k],
        1 => QUARTER[256 - k],
        2 => -QUARTER[k],
        else => -QUARTER[256 - k],
    };
}

// pi/2 in Q29: the remainder's 22 bits, times 2pi/2^32 rad, in Q30, is lo*pi/2.
const HALF_PI_Q29: i64 = 843314857;
const THIRD_Q30: i64 = 357913941; // 2^30 / 3

pub const SinCos = struct { s: i32, c: i32 };

/// sin and cos of `a`, Q30, within a few 2^-30.
pub fn sinCos(a: Angle) SinCos {
    const i = a >> 22;
    const s0: i64 = tableSin(i);
    const c0: i64 = tableSin(i + 256);
    const d: i64 = (@as(i64, a & 0x3F_FFFF) * HALF_PI_Q29 + (1 << 28)) >> 29; // Q30 radians, < 6.6e6
    const half_d2 = (d * d) >> 31; // d^2/2
    const sixth_d3 = (((half_d2 * d) >> 30) * 2 * THIRD_Q30) >> 31; // d^3/6 = (d^2/2) d / 3
    const cos_d = ONE30 - half_d2;
    const sin_d = d - sixth_d3;
    return .{
        .s = @intCast((s0 * cos_d + c0 * sin_d + (1 << 29)) >> 30),
        .c = @intCast((c0 * cos_d - s0 * sin_d + (1 << 29)) >> 30),
    };
}

/// A compile-time angle in radians as a u64 phase (one turn = 2^64), so a
/// per-frame step accumulates with no drift a frame can see.
pub fn phase(comptime rad: f64) u64 {
    const turns = rad / (2.0 * std.math.pi);
    const x = (turns - @floor(turns)) * 18446744073709551616.0;
    return @intFromFloat(@min(@round(x), 18446744073709549568.0)); // the last f64 below 2^64
}

/// Three Euler phases (x, y, z), turned by a fixed step each frame: what
/// `rotation.x += 0.01` becomes. top() is the projector's angle.
pub const Spin = struct {
    p: [3]u64 = .{ 0, 0, 0 },

    pub fn add(self: *Spin, step: [3]u64) void {
        for (&self.p, step) |*p, s| p.* +%= s;
    }
    pub fn top(self: Spin) [3]Angle {
        var a: [3]Angle = undefined;
        for (&a, self.p) |*o, p| o.* = @truncate((p +% (1 << 31)) >> 32); // rounded
        return a;
    }
};

fn mul30(a: i64, b: i64) i64 {
    return (a * b + (1 << 29)) >> 30;
}

/// Object3D.updateMatrix's rotation (setRotationFromEuler, "XYZ"), Q30,
/// row-major: rows[r] dotted with (x, y, z) is coordinate r. zig3d's
/// Mat4.compose with three.js's own letters.
pub fn rotation(a: [3]Angle) [3][3]i32 {
    const x = sinCos(a[0]);
    const y = sinCos(a[1]);
    const z = sinCos(a[2]);
    const g: i64 = x.c;
    const d: i64 = x.s;
    const h: i64 = y.c;
    const e: i64 = y.s;
    const j: i64 = z.c;
    const f: i64 = z.s;
    const l = mul30(g, j);
    const k = mul30(g, f);
    const p = mul30(d, j);
    const q = mul30(d, f);
    const r = [9]i64{
        mul30(h, j),          -mul30(h, f),         e,
        k + mul30(p, e),      l - mul30(q, e),      -mul30(d, h),
        q - mul30(l, e),      p + mul30(k, e),      mul30(g, h),
    };
    var out: [3][3]i32 = undefined;
    for (0..3) |row| for (0..3) |col| {
        out[row][col] = @intCast(r[row * 3 + col]);
    };
    return out;
}

/// A Q30 row dotted with a Q16 vector, rounded, in Q16.
pub fn dot(row: [3]i32, x: i32, y: i32, z: i32) i32 {
    const s = @as(i64, row[0]) * x + @as(i64, row[1]) * y + @as(i64, row[2]) * z;
    return @intCast((s + (1 << 29)) >> 30);
}

/// floor(sqrt(v)), bit by bit: no float, and exact.
pub fn isqrt(v: u64) u64 {
    return std.math.sqrt(v);
}

/// A Q12 coordinate rounded half away from zero to a whole pixel and clamped
/// to +-limit: zig3d.roundClamped's job on a fixed-point value.
pub fn roundPx(v: i32, comptime limit: i32) i16 {
    const mag: i64 = @intCast((@abs(@as(i64, v)) + 2048) >> 12);
    const r: i64 = if (v < 0) -mag else mag;
    return @intCast(std.math.clamp(r, -limit, limit));
}
