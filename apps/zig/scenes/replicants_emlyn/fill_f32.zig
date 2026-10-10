// --------------------------------------------------------------------------
// The raster table, filled the CODEF port's way, in f32: for every bucket of
// every line, search the bars near to far for the first one covering that
// point (a divide and a floor per bar tried). This is replicants_emlyn_f32's
// fill, kept for the FPU test; the default cart fills the same table with
// integer spans (fill_fixed.zig). rasters.zig says what the table is.
// --------------------------------------------------------------------------
const std = @import("std");
const R = @import("rasters.zig");
const A = @import("assets.zig");
const Particle = @import("balls_f32.zig").Particle;

const PLANE_WF: f32 = R.PLANE_W;
const CX: f32 = R.CX;
const CY: f32 = R.CY;
const CYCLES_PER_ENTRY: f32 = @as(f32, R.CYCLES_PER_ENTRY_X2) / 2.0;

/// Bands that fall inside one bucket, per particle (rasters.zig: MERGING).
var merge: [16]usize = undefined;

/// The colours every scanline of the content window shows this frame.
/// `particles` come far to near.
pub fn build(particles: []const Particle, theta: f32) void {
    const sin = @sin(theta);
    const cos = @cos(theta);
    const band = typicalBand(particles); // one colour band, in canvas pixels
    R.setCount(bucketCount(@abs(sin), @abs(cos), band));
    const width = 2.0 * PLANE_WF / @as(f32, @floatFromInt(R.count)); // a bucket, in canvas pixels
    setMerge(particles, @abs(width * sin));
    const du = width * sin;
    const t = R.table; // one load of the arena pointer, not one a row
    for (0..A.CONTENT_H) |y| {
        // the ST row's canvas pixel centre, as the sprite port sampled it
        const yc = 2.0 * @as(f32, @floatFromInt(y)) + 0.5;
        // plane column 0 is CONTENT_X to the left of canvas 0
        var u = (-2.0 * @as(f32, A.CONTENT_X) + 0.5 - CX) * sin + (yc - CY) * cos + CY;
        for (t[A.CONTENT_Y + y][0..R.count]) |*b| {
            b.* = inkAt(particles, u);
            u += du;
        }
    }
}

/// How fine the ramp may be: no finer than one band needs (there is nothing to
/// show between two), and no finer than a line can rewrite.
fn bucketCount(sin: f32, cos: f32, band: f32) usize {
    const need = 2.0 * PLANE_WF * sin / band;
    const churn = @min(1.0, 2.0 * cos / band); // entries changing per line
    const budget = if (churn <= 0) @as(f32, R.MAX_BUCKETS) else R.LINE_CYCLES / (CYCLES_PER_ENTRY * churn);
    return @intFromFloat(std.math.clamp(@round(@min(need, budget)), 1, @as(f32, R.MAX_BUCKETS)));
}

/// The mean colour band, in canvas pixels: a bar's 32 bands over 64*sy rows.
fn typicalBand(particles: []const Particle) f32 {
    if (particles.len == 0) return 2.0;
    var sum: f32 = 0;
    for (particles) |p| sum += 2.0 * p.sy;
    return sum / @as(f32, @floatFromInt(particles.len));
}

fn setMerge(particles: []const Particle, step: f32) void {
    for (particles, 0..) |p, i| {
        const k = @round(step / (2.0 * p.sy));
        merge[i] = if (k < 1) 1 else @intFromFloat(k);
    }
}

/// The nearest bar covering `u` wins, so scan near to far and stop at the first:
/// the far-to-near painting order with no painting.
fn inkAt(particles: []const Particle, u: f32) u8 {
    var i = particles.len;
    while (i > 0) {
        i -= 1;
        const p = particles[i];
        // bar.png's row under u. The CanvasRenderer never undoes its y flip for
        // a ParticleCanvasMaterial, so the table reads backwards — measured
        // against the browser, and kept.
        const r = @floor((p.y - u) / p.sy) + R.BAR_ROWS / 2;
        if (r < 0 or r >= R.BAR_ROWS) continue;
        const m = @as(usize, @intFromFloat(r)) / 2;
        return @intCast(m / merge[i] * merge[i]);
    }
    return R.BLACK;
}
