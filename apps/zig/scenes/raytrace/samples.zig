// The refinement's sample pattern, built at compile time in f64 (no float at run time:
// the tables are constants in each engine's own number type).
//
// Sample 0 is the first picture's: the pixel's own coordinates under the sun.
// Samples 1..N-1 each pair a sub-pixel offset from the R2 low-discrepancy
// sequence (Roberts, 2018: x_i = frac(0.5 + i / g), y_i = frac(0.5 + i / g^2),
// g the plastic number) with a light direction on a Vogel spiral over a small
// disc around the sun (radius LIGHT_R), so every pass is one more anti-aliasing
// sample AND one more soft-shadow sample at no extra ray.
//
// All pixels take the same N samples, but in an order rotated by the pixel's
// Bayer rank, so a part-refined picture shows the light disc as dither rather
// than as N stacked hard shadows; the converged sums do not depend on it.
const trace = @import("trace.zig");

pub const N = 16;
const LIGHT_R = 0.10; // the light disc's radius, in units of the unit sun vector

/// Sample i's sub-pixel offset (x, y), in pixels, -0.5..0.5.
pub const JIT: [N][2]f64 = blk: {
    const g = 1.32471795724474602596;
    var o: [N][2]f64 = undefined;
    for (0..N) |i| {
        const f: f64 = @floatFromInt(i);
        const vx = 0.5 + f / g;
        const vy = 0.5 + f / (g * g);
        o[i] = .{ vx - @floor(vx) - 0.5, vy - @floor(vy) - 0.5 };
    }
    break :blk o;
};

/// Sample i's unit vector toward the light.
pub const LIGHT: [N][3]f64 = blk: {
    @setEvalBranchQuota(10_000);
    const l = unit(trace.SUN_DIR);
    const e1 = unit(cross(l, .{ 0, 1, 0 }));
    const e2 = cross(l, e1);
    var o: [N][3]f64 = undefined;
    for (0..N) |i| {
        const f: f64 = @floatFromInt(i);
        const r = LIGHT_R * @sqrt(f / (N - 1));
        const th = f * 2.399963229728653; // the golden angle
        var d: [3]f64 = undefined;
        for (0..3) |c| d[c] = l[c] + r * (@cos(th) * e1[c] + @sin(th) * e2[c]);
        o[i] = unit(d);
    }
    break :blk o;
};

/// Which sample pass `done` (1..N-1) gives a pixel of Bayer rank 0..15.
pub fn pick(done: u32, rank: u32) u32 {
    return 1 + (done - 1 + rank) % (N - 1);
}

/// The tables in number back-end M (fixed.zig, float.zig) and its vector type V.
pub fn Samples(comptime M: type, comptime V: type) type {
    return struct {
        pub const JX: [N]M.T = axis(0);
        pub const JY: [N]M.T = axis(1);
        pub const LIGHTS: [N]V = blk: {
            var o: [N]V = undefined;
            for (0..N) |i| o[i] = V.of(M.k(LIGHT[i][0]), M.k(LIGHT[i][1]), M.k(LIGHT[i][2]));
            break :blk o;
        };

        fn axis(comptime a: usize) [N]M.T {
            var o: [N]M.T = undefined;
            for (0..N) |i| o[i] = M.k(JIT[i][a]);
            return o;
        }
    };
}

fn unit(v: [3]f64) [3]f64 {
    const n = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return .{ v[0] / n, v[1] / n, v[2] / n };
}

fn cross(a: [3]f64, b: [3]f64) [3]f64 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
