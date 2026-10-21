const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const TILE = @import("modes.zig").TILE;
const W = @import("modes.zig").W;
const map = @import("path_map.zig"); // where each point's samples land

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
const MAX_PTS = map.MAX_PTS;
/// 7,168 B on zg.mem, taken once by buildPath() (modes.init, once per cart load).
var path: *[MAX_PTS][2]f32 = undefined;
/// The unit normal at each point, worked out once: the frame has no sqrt or divide.
var normal: *[MAX_PTS][2]f32 = undefined;
var path_len: usize = 0;

/// Walk the Catmull-Rom finely, then emit a point every arc pixel.
pub fn buildPath() void {
    const STEP = 400;
    path = zg.mem.mustAlloc([2]f32, MAX_PTS)[0..MAX_PTS];
    normal = zg.mem.mustAlloc([2]f32, MAX_PTS)[0..MAX_PTS];
    map.alloc();
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
    for (0..path_len) |i| {
        const a = path[(i + path_len - 1) % path_len];
        const b = path[(i + 1) % path_len];
        const dx = b[0] - a[0];
        const dy = b[1] - a[1];
        const d = @sqrt(dx * dx + dy * dy);
        normal[i] = if (d == 0) .{ 0, 0 } else .{ -dy / d, dx / d }; // the tangent turned 90 degrees
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

/// Fill the sample map for `dst` now (init), not on mode 9's first frame.
pub fn prepare(dst: blit.Dst) void {
    if (path_len >= 4) _ = map.ensure(dst, path[0..path_len], normal[0..path_len]);
}

/// Half-pixel steps along the path AND across the column, so the outside of a
/// tight bend does not open gaps. Where the track crosses itself the later
/// column simply draws over the earlier one: no depth model, by choice.
///
/// Where each of a point's 2*TILE samples lands depends on the point alone, so
/// buildMap() works them out once (path_map.zig) and the frame is integer: a
/// strip byte, a table offset, a store. Two exact cuts of repeated work:
/// - a sub-column on the SAME path point as the one before (same strip column,
///   half the subs at travel 0) would repeat its whole write sequence verbatim,
///   which cannot change the picture: skipped;
/// - the map drops a sample landing where its row's other sample just wrote.
pub fn draw(dst: blit.Dst, strip: *const [TILE][W]u8, drift_q4: i64) void {
    if (path_len < 4) return;
    if (!map.ensure(dst, path[0..path_len], normal[0..path_len])) return drawSlow(dst, strip, drift_q4);
    // Arc position in QUARTER pixels: half-pixel steps plus a drift that is a
    // whole number of quarters. The drift is reduced once a frame; each sub
    // then steps 2 quarters with a wrap, the same as @mod(2*sub + drift, n4).
    const n4: i32 = @intCast(path_len * 4);
    var s4: i32 = @intCast(@mod(drift_q4, n4));
    var prev: usize = std.math.maxInt(usize);
    for (0..2 * W) |sub| {
        defer {
            s4 += 2;
            if (s4 >= n4) s4 -= n4;
        }
        const col = sub / 2;
        const at = if (s4 < 4) s4 + n4 - 8 else s4;
        const i: usize = @intCast(at >> 2);
        const repeat = sub % 2 == 1 and i == prev;
        prev = i;
        if (repeat or map.empty[i]) continue;
        const offs = &map.offs[i];
        for (0..TILE) |r| {
            const ink = strip[r][col];
            if (ink == 0) continue;
            const o0 = offs[2 * r];
            const o1 = offs[2 * r + 1];
            if (o0 != map.NONE) dst.buf[o0] = ink;
            if (o1 != map.NONE) dst.buf[o1] = ink;
        }
    }
}

/// The frame as it was before path_map.zig, per sample in f32: what the map
/// reproduces, and the fallback for a view too big for its u16 offsets.
fn drawSlow(dst: blit.Dst, strip: *const [TILE][W]u8, drift_q4: i64) void {
    const n4: i64 = @as(i64, @intCast(path_len)) * 4;
    for (0..2 * W) |sub| {
        const col = sub / 2;
        var s4 = @mod(@as(i64, @intCast(sub)) * 2 + drift_q4, n4);
        if (s4 < 4) s4 += n4 - 8;
        const i: usize = @intCast(s4 >> 2);
        const p = path[i];
        const nv = normal[i];
        if (nv[0] == 0 and nv[1] == 0) continue;
        for (0..2 * TILE) |k| {
            const ink = strip[k / 2][col];
            if (ink == 0) continue;
            const t = @as(f32, @floatFromInt(k)) * 0.5 - TILE / 2;
            plot(dst, p[0] + nv[0] * t, p[1] + nv[1] * t, ink);
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
