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
};
