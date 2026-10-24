// --------------------------------------------------------------------------
// The music screen's wave maths in fixed point (Matt, 2026-10-24: no float per
// frame). Phases are zg.fixtrig Angles (one turn = 2^32, so an accumulator
// wraps where 2*pi does and never drifts), sines come from its 1024-entry
// table, and an amplitude is Q8 (256 = 1 pixel).
//
// The screen used to run the same waves through an f32 sine on ZIGGY's FPU
// (~230 cycles each, ~2,400 a frame): the radian constants below are the very
// ones it used, converted once at compile time, so the motion is the same; an
// offset can differ by one pixel where sin * amp crosses an integer.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ft = zg.fixtrig;

pub const Angle = ft.Angle;

/// A compile-time radian constant (a phase step, a per-column step) as an Angle.
pub fn rad(comptime r: f64) Angle {
    return comptime ft.angle(r);
}

/// trunc(sin(a) * amp8 / 256): a wave's whole-pixel offset, toward zero as the
/// float version's @intFromFloat was. |amp8| <= 2^15 keeps the product in i32.
/// Inline, with the divide as shifts (ReleaseSmall kept a call and a div_s,
/// ~35 cycles, in each of ~2,300 a frame).
pub inline fn offset(a: Angle, amp8: i32) i32 {
    return truncShift(@call(.always_inline, ft.sin, .{a}) * amp8, 24);
}

/// @divTrunc(x, 1 << n) as shifts: ReleaseSmall emits a div_s (~35 cycles) for it.
pub inline fn truncShift(x: i32, comptime n: u5) i32 {
    return (x + ((x >> 31) & ((1 << n) - 1))) >> n;
}

/// sin(a) >= 0, for the square waves of the YM scope.
pub fn positive(a: Angle) bool {
    return a <= 1 << 31; // the first half-turn, ends included (sin 0 = sin pi = 0)
}

/// An Angle times a small integer (a phase scaled by a whole factor): wraps.
pub fn scale(a: Angle, k: u32) Angle {
    return a *% k;
}
