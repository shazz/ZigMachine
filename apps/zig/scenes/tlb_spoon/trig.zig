// --------------------------------------------------------------------------
// THE LOST BOYS / TWIDDLE DEMO — trig for a CPU with no f64 FPU.
// The remake's angles only ever advance by constants, so a Q30 unit vector
// turned by a constant (four multiplies) replaces every sin/cos of the
// frame. Float is used at comptime and for one-off init values only.
// --------------------------------------------------------------------------

pub fn q30(v: f64) i32 {
    return @intFromFloat(@round(v * 1073741824.0));
}

/// cos/sin (Q30) of a constant angle step, built at comptime.
pub const Step = struct {
    c: i32,
    s: i32,

    pub fn of(angle: f64) Step {
        return .{ .c = q30(@cos(angle)), .s = q30(@sin(angle)) };
    }
};

pub const Rotor = struct {
    c: i32,
    s: i32,

    /// Init-time only (float): the starting angle.
    pub fn at(angle: f64) Rotor {
        return .{ .c = q30(@cos(angle)), .s = q30(@sin(angle)) };
    }

    pub fn turn(self: *Rotor, st: Step) void {
        const c: i64 = self.c;
        const s: i64 = self.s;
        const half: i64 = 1 << 29;
        self.c = @intCast((c * st.c - s * st.s + half) >> 30);
        self.s = @intCast((s * st.c + c * st.s + half) >> 30);
    }

    pub fn cosF(self: Rotor) f32 {
        return @as(f32, @floatFromInt(self.c)) * (1.0 / 1073741824.0);
    }

    pub fn sinF(self: Rotor) f32 {
        return @as(f32, @floatFromInt(self.s)) * (1.0 / 1073741824.0);
    }
};

/// sin and cos of a small angle (|x| <= 0.5 rad, error < 1e-8), f32 hardware
/// multiplies only: the Taylor series stopped at x^7 / x^8.
pub fn sinCosSmall(x: f32) struct { s: f32, c: f32 } {
    const x2 = x * x;
    const s = x * (1.0 + x2 * (-1.0 / 6.0 + x2 * (1.0 / 120.0 + x2 * (-1.0 / 5040.0 + x2 * (1.0 / 362880.0)))));
    const c = 1.0 + x2 * (-0.5 + x2 * (1.0 / 24.0 + x2 * (-1.0 / 720.0 + x2 * (1.0 / 40320.0))));
    return .{ .s = s, .c = c };
}
