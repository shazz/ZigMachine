// --------------------------------------------------------------------------
// Union scrolltext -- the wave's rounded sine, in integers.
//
// scroller.zig's FX.siny needs round(10 sin p) for 134 column groups a frame.
// The phase is a u32 angle (fixsin.zig: 2^32 = 2 pi) and the sine fixsin's Q30
// table, so the value is exact but where 10 sin p lies within ~2e-5 of a
// half-integer, which the f32 version (libm sine, @round) could round the other
// way: a column group 1 px higher or lower, now and then. 2026-10-25: no float
// runs here per frame on ZIGGY (wave_sin_test.zig holds it against an f64 sine).
// --------------------------------------------------------------------------
const fixsin = @import("fixsin.zig");

pub const AMP: i32 = 10;

/// round(AMP sin p), halves away from zero.
pub fn rounded(p: u32) i32 {
    const v: i64 = @as(i64, AMP) * fixsin.sin(p); // Q30
    const half: i64 = 1 << 29;
    return @intCast(if (v >= 0) (v + half) >> 30 else -((-v + half) >> 30));
}
