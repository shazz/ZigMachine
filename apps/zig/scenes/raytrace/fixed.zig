// Q16.16 fixed-point arithmetic for the ray tracer: the number back-end the
// FPGA cart uses (VexRiscv rv32im has no FPU, so float would be soft-float).
//
// Contract shared with float.zig (the tracer is generic over it): T, k, fromInt,
// mul, div, len3, toInt, toQ8, plus add/sub/compare which are plain operators
// on both i32 and f32.
//
//   T       i32, value = raw / 65536
//   mul     one widening 32x32->64 multiply + shift (mul/mulh on rv32im)
//   div     one 64-bit divide; the tracer calls it at most once per ray
//   len3    sqrt(x*x+y*y+z*z): three widening multiplies and sqrtQ below
//
// Ranges: the scene lives inside |v| < 64, so sums of products never overflow
// the i64 intermediates and a Q16.16 result never overflows an i32.
pub const NAME = "FIXED 16.16";
pub const T = i32;
pub const ONE: T = 1 << 16;

/// Compile-time conversion of a constant; never emits float code.
pub fn k(comptime v: f64) T {
    return @intFromFloat(@round(v * 65536.0));
}

pub fn fromInt(i: i32) T {
    return i << 16;
}

pub fn mul(a: T, b: T) T {
    return @truncate((@as(i64, a) * @as(i64, b)) >> 16);
}

pub fn div(a: T, b: T) T {
    const q = @divTrunc(@as(i64, a) << 16, @as(i64, b));
    return @intCast(@min(@max(q, -0x7fffffff), 0x7fffffff));
}

/// floor(sqrt(m)) for a u32: 16 shift/compare iterations, no multiply, no
/// divide. The caller normalises m so its top bit pair is occupied (full
/// 16-bit root).
fn isqrt32(m: u32) u32 {
    var op = m;
    var res: u32 = 0;
    var one: u32 = 1 << 30;
    while (one != 0) : (one >>= 2) {
        if (op >= res + one) {
            op -= res + one;
            res = (res >> 1) + one;
        } else res >>= 1;
    }
    return res;
}

/// Square root of a Q16.16 value given as raw u32 `v`, result Q16.16.
/// v is normalised by an even shift (a 16-bit root, relative error 2^-16),
/// rooted by isqrt32, then shifted back: sqrt(raw) * 256 = (root << 8) >> (shift / 2).
pub fn sqrtQ(v: u32) T {
    if (v == 0) return 0;
    const s: u5 = @intCast(@clz(v) & ~@as(u32, 1));
    const root = isqrt32(v << s);
    return @intCast((root << 8) >> (s >> 1));
}

pub fn len3(x: T, y: T, z: T) T {
    const sum: i64 = @as(i64, x) * x + @as(i64, y) * y + @as(i64, z) * z; // Q32.32
    const v: i64 = sum >> 16; // Q16.16 of the squared length
    return sqrtQ(@intCast(@min(v, 0xffffffff)));
}

pub fn toInt(a: T) i32 {
    return a >> 16; // arithmetic shift = floor
}

/// 0..1 mapped to 0..256, clamped.
pub fn toQ8(a: T) u32 {
    if (a <= 0) return 0;
    return @min(@as(u32, @intCast(a >> 8)), 256);
}
