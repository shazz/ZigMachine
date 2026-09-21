const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const TILE = @import("modes.zig").TILE;
const W = @import("modes.zig").W;

// --------------------------------------------------------------------------
// Mode 9: a 2D PARAMETRIC PATH, not a height field.
//
// Every other mode is y = f(x), one y per column, which is why none of them can
// loop: a loop is multivalued in y. Here the track is (x(s), y(s)) for arc
// length s, and strip column c is drawn ALONG THE NORMAL at P(s = c): pixel r
// goes at P + N * (r - 16). A strip column is one pixel wide, so "rotating" it
// is walking a line — true rotation of the text through vertical and upside
// down, with no rotated blit, which this machine does not have.
//
// PATH is the design, in ST screen pixels, and it is meant to be edited: a
// climb from off-screen left, a genuine LOOP (points 5..9, which cross), a
// crest, then a near-vertical DROP, then out to the right. Net motion is right
// to left because the text runs from high s to low s; locally the track goes
// backwards, upwards and fully inverts, which Matt asked for.
//
// It is resampled to ONE POINT PER ARC PIXEL, so the letters keep even spacing
// however tight the curve gets — spacing them in the spline's raw parameter
// would bunch them in the loop and stretch them on the straights.
const PATH = [_][2]f64{
    .{ -40, 132 }, .{ 10, 130 }, .{ 50, 122 }, .{ 84, 104 }, .{ 112, 84 }, // the climb
    .{ 140, 72 },  .{ 176, 40 }, .{ 140, 6 },  .{ 104, 40 }, .{ 146, 72 }, // the loop
    .{ 182, 80 },  .{ 212, 64 }, .{ 238, 40 }, // out of the loop, up to the crest
    .{ 252, 62 },  .{ 262, 96 }, .{ 272, 126 }, // the drop, near vertical
    .{ 300, 132 }, .{ 340, 128 }, .{ 380, 132 }, // and away to the right
};
const MAX_PTS = 896;
var path: [MAX_PTS][2]f32 = undefined;
var path_len: usize = 0;

/// Walk the Catmull-Rom finely, then emit a point every arc pixel.
pub fn buildPath() void {
    const STEP = 400;
    var prev = sample(0, 0);
    var acc: f64 = 0;
    path[0] = .{ @floatCast(prev[0]), @floatCast(prev[1]) };
    path_len = 1;
    for (0..PATH.len - 1) |i| {
        for (0..STEP) |j| {
            const p = sample(i, @as(f64, @floatFromInt(j)) / STEP);
            acc += @sqrt((p[0] - prev[0]) * (p[0] - prev[0]) + (p[1] - prev[1]) * (p[1] - prev[1]));
            prev = p;
            while (acc >= 1.0 and path_len < MAX_PTS) {
                path[path_len] = .{ @floatCast(p[0]), @floatCast(p[1]) };
                path_len += 1;
                acc -= 1.0;
            }
        }
    }
}

fn sample(i: usize, f: f64) [2]f64 {
    var out: [2]f64 = undefined;
    for (0..2) |k| {
        const p0 = PATH[if (i == 0) 0 else i - 1][k];
        const p1 = PATH[i][k];
        const p2 = PATH[@min(i + 1, PATH.len - 1)][k];
        const p3 = PATH[@min(i + 2, PATH.len - 1)][k];
        out[k] = 0.5 * ((2 * p1) + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f +
            (3 * p1 - p0 - 3 * p2 + p3) * f * f * f);
    }
    return out;
}

/// Half-pixel steps along the path AND across the column, so the outside of a
/// tight bend does not open gaps. Where the track crosses itself the later
/// column simply draws over the earlier one: no depth model, by choice.
pub fn draw(dst: blit.Dst, strip: *const [TILE][W]u8, drift: f64) void {
    if (path_len < 4) return;
    const n: f64 = @floatFromInt(path_len);
    for (0..2 * W) |sub| {
        const col = sub / 2;
        var s = @mod(@as(f64, @floatFromInt(sub)) * 0.5 + drift, n);
        if (s < 1) s += n - 2;
        const i: usize = @intFromFloat(s);
        const p = path[i];
        const a = path[(i + path_len - 1) % path_len];
        const b = path[(i + 1) % path_len];
        const dx = b[0] - a[0];
        const dy = b[1] - a[1];
        const d = @sqrt(dx * dx + dy * dy);
        if (d == 0) continue;
        const nx = -dy / d; // the normal: the tangent turned 90 degrees
        const ny = dx / d;
        for (0..2 * TILE) |k| {
            const t = @as(f32, @floatFromInt(k)) * 0.5 - TILE / 2;
            const ink = strip[k / 2][col];
            if (ink == 0) continue;
            plot(dst, p[0] + nx * t, p[1] + ny * t, ink);
        }
    }
}

fn plot(dst: blit.Dst, x: f32, y: f32, ink: u8) void {
    if (!(x >= 0 and y >= 0)) return; // NaN-safe, and vramAlloc has no guard
    const ix: usize = @intFromFloat(x);
    const iy: usize = @intFromFloat(y);
    if (ix >= dst.w or iy >= dst.h) return;
    dst.buf[iy * dst.stride + ix] = ink;
}

