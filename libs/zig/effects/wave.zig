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

// Tag 0 is the default, so a SineSum inside a zeroed Demo behaves as declared.
pub const Step = enum(u8) { accumulate = 0, multiply };
pub const Rounding = enum(u8) { trunc = 0, round, floor };

/// `base + amp[0]*sin(p0) + amp[1]*sin(p1) + ...`, summed left to right.
/// A Sweep points at its SineSum: keep the SineSum alive while sweeping.
pub fn SineSum(comptime F: type, comptime n: usize) type {
    if (n == 0) @compileError("wave.SineSum: at least one term");
    if (F != f32 and F != f64) @compileError("wave.SineSum: F must be f32 or f64");
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
                const r = switch (s.rounding) {
                    .trunc => @trunc(v),
                    .round => @round(v),
                    .floor => @floor(v),
                };
                // Exact for every in-range value; NaN/inf/huge saturate instead
                // of being undefined in @intFromFloat (NaN fails both tests).
                if (r >= -0x1p31 and r < 0x1p31) return @intFromFloat(r);
                return if (r > 0) 0x7FFF_FFFF else -0x8000_0000;
            }
        };
    };
}

/// FX.siny authored on a doubled (640-wide) canvas, drawn at half resolution.
///
/// The canvas strip is given twice, halved at each vertical parity: `halves[0]`
/// pairs its rows (2k, 2k+1), `halves[1]` pairs (2k-1, 2k). `sweep` yields the
/// CANVAS y of every canvas column, two per destination column; the first of
/// each pair places the half column. A column landing on an even canvas row
/// uses halves[0] at y/2, an odd one halves[1] at floor(y/2), so each ST row
/// shows exactly the two canvas rows it covers, whatever the sine's parity.
/// Destination column dx + i shows half column i.
pub fn sinyHalved(dst: blit.Dst, halves: *const [2]blit.Image, dx: i32, sweep: anytype, key: ?u8, ink: blit.Ink) void {
    if (@typeInfo(@TypeOf(sweep)) != .pointer) @compileError("wave.sinyHalved: pass the sweep by pointer (&it)");
    const w = @min(halves[0].w, halves[1].w);
    for (0..w) |i| {
        const y = sweep.next();
        _ = sweep.next(); // canvas column 2i+1: under the same ST column
        const half = &halves[@intCast(y & 1)];
        blit.blit(dst, half.*, .{ .x = i, .y = 0, .w = 1, .h = half.h }, dx +| @as(i32, @intCast(i)), @divFloor(y, 2), key, ink);
    }
}

/// FX.siny: draw `part` of `src` (all of it when null) at (dx, dy) in groups of
/// `col_w` columns, each group shifted down by the next value of `sweep`
/// (a pointer to anything with `next() i32`). Groups are clipped like any blit,
/// and source pixels equal to `key` are skipped. Every group of the
/// source-clipped width consumes one value, drawn or not.
pub fn siny(dst: blit.Dst, src: blit.Image, part: ?blit.Rect, dx: i32, dy: i32, col_w: usize, sweep: anytype, key: ?u8, ink: blit.Ink) void {
    if (@typeInfo(@TypeOf(sweep)) != .pointer) @compileError("wave.siny: pass the sweep by pointer (&it)");
    if (col_w == 0) return;
    const p = part orelse blit.Rect{ .x = 0, .y = 0, .w = src.w, .h = src.h };
    if (p.x >= src.w) return;
    const w = @min(p.w, src.w - p.x);
    var x: usize = 0;
    while (x < w) : (x += col_w) {
        const off = sweep.next();
        const group = blit.Rect{ .x = p.x + x, .y = p.y, .w = @min(col_w, w - x), .h = p.h };
        blit.blit(dst, src, group, dx +| @as(i32, @intCast(x)), dy +| off, key, ink);
    }
}
