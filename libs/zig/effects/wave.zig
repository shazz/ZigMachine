// --------------------------------------------------------------------------
// Wave: CODEF's FX.siny, a strip drawn column by column at a sine-driven y.
//
// CODEF's FX (fxparam) sums one or more `amp * sin(phase + inc * column)` terms
// per column and draws that source column at the resulting y. Ports reproduce
// it byte for byte only if they keep the original's float habits, which is why
// three ports wrote the loop three ways. Those habits are the options here:
//   - `.accumulate` adds `inc` to the phase once per column (CODEF's own loop:
//     supplex_fs2, union's scroller); `.multiply` computes `phase + inc * i`
//     (noextra). Accumulated floats drift, so the two are not interchangeable.
//   - rounding (`trunc`, `round`, `floor`) of the summed value, base included.
//   - the float type (f32 vs f64).
// The drawing is `blit.blit` of one column group at a time, so clipping, key
// and ink behave exactly like every other blit.
//
// Row displacement (FX.sinx) is left in the scenes: every port shifts rows
// through a different renderer (fixed-point zoom, RLE spans, mirrored copies).
//
// No ZigOS import: it tests natively (wave_test.zig).
// --------------------------------------------------------------------------
const blit = @import("blit.zig");

pub const Step = enum { accumulate, multiply };
pub const Rounding = enum { trunc, round, floor };

/// `base + amp[0]*sin(p0) + amp[1]*sin(p1) + ...`, summed left to right.
pub fn SineSum(comptime F: type, comptime n: usize) type {
    if (n == 0) @compileError("wave.SineSum: at least one term");
    return struct {
        const Self = @This();

        base: F = 0,
        amp: [n]F,
        phase: [n]F,
        inc: [n]F,
        step: Step = .accumulate,
        rounding: Rounding = .trunc,

        /// A left-to-right pass over the columns, starting at column `origin`
        /// (only `.multiply` uses it: the phase of column i is phase + inc * (origin + i)).
        pub fn sweep(self: *const Self, origin: i32) Sweep {
            return .{ .sum = self, .p = self.phase, .i = origin };
        }

        pub const Sweep = struct {
            sum: *const Self,
            p: [n]F,
            i: i32,

            /// This column's value, rounded; then move to the next column.
            pub fn next(it: *Sweep) i32 {
                const s = it.sum;
                var v: F = s.base;
                for (0..n) |k| {
                    const ph = switch (s.step) {
                        .accumulate => it.p[k],
                        .multiply => s.phase[k] + s.inc[k] * @as(F, @floatFromInt(it.i)),
                    };
                    v += s.amp[k] * @sin(ph);
                }
                if (s.step == .accumulate) {
                    for (&it.p, s.inc) |*p, d| p.* += d;
                }
                it.i += 1;
                return @intFromFloat(switch (s.rounding) {
                    .trunc => v,
                    .round => @round(v),
                    .floor => @floor(v),
                });
            }
        };
    };
}

/// FX.siny: draw `part` of `src` (all of it when null) at (dx, dy) in groups of
/// `col_w` columns, each group shifted down by the next value of `sweep`
/// (anything with `next() i32`). Groups are clipped like any blit, and source
/// pixels equal to `key` are skipped. Every group consumes one value, drawn or not.
pub fn siny(dst: blit.Dst, src: blit.Image, part: ?blit.Rect, dx: i32, dy: i32, col_w: usize, sweep: anytype, key: ?u8, ink: blit.Ink) void {
    if (col_w == 0) return;
    const p = part orelse blit.Rect{ .x = 0, .y = 0, .w = src.w, .h = src.h };
    if (p.x >= src.w) return;
    const w = @min(p.w, src.w - p.x);
    var x: usize = 0;
    while (x < w) : (x += col_w) {
        const off = sweep.next();
        const group = blit.Rect{ .x = p.x + x, .y = p.y, .w = @min(col_w, w - x), .h = p.h };
        blit.blit(dst, src, group, dx + @as(i32, @intCast(x)), dy + off, key, ink);
    }
}
