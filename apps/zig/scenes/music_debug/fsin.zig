// --------------------------------------------------------------------------
// sin() in f32 arithmetic only, for the music screen's per-frame waves.
//
// WHY: Zig's @sin(f32) is compiler-rt's sinf, a musl port that reduces and
// evaluates in f64. ZIGGY's FPU is f32-only, so every @sin was soft f64:
// a few thousand cycles each, thousands of them a frame (the 1 fps on the
// board). This is the same algorithm (Cody-Waite reduction to +-pi/4, musl's
// minimax kernels) kept in f32, so it runs on the FPU in a few dozen cycles.
//
// Intentional exception to the no-float rule (Matt, 2026-10-17): the music
// test cart may use ZIGGY's f32 FPU. It stays within ~2 ulp of sinf, so the
// waves truncate to the same pixel offsets (apps/music_debug_check.mjs and
// the board sim compare frames).
// --------------------------------------------------------------------------
const std = @import("std");

// pi/2 split in three: P1 has 16 significant bits, so k * P1 is exact for |k| < 2^8 and
// within an ulp well beyond; P1 + P2 + P3 = pi/2 to ~1e-15.
const P1: f32 = 1.5703125;
const P2: f32 = 4.837512969970703125e-4;
const P3: f32 = 7.54978995489188216e-8;
const TWO_OVER_PI: f32 = 0.636619772367581343;

// musl __sindf / __cosdf coefficients (|r| <= pi/4)
const S1: f32 = -0.166666666416265235595;
const S2: f32 = 0.0083333293858894631756;
const S3: f32 = -0.000198393348360966317347;
const S4: f32 = 0.0000027183114939898219064;
const C0: f32 = -0.499999997251031003120;
const C1: f32 = 0.0416666233237390631894;
const C2: f32 = -0.00138867637746099294692;
const C3: f32 = 0.0000243904487962774090654;

inline fn kSin(r: f32) f32 {
    const z = r * r;
    return r + r * z * (S1 + z * (S2 + z * (S3 + z * S4)));
}

inline fn kCos(r: f32) f32 {
    const z = r * r;
    return 1.0 + z * (C0 + z * (C1 + z * (C2 + z * C3)));
}

pub fn sin(x: f32) f32 {
    // nearest quadrant, rounded by truncation (fcvt) rather than a roundf call
    const q = x * TWO_OVER_PI;
    const k: i32 = @intFromFloat(if (q >= 0) q + 0.5 else q - 0.5);
    const kf: f32 = @floatFromInt(k);
    const r = ((x - kf * P1) - kf * P2) - kf * P3;
    return switch (k & 3) {
        0 => kSin(r),
        1 => kCos(r),
        2 => -kSin(r),
        else => -kCos(r),
    };
}

test "sin tracks std.math.sin over the screen's argument range" {
    var worst: f32 = 0;
    var i: i32 = -20000;
    while (i <= 200000) : (i += 7) {
        const x = @as(f32, @floatFromInt(i)) * 0.00137;
        worst = @max(worst, @abs(sin(x) - @sin(x)));
    }
    try std.testing.expect(worst < 4e-7);
}

test "sin is exact at the quadrant points" {
    try std.testing.expectEqual(@as(f32, 0), sin(0));
    try std.testing.expectApproxEqAbs(@as(f32, 1), sin(std.math.pi / 2.0), 1e-7);
    try std.testing.expectApproxEqAbs(@as(f32, -1), sin(-std.math.pi / 2.0), 1e-7);
}
