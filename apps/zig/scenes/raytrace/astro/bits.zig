// ZIGGY's side of mode 3: f64 values read and compared by their BITS, integer ops
// only (as COPRO page 5 scans its escape test). hwAstro has no per-element compare,
// select or convert, so every decision between two calls (hit or not, which sphere,
// floor or sky, shadowed or lit) and every Shade field is taken here, with no FPU op
// and no soft-float call on ZIGGY. Pure: bits_test.zig.

/// An f64 constant's bits, at compile time.
pub fn of(comptime x: f64) u64 {
    return @bitCast(x);
}

/// An f64 array's words.
pub fn words(a: [*]f64) [*]u64 {
    return @ptrCast(a);
}

/// A signed integer that orders as the f64 does (sign-magnitude to two's complement;
/// -0 and +0 are both 0). NaN orders past the infinities, by its sign.
pub fn key(b: u64) i64 {
    const s: i64 = @bitCast(b);
    return if (s >= 0) s else -(s & 0x7FFF_FFFF_FFFF_FFFF);
}

pub fn lt(a: u64, b: u64) bool {
    return key(a) < key(b);
}

/// Whether x <= 0 (or -0).
pub fn notPositive(b: u64) bool {
    return key(b) <= 0;
}

/// Whether x is +0 or -0.
pub fn isZero(b: u64) bool {
    return b << 1 == 0;
}

/// trunc(x), clamped to +-2^30.
pub fn trunc(b: u64) i32 {
    const e: i32 = @intCast((b >> 52) & 0x7FF);
    if (e < 1023) return 0;
    const sh = e - 1023;
    const neg = b >> 63 != 0;
    if (sh >= 30) return if (neg) -(1 << 30) else 1 << 30;
    const m = (b & ((1 << 52) - 1)) | (1 << 52);
    const v: i32 = @intCast(m >> @intCast(52 - sh));
    return if (neg) -v else v;
}

/// floor(x), for |x| < 2^30: trunc, one lower for a negative x with a fraction.
pub fn floor(b: u64) i32 {
    const t = trunc(b);
    if (b >> 63 == 0) return t;
    const e: i32 = @intCast((b >> 52) & 0x7FF);
    if (e == 0 and b << 1 == 0) return 0; // -0
    if (e < 1023) return -1; // -1 < x < 0
    const sh = e - 1023;
    if (sh >= 52) return t;
    const frac = b & ((@as(u64, 1) << @intCast(52 - sh)) - 1);
    return if (frac != 0) t - 1 else t;
}

/// An intensity already scaled by 256 (the descriptors fold the 256 in), as the tracer's
/// toQ8 makes it: floor, clamped to 0..256.
pub fn q8(b: u64) u16 {
    if (notPositive(b)) return 0;
    return @intCast(@min(trunc(b), 256));
}
