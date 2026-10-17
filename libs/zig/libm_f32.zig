// --------------------------------------------------------------------------
// Pure-f32 sinf / cosf / sincosf for the carts.
//
// WHY: Zig lowers an f32 @sin/@cos to compiler-rt's sinf/cosf, the
// musl ports, which do their range reduction and their polynomials in f64. The
// board's cart CPU (ZIGGY, rv32imf) has a SINGLE-precision FPU, so every one of
// those f64 operations is a libgcc soft-float call: about a thousand cycles a
// sin. These versions use only f32 arithmetic and integer ops (the FPU's own
// instructions on the board, plain wasm f32 ops in the browser), so both run
// the same code and stay bit-identical to each other.
//
// Method (Cephes sinf/cosf polynomials, reduced by quadrant):
//   n = nearest(x * 2/pi); r = x - n*pi/2 with pi/2 split four ways
//   (Cody-Waite: the first three parts carry <= 12 bits so n*part is exact
//   for |n| < 2^12), kept as hi + lo so the rounding of r is not lost; then a
//   minimax polynomial on |r| <= pi/4 plus the first-order lo correction.
// Accuracy for |x| < REDUCE_MAX (libm_f32_test.zig): see the bounds there.
// Above it the reduction is done in f64 (rare: an angle that big is a bug or
// a test), exact up to 1.6e6 and bounded in [-1, 1] beyond.
//
// tanf is left to compiler-rt on purpose: carts only call @tan once, to set
// up a projection, so it costs nothing per frame, and a Cephes tanf (~3 ulp)
// would move those projections for no gain.
//
// apps/zig/demo_main.zig exports these under the C names with STRONG linkage,
// which beats compiler-rt's weak definitions at link time.
// --------------------------------------------------------------------------
const std = @import("std");

const TWO_OVER_PI: f32 = 0.6366197466850281;
// pi/2 = C1 + C2 + C3 + C4 (12, 9, 11 and 24 significant bits).
const C1: f32 = 0x1.92p+0;
const C2: f32 = 0x1.fb4p-12;
const C3: f32 = 0x1.444p-24;
const C4: f32 = 0x1.68c234p-39;

/// Above this |x| the f32 reduction would lose bits (n reaches 2^12).
pub const REDUCE_MAX: f32 = 6000.0;
const TINY_BITS: u32 = 0x39800000; // 2^-12: sin x == x, cos x == 1 in f32

/// x = q * pi/2 + hi + lo, |hi| <= ~pi/4, |lo| <= ulp(hi).
const Reduced = struct { hi: f32, lo: f32, q: u32 };

fn reduce(x: f32) Reduced {
    if (@abs(x) >= REDUCE_MAX) return reduceBig(x);
    const y = x * TWO_OVER_PI;
    const n: i32 = @intFromFloat(y + (if (y < 0) @as(f32, -0.5) else 0.5));
    const f: f32 = @floatFromInt(n);
    const t = (x - f * C1) - f * C2; // exact: both steps cancel onto x's grid
    const p3 = f * C3; // exact (11 + 12 bits)
    const p4 = f * C4;
    // TwoSum t - p3, then Fast2Sum the small p4 in.
    const s = t - p3;
    const bb = s - t;
    const e = (t - (s - bb)) - (p3 + bb);
    const hi = s - p4;
    const lo = ((s - hi) - p4) + e;
    return .{ .hi = hi, .lo = lo, .q = @bitCast(n) };
}

// f64 reduction for huge |x| (musl's medium-path constants, 33-bit parts).
// One step is exact for |x| < 2^20 * pi/2; beyond, repeated steps keep
// |r| < 0.8 so the result stays bounded (f32 spacing there is >= 4 radians).
fn reduceBig(x: f32) Reduced {
    var r: f64 = x;
    var q: u32 = 0;
    while (@abs(r) > 0.8) {
        const nd = @round(r * 6.36619772367581382433e-01);
        r = (r - nd * 1.57079632673412561417e+00) - nd * 6.07710050650619224932e-11;
        q +%= @intFromFloat(@mod(nd, 4.0));
    }
    const hi: f32 = @floatCast(r);
    return .{ .hi = hi, .lo = @floatCast(r - hi), .q = q };
}

// sin(hi + lo) for |hi| <= pi/4 (Cephes sinf coefficients; + lo * cos hi).
fn kSin(red: Reduced) f32 {
    const r = red.hi;
    const z = r * r;
    const p = (-1.9515295891e-4 * z + 8.3321608736e-3) * z - 1.6666654611e-1;
    return r + (p * z * r + red.lo * (1.0 - 0.5 * z));
}

// cos(hi + lo) for |hi| <= pi/4 (Cephes cosf coefficients; - lo * sin hi).
fn kCos(red: Reduced) f32 {
    const r = red.hi;
    const z = r * r;
    const p = (2.443315711809948e-5 * z - 1.388731625493765e-3) * z + 4.166664568298827e-2;
    return (p * z * z - red.lo * r) - 0.5 * z + 1.0;
}

fn tinyOrNan(x: f32) bool {
    const ix: u32 = @as(u32, @bitCast(x)) & 0x7fffffff;
    return ix < TINY_BITS or ix >= 0x7f800000;
}

pub fn sin(x: f32) f32 {
    if (tinyOrNan(x)) return if (std.math.isFinite(x)) x else x - x;
    const red = reduce(x);
    return switch (red.q & 3) {
        0 => kSin(red),
        1 => kCos(red),
        2 => -kSin(red),
        else => -kCos(red),
    };
}

pub fn cos(x: f32) f32 {
    if (tinyOrNan(x)) return if (std.math.isFinite(x)) 1.0 else x - x;
    const red = reduce(x);
    return switch (red.q & 3) {
        0 => kCos(red),
        1 => -kSin(red),
        2 => -kCos(red),
        else => kSin(red),
    };
}

pub fn sincos(x: f32, s: *f32, c: *f32) void {
    if (tinyOrNan(x)) {
        s.* = if (std.math.isFinite(x)) x else x - x;
        c.* = if (std.math.isFinite(x)) 1.0 else x - x;
        return;
    }
    const red = reduce(x);
    const ks = kSin(red);
    const kc = kCos(red);
    const q = red.q & 3;
    s.* = switch (q) {
        0 => ks,
        1 => kc,
        2 => -ks,
        else => -kc,
    };
    c.* = switch (q) {
        0 => kc,
        1 => -ks,
        2 => -kc,
        else => ks,
    };
}

// The C-ABI entry points demo_main.zig exports.
pub fn sinf(x: f32) callconv(.c) f32 {
    return sin(x);
}
pub fn cosf(x: f32) callconv(.c) f32 {
    return cos(x);
}
pub fn sincosf(x: f32, s: *f32, c: *f32) callconv(.c) void {
    sincos(x, s, c);
}

/// Export the three with strong linkage and hidden visibility: they override
/// compiler-rt's weak symbols but do not join the cart's host export list.
/// Call from a `comptime` block in the cart's root (apps/zig/demo_main.zig).
pub fn exportAll() void {
    const hidden = std.builtin.SymbolVisibility.hidden;
    @export(&sinf, .{ .name = "sinf", .linkage = .strong, .visibility = hidden });
    @export(&cosf, .{ .name = "cosf", .linkage = .strong, .visibility = hidden });
    @export(&sincosf, .{ .name = "sincosf", .linkage = .strong, .visibility = hidden });
}
