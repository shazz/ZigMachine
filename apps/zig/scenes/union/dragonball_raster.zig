// --------------------------------------------------------------------------
// Union main -- one dragonball (5 spinning stars over the translucent disc)
// rasterised into its 64x64 index buffer. Pure f32 maths, no ZigOS, so the
// native test (dragonball_raster_test.zig) can hold it against the first
// version, pixel for pixel.
//
// Same pixels as the first version (back triangles, then the disc turning
// what lay under it into DISC_ON_BACK and 0 into DISC, then front triangles),
// in fewer steps: the disc is laid FIRST (its rows are known at compile time,
// gm.DISC_SPAN), and a back triangle's row run is cut at the disc's edges --
// DISC_ON_BACK inside, BACK outside -- so no pass reads the buffer back. The
// triangle edges are sorted and differenced once a triangle instead of once a
// row (the same operands, the same operation order: the same f32 results), and
// a star's facing is worked out once, not once a pass.
// --------------------------------------------------------------------------
const std = @import("std");
const gm = @import("dragonball_math.zig");

const TWO_PI: f32 = std.math.pi * 2.0;
const BS = gm.BALL_SIZE; // 64

pub const PAL_DISC: u8 = 64; // the translucent disc, pre-blended over the bottom band
pub const PAL_FRONT: u8 = 128; // star front (kolor 0xD94345), opaque
pub const PAL_BACK: u8 = 129; // star back, opaque, dimmer (drawn under the disc)
pub const PAL_DISC_ON_BACK: u8 = 192; // the disc over PAL_BACK, opaque

pub const Buf = [BS * BS]u8;
/// Per row, columns [lo, hi) hold every non-zero pixel of the row (lo >= hi: none).
pub const Spans = [BS][2]u8;
const Tri = [3]gm.Vec2;

/// The ball at star rotation (rotx, roty) into `buf`, and where each row is not 0 into `spans`.
pub fn renderBall(buf: *Buf, spans: *Spans, rotx: f32, roty: f32) void {
    @memset(buf, 0);
    for (gm.DISC_SPAN, 0..) |span, y| @memset(buf[y * BS + span[0] ..][0 .. span[1] - span[0]], PAL_DISC);
    spans.* = gm.DISC_SPAN;

    var tris: [gm.NSTARS * gm.NTRIS]Tri = undefined;
    var front: [gm.NSTARS * gm.NTRIS]bool = undefined;
    for (0..gm.NSTARS) |s| {
        const phase: f32 = @as(f32, @floatFromInt(s)) * (TWO_PI / @as(f32, gm.NSTARS));
        const ay = roty + phase;
        var proj: [gm.NVERTS]gm.Vec2 = undefined;
        for (0..gm.NVERTS) |v| proj[v] = gm.project(gm.rotate(gm.VERTS[v], rotx, ay));
        for (gm.TRIS, 0..) |t, i| {
            const k = s * gm.NTRIS + i;
            tris[k] = .{ proj[t[0]], proj[t[1]], proj[t[2]] };
            front[k] = gm.signedArea(proj[t[0]], proj[t[1]], proj[t[2]]) <= 0;
        }
    }
    for (tris, front) |t, f| if (!f) fill(buf, spans, t, .back); // under the disc
    for (tris, front) |t, f| if (f) fill(buf, spans, t, .front); // on top, opaque
}

const Edge = struct { ay: f32, ax: f32, by: f32, dx: f32, dy: f32, flat: bool };

// gm.fillTriangle's edge e, swapped to run downwards, with its differences taken.
fn edge(a: gm.Vec2, b: gm.Vec2) Edge {
    const lo = if (a.y > b.y) b else a;
    const hi = if (a.y > b.y) a else b;
    return .{ .ay = lo.y, .ax = lo.x, .by = hi.y, .dx = hi.x - lo.x, .dy = hi.y - lo.y, .flat = a.y == b.y };
}

const Pass = enum { back, front };

// gm.fillTriangle, clipped the same way; a back row is split at the disc's run.
fn fill(buf: *Buf, spans: *Spans, t: Tri, pass: Pass) void {
    const edges = [3]Edge{ edge(t[0], t[1]), edge(t[1], t[2]), edge(t[2], t[0]) };
    var ymin = @min(t[0].y, @min(t[1].y, t[2].y));
    var ymax = @max(t[0].y, @max(t[1].y, t[2].y));
    if (ymin < 0) ymin = 0;
    if (ymax > @as(f32, BS - 1)) ymax = @as(f32, BS - 1);
    var y: i32 = @intFromFloat(@ceil(ymin));
    const ylast: i32 = @intFromFloat(@floor(ymax));
    while (y <= ylast) : (y += 1) {
        const fy: f32 = @floatFromInt(y);
        var xl: f32 = 1e9;
        var xr: f32 = -1e9;
        for (edges) |e| {
            if (e.flat or fy < e.ay or fy >= e.by) continue;
            const x = e.ax + e.dx * (fy - e.ay) / e.dy;
            if (x < xl) xl = x;
            if (x > xr) xr = x;
        }
        if (xr < xl) continue;
        var l: i32 = @intFromFloat(@ceil(xl));
        var r: i32 = @intFromFloat(@floor(xr));
        if (l < 0) l = 0;
        if (r > @as(i32, BS - 1)) r = BS - 1;
        if (r < l) continue;
        const yu: usize = @intCast(y);
        const lu: usize = @intCast(l);
        const ru: usize = @intCast(r + 1);
        widen(&spans[yu], lu, ru);
        if (pass == .front) {
            @memset(buf[yu * BS + lu .. yu * BS + ru], PAL_FRONT);
        } else {
            backRow(buf[yu * BS ..][0..BS], lu, ru, gm.DISC_SPAN[yu]);
        }
    }
}

fn widen(span: *[2]u8, lo: usize, hi: usize) void {
    if (span[1] <= span[0]) {
        span.* = .{ @intCast(lo), @intCast(hi) };
    } else {
        span.* = .{ @min(span[0], @as(u8, @intCast(lo))), @max(span[1], @as(u8, @intCast(hi))) };
    }
}

// Columns lo..hi-1 of a back triangle's row: DISC_ON_BACK on the disc's run, BACK off it.
fn backRow(row: *[BS]u8, lo: usize, hi: usize, disc: [2]u8) void {
    const d0 = @min(@max(@as(usize, disc[0]), lo), hi);
    const d1 = @max(@min(@as(usize, disc[1]), hi), d0);
    @memset(row[lo..d0], PAL_BACK);
    @memset(row[d0..d1], PAL_DISC_ON_BACK);
    @memset(row[d1..hi], PAL_BACK);
}
