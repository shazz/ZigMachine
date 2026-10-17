// --------------------------------------------------------------------------
// sin(phase + step * j) without a libm call per j: the angle-addition formula,
//   sin(p + d) = sin p cos d + cos p sin d,
// with sin d / cos d TABLED at compile time in Q30 for d = step * j. A frame
// takes sin p and cos p once (two f64 calls) and each j costs two 64-bit
// multiplies. Q30 keeps a rounded result identical to the f64 one except
// within ~1e-8 of a .5 boundary.
//
// The CODEF ports step these phases by a constant (0.1, 0.6, 0.004) per letter,
// row or column, which is why one table per (n, step) serves a whole screen.
// --------------------------------------------------------------------------
pub fn SinTab(comptime n: usize, comptime step: f64) type {
    return struct {
        const Self = @This();

        const Tables = struct { sin: [n]i32, cos: [n]i32 };
        const T: Tables = blk: {
            @setEvalBranchQuota(n * 4000 + 10_000);
            var t: Tables = undefined;
            for (0..n) |i| {
                const d = step * @as(f64, @floatFromInt(i));
                t.sin[i] = @intFromFloat(@round(@sin(d) * 1073741824.0));
                t.cos[i] = @intFromFloat(@round(@cos(d) * 1073741824.0));
            }
            break :blk t;
        };

        s: i64, // sin(phase), Q30
        c: i64, // cos(phase), Q30

        /// The phase is the one f64 libm pair a frame pays.
        pub fn init(phase: f64) Self {
            return .{
                .s = @intFromFloat(@round(@sin(phase) * 1073741824.0)),
                .c = @intFromFloat(@round(@cos(phase) * 1073741824.0)),
            };
        }

        /// sin(phase + step * j), Q30.
        pub fn at(self: Self, j: usize) i64 {
            return (self.s * T.cos[j] + self.c * T.sin[j]) >> 30;
        }

        /// cos(phase + step * j), Q30.
        pub fn cosAt(self: Self, j: usize) i64 {
            return (self.c * T.cos[j] - self.s * T.sin[j]) >> 30;
        }

        /// round_half_up(base + amp * cos(phase + step * j)).
        pub fn roundCos(self: Self, j: usize, base: i64, amp: i64) i32 {
            return @intCast(((base << 30) + amp * self.cosAt(j) + (1 << 29)) >> 30);
        }

        /// round_half_up(base + amp * sin(phase + step * j)); base, amp in whole pixels.
        pub fn round(self: Self, j: usize, base: i64, amp: i64) i32 {
            return @intCast(((base << 30) + amp * self.at(j) + (1 << 29)) >> 30);
        }
    };
}

/// A column-independent sweep (wave.siny's `next() i32`): every column at one y.
pub const Flat = struct {
    y: i32,
    pub fn next(it: *Flat) i32 {
        return it.y;
    }
};
