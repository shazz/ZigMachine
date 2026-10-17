// --------------------------------------------------------------------------
// CUDDLY STARWARS — the integer side of the per-frame maths. ZIGGY has no
// f64 FPU, so the stars, the perspective blend, the raster and the sprite
// wobble all run on Q16 / Q24 / Q30 integers. Float appears only in
// comptime constants and one-off init values.
// --------------------------------------------------------------------------

pub const ONE: u32 = 65536; // Q16 1.0

pub fn q30(v: f64) i32 {
    return @intFromFloat(@round(v * 1073741824.0));
}

/// A unit vector (cos, sin) in Q30 turned by a constant angle per call: the
/// ST coder's way to a sine with no table and no divide. A turn costs four
/// multiplies; the rounding drift is ~1e-9 per step.
pub const Rotor = struct {
    c: i32,
    s: i32,

    /// Init-time only (float): the starting angle.
    pub fn at(angle: f64) Rotor {
        return .{ .c = q30(@cos(angle)), .s = q30(@sin(angle)) };
    }

    /// Turn by the angle whose cos/sin (Q30) are step_c/step_s.
    pub fn turn(self: *Rotor, step_c: i32, step_s: i32) void {
        const c: i64 = self.c;
        const s: i64 = self.s;
        const half: i64 = 1 << 29;
        self.c = @intCast((c * step_c - s * step_s + half) >> 30);
        self.s = @intCast((s * step_c + c * step_s + half) >> 30);
    }
};

// Stars: z runs in milli-units on a lattice of 25, and k = 128 / z is a table
// indexed by z / 25 (Q16), so there is no divide in the frame.
pub const STAR_Z_MILLI: i32 = 130000;
const K_LEN = 5201;
pub const star_k: [K_LEN]u32 = blk: {
    @setEvalBranchQuota(200_000);
    var t: [K_LEN]u32 = undefined;
    t[0] = 0;
    for (1..K_LEN) |m| t[m] = @intCast((335544320 + m / 2) / m); // 128 * 65536 * 40 / m
    break :blk t;
};

/// The 8-bit grey each palette index holds (0 below `base`).
pub fn greyLut(comptime base: u8, comptime levels: usize) [256]u8 {
    var t = [_]u8{0} ** 256;
    for (0..levels) |k| t[base + k] = @intCast((k * 255 + (levels - 1) / 2) / (levels - 1));
    return t;
}

/// round(v * (levels-1) / (255 * ONE)) for a Q16 grey v in 0..255*ONE.
pub inline fn levelOf(v: u32, comptime levels: u32) u32 {
    const den: u32 = 255 * ONE;
    return (v * (levels - 1) + den / 2) / den;
}
