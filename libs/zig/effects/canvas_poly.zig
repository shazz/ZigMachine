// --------------------------------------------------------------------------
// A canvas path fill, shown at half resolution.
//
// CODEF screens draw on a canvas at the machine's resolution doubled. A
// polygon filled on that canvas (ctx.fill(), nonzero rule) is shown here by
// taking, for each ST pixel (X, Y), the canvas pixel (2X, 2Y): the pixel is
// ink when that canvas pixel's centre (2X + 0.5, 2Y + 0.5) is inside the path.
// That is the same (0,0)-grid sampling the ports use for doubled artwork, and
// it snaps where the browser antialiases.
//
// "Inside" is exact and has no tie cases left to taste: along the sample row,
// every edge (p[i], p[i+1]) with the row in [y_i, y_{i+1}) or [y_{i+1}, y_i)
// crosses at  x_i + (sy - y_i) * (x_{i+1} - x_i) / (y_{i+1} - y_i)  and adds
// +1 (downward) or -1 (upward); a sample at sx takes the sum of the crossings
// at x <= sx, and is ink when that sum is not 0. A harness can test one point
// with the same formula and get the same answer as these runs.
//
// No ZigOS import: canvas_poly_test.zig runs it natively.
// --------------------------------------------------------------------------
const std = @import("std");
const Dst = @import("blit.zig").Dst;

pub const MAX_POINTS = 16;

const Crossing = struct { x: f64, dir: i8 };

/// Fill the closed path `pts` (canvas pixels, doubled) with `ink`.
pub fn fill(dst: Dst, pts: []const [2]f64, ink: u8) void {
    if (pts.len < 3 or pts.len > MAX_POINTS or dst.w == 0) return;
    var lo = pts[0][1];
    var hi = pts[0][1];
    for (pts[1..]) |p| {
        lo = @min(lo, p[1]);
        hi = @max(hi, p[1]);
    }
    if (!(hi >= 0) or lo >= @as(f64, @floatFromInt(dst.h * 2))) return; // also refuses NaN
    const first = firstSample(lo, dst.h);
    const last = firstSample(hi, dst.h); // exclusive: sample 2Y + 0.5 < hi
    var y = first;
    while (y < last) : (y += 1) {
        const sy = @as(f64, @floatFromInt(2 * y)) + 0.5;
        var xs: [MAX_POINTS]Crossing = undefined;
        var n: usize = 0;
        for (pts, 0..) |p0, i| {
            const p1 = pts[(i + 1) % pts.len];
            const down = p0[1] <= sy and sy < p1[1];
            if (!down and !(p1[1] <= sy and sy < p0[1])) continue;
            xs[n] = .{ .x = p0[0] + (sy - p0[1]) * (p1[0] - p0[0]) / (p1[1] - p0[1]), .dir = if (down) 1 else -1 };
            n += 1;
        }
        std.sort.insertion(Crossing, xs[0..n], {}, leftOf);
        const row = dst.buf[y * dst.stride ..][0..dst.w];
        var winding: i32 = 0;
        for (xs[0..n], 0..) |c, i| {
            winding += c.dir;
            if (winding == 0 or i + 1 == n) continue;
            const a = firstSample(c.x, dst.w);
            const b = firstSample(xs[i + 1].x, dst.w);
            if (a < b) @memset(row[a..b], ink);
        }
    }
}

/// The first ST index k (clamped to 0..limit) whose sample 2k + 0.5 is >= c.
/// (c - 0.5) / 2 is exact for any coordinate a canvas can hold.
fn firstSample(c: f64, limit: usize) usize {
    const k = @ceil((c - 0.5) / 2);
    if (!(k > 0)) return 0;
    const lim: f64 = @floatFromInt(limit);
    if (k >= lim) return limit;
    return @intFromFloat(k);
}

fn leftOf(_: void, a: Crossing, b: Crossing) bool {
    return a.x < b.x;
}
