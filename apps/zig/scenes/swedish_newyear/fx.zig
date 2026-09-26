// CODEF's FX (lib/codef_fx.js) sinx / siny: line i of the source is shifted by
//   prov_i = sum_j sin(value_j) * amp_j,   value_j += inc_j after every line,
// and after the call every value_j = (its value at the start) + offset_j. The
// shifts are taken here one line at a time, by the same repeated additions.
//
// The draws land at fractional offsets. The remake's intermediate canvases
// smooth them (bilinear); an ST shifts whole pixels, so every sample here is
// NEAREST: destination pixel d shows source floor(d + 0.5 - offset).
pub const Param = struct { value: f64, amp: f64, inc: f64, offset: f64 };

pub fn Fx(comptime n: usize) type {
    return struct {
        const Self = @This();
        p: [n]Param,

        /// The shifts for `lines` lines into `out`, and the per-call offset.
        pub fn run(self: *Self, out: []f64) void {
            var v: [n]f64 = undefined;
            for (self.p, 0..) |q, j| v[j] = q.value;
            for (out) |*o| {
                var prov: f64 = 0;
                for (self.p, 0..) |q, j| prov += @sin(v[j]) * q.amp;
                o.* = prov;
                for (self.p, 0..) |q, j| v[j] += q.inc;
            }
            for (&self.p) |*q| q.value += q.offset;
        }
    };
}
