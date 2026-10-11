// --------------------------------------------------------------------------
// ZIG mode's scrolltext curve: CODEF 484's middle scroller (cascade-
// archeology.js:76-79), amp HALVED and inc DOUBLED for ST, offset per frame
// unchanged, scaled by the mode's bend (scroller.zig says why this curve).
//
//   y(column x) = round( sum_k amp_k * bend * sin(phase_k + inc_k * x) )
//
// Each glyph is drawn by wave.siny, which takes any sweep with next(). Two of
// them, one per cart:
//   CurveFixed  the default: integer angles, the fixtrig table, Q8 amplitudes
//               (amp * bend / 20 is a whole number of 1/256 px, so exact), sums
//               in Q24 — two table lookups and two multiplies a column
//   CurveF32    the f32 cart: wave.SineSum(.multiply, .round) as the port had
//               it, written out so the sweep can outlive the call that made it
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trig = zg.fixtrig;
const ModeFixed = @import("mode.zig");
const ModeF32 = @import("mode_f32.zig").Mode;

const TERMS = 2;
const AMP = [TERMS]i32{ 10, 20 }; // the short ripple, then the long swell
const INC = [TERMS]f64{ 0.06, 0.02 }; // radians a column: the wavelengths
const OFFSET = [TERMS]f64{ -0.05, -0.04 }; // radians a frame: the travel
/// The furthest a column moves, at full bend: |y| <= the amplitudes' sum.
pub const REACH = AMP[0] + AMP[1];

pub const CurveFixed = struct {
    phase: [TERMS]trig.Angle, // 484's `value`, advanced by OFFSET a frame

    const inc = [TERMS]trig.Angle{ trig.angle(INC[0]), trig.angle(INC[1]) };
    const offset = [TERMS]trig.Angle{ trig.angle(OFFSET[0]), trig.angle(OFFSET[1]) };

    pub fn init(self: *CurveFixed) void {
        self.phase = .{ 0, 0 };
    }

    pub fn step(self: *CurveFixed) void {
        for (&self.phase, offset) |*v, d| v.* +%= d;
    }

    /// The curve from screen column `origin` on, at the mode's bend.
    pub fn sweep(self: *const CurveFixed, mode: *const ModeFixed.Mode, origin: i32) Sweep {
        var s: Sweep = undefined;
        const col: u32 = @bitCast(origin);
        for (0..TERMS) |k| {
            s.amp[k] = @divExact(AMP[k] * 256 * @as(i32, mode.bend), ModeFixed.BEND_FRAMES);
            s.ph[k] = self.phase[k] +% inc[k] *% col;
        }
        return s;
    }

    pub const Sweep = struct {
        amp: [TERMS]i32, // Q8 pixels
        ph: [TERMS]trig.Angle,

        pub fn next(it: *Sweep) i32 {
            var v: i32 = 0; // Q24: |v| < 30 px
            for (0..TERMS) |k| {
                v += it.amp[k] * trig.sin(it.ph[k]);
                it.ph[k] +%= inc[k];
            }
            return (v + (1 << 23)) >> 24;
        }
    };
};

pub const CurveF32 = struct {
    phase: [TERMS]f32,

    pub fn init(self: *CurveF32) void {
        self.phase = .{ 0, 0 };
    }

    pub fn step(self: *CurveF32) void {
        for (&self.phase, OFFSET) |*v, d| v.* += @floatCast(d);
    }

    pub fn sweep(self: *const CurveF32, mode: *const ModeF32, origin: i32) Sweep {
        var s = Sweep{ .amp = undefined, .phase = self.phase, .i = origin };
        for (&s.amp, AMP) |*a, amp| a.* = @as(f32, @floatFromInt(amp)) * mode.bend;
        return s;
    }

    pub const Sweep = struct {
        amp: [TERMS]f32,
        phase: [TERMS]f32,
        i: i32,

        pub fn next(it: *Sweep) i32 {
            var v: f32 = 0;
            const x: f32 = @floatFromInt(it.i);
            for (0..TERMS) |k| v += it.amp[k] * @sin(it.phase[k] + @as(f32, @floatCast(INC[k])) * x);
            it.i += 1;
            const r = @round(v);
            // NaN/inf saturate instead of being undefined in @intFromFloat
            if (r >= -0x1p31 and r < 0x1p31) return @intFromFloat(r);
            return if (r > 0) 0x7FFF_FFFF else -0x8000_0000;
        }
    };
};
