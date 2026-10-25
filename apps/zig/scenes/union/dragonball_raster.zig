// --------------------------------------------------------------------------
// Union main -- one dragonball (5 spinning stars over the translucent disc)
// rasterised into its 64x64 index buffer. No ZigOS, so the native test
// (dragonball_raster_test.zig) can hold it against the first, f32 version.
//
// The pixels of the first version (back triangles, then the disc turning what
// lay under it into DISC_ON_BACK and 0 into DISC, then front triangles), in
// fewer steps: the disc is laid FIRST (its rows are known at compile time,
// gm.DISC_SPAN), and a back triangle's row run is cut at the disc's edges --
// DISC_ON_BACK inside, BACK outside -- so no pass reads the buffer back.
// 2026-10-25: fixed point, no float a frame on ZIGGY: u32 angles and Q30 sines
// (fixsin.zig), vertices in Q16, an edge's slope worked out once a triangle
// (one divide), then stepped a row at a time with an add. An edge pixel lands differently now
// and then (dragonball_raster_test.zig bounds how many).
// --------------------------------------------------------------------------
const std = @import("std");
const gm = @import("dragonball_math.zig");
const fixsin = @import("fixsin.zig");

const BS = gm.BALL_SIZE; // 64

pub const PAL_DISC: u8 = 64; // the translucent disc, pre-blended over the bottom band
pub const PAL_FRONT: u8 = 128; // star front (kolor 0xD94345), opaque
pub const PAL_BACK: u8 = 129; // star back, opaque, dimmer (drawn under the disc)
pub const PAL_DISC_ON_BACK: u8 = 192; // the disc over PAL_BACK, opaque

pub const Buf = [BS * BS]u8;
/// Per row, columns [lo, hi) hold every non-zero pixel of the row (lo >= hi: none).
pub const Spans = [BS][2]u8;
// A projected vertex in Q16 ball pixels.
const P = struct { x: i32, y: i32 };
const Tri = [3]P;
const Q: i32 = 1 << 16;

// codef_dragonball.js's vertices (gm.VERTS) in Q16.
const VQ: [gm.NVERTS][3]i64 = blk: {
    var t: [gm.NVERTS][3]i64 = undefined;
    for (gm.VERTS, 0..) |v, i| t[i] = .{ q(v.x), q(v.y), q(v.z) };
    break :blk t;
};
fn q(comptime x: f32) i64 {
    return @intFromFloat(@round(@as(f64, x) * 65536.0));
}

// gm.rotate then gm.project (Rx * Ry, then the camera), in Q16 with Q30 sines.
fn project(v: [3]i64, sx: i64, cx: i64, sy: i64, cy: i64) P {
    const x1 = (v[0] * cy + v[2] * sy) >> 30;
    const z1 = (-v[0] * sy + v[2] * cy) >> 30;
    const y2 = (v[1] * cx - z1 * sx) >> 30;
    const z2 = (v[1] * sx + z1 * cx) >> 30;
    var denom = q(gm.CAM_Z) - z2;
    if (denom < Q) denom = Q; // defensive: verts never reach the camera plane
    // FOCAL / denom in Q32, by i32 long division of their Q11 values (denom < 4096 px here)
    const k: i64 = quot(@intCast(q(gm.FOCAL) >> 5), @intCast(denom >> 5), 4);
    return .{
        .x = @intCast(q(gm.CENTER) + ((x1 * k) >> 32)),
        .y = @intCast(q(gm.CENTER) - ((y2 * k) >> 32)),
    };
}

/// The ball at star rotation rotx and, per star, roty + its phase (`ay`) -- u32 angles,
/// fixsin.zig -- into `buf`, and where each row is not 0 into `spans`.
pub fn renderBall(buf: *Buf, spans: *Spans, rotx: u32, ay_of: *const [gm.NSTARS]u32) void {
    @memset(buf, 0);
    for (gm.DISC_SPAN, 0..) |span, y| @memset(buf[y * BS + span[0] ..][0 .. span[1] - span[0]], PAL_DISC);
    spans.* = gm.DISC_SPAN;

    var tris: [gm.NSTARS * gm.NTRIS]Tri = undefined;
    var front: [gm.NSTARS * gm.NTRIS]bool = undefined;
    const sx: i64 = fixsin.sin(rotx);
    const cx: i64 = fixsin.cos(rotx);
    for (0..gm.NSTARS) |s| {
        const ay = ay_of[s];
        const sy: i64 = fixsin.sin(ay);
        const cy: i64 = fixsin.cos(ay);
        var proj: [gm.NVERTS]P = undefined;
        for (0..gm.NVERTS) |v| proj[v] = project(VQ[v], sx, cx, sy, cy);
        for (gm.TRIS, 0..) |t, i| {
            const k = s * gm.NTRIS + i;
            const a = proj[t[0]];
            const b = proj[t[1]];
            const c = proj[t[2]];
            tris[k] = .{ a, b, c };
            // gm.signedArea <= 0
            front[k] = @as(i64, b.x - a.x) * (c.y - a.y) - @as(i64, b.y - a.y) * (c.x - a.x) <= 0;
        }
    }
    for (tris, front) |t, f| if (!f) fill(buf, spans, t, .back); // under the disc
    for (tris, front) |t, f| if (f) fill(buf, spans, t, .front); // on top, opaque
}

// An edge run downwards: x at row y is ax + slope * (y - ay), the slope worked out once
// (Q16, slopeQ16) and added a row at a time.
const Edge = struct { ay: i32, by: i32, slope: i32, x: i32, flat: bool };

// The edge, its x already at row `y0` (Q16), stepped a row at a time by fill().
fn edge(a: P, b: P, y0: i32) Edge {
    const lo = if (a.y > b.y) b else a;
    const hi = if (a.y > b.y) a else b;
    const dx = hi.x - lo.x;
    const dy = hi.y - lo.y;
    if (dy < 256 or @abs(dx) >= (1 << 22)) {
        // Under 1/256 px tall (or wild): it holds one row centre at most, so its x there is
        // worked out once, exactly, and kept (slope 0).
        const fr: i32 = (lo.y + 0xFFFF) & ~@as(i32, 0xFFFF); // the first row centre on it
        const x: i64 = if (dy == 0) lo.x else lo.x + @divFloor(@as(i64, dx) * (fr - lo.y), dy);
        return .{ .ay = lo.y, .by = hi.y, .slope = 0, .x = @truncate(x), .flat = dy == 0 };
    }
    const slope = slopeQ16(dx, dy);
    const x0: i64 = lo.x + ((@as(i64, slope) * (y0 - lo.y)) >> 16);
    return .{ .ay = lo.y, .by = hi.y, .slope = slope, .x = @truncate(x0), .flat = false };
}

// floor(n * 2^(8 digits) / d) for 0 < d < 2^23, the result fitting an i32, in i32 divides
// (a long division, 8 bits a step): ZIGGY has a divider; an i64 divide is a library call.
fn quot(n: i32, d: i32, comptime digits: u5) i32 {
    var acc = @divFloor(n, d);
    var r = n - acc * d; // 0 .. d-1
    inline for (0..digits) |_| {
        const digit = @divFloor(r << 8, d);
        r = (r << 8) - digit * d;
        acc = (acc << 8) + digit;
    }
    return acc;
}

fn slopeQ16(dx: i32, dy: i32) i32 {
    return quot(dx, dy, 2);
}

const Pass = enum { back, front };

// gm.fillTriangle in Q16 (rows whose centre line y lies in [ay, by) of an edge, columns
// ceil(xl) .. floor(xr)), clipped the same way; a back row is split at the disc's run.
fn fill(buf: *Buf, spans: *Spans, t: Tri, pass: Pass) void {
    var ymin = @min(t[0].y, @min(t[1].y, t[2].y));
    var ymax = @max(t[0].y, @max(t[1].y, t[2].y));
    if (ymin < 0) ymin = 0;
    if (ymax > (BS - 1) * Q) ymax = (BS - 1) * Q;
    var y: i32 = (ymin + 0xFFFF) >> 16; // ceil
    const ylast: i32 = ymax >> 16; // floor
    if (y > ylast) return;
    var edges = [3]Edge{ edge(t[0], t[1], y << 16), edge(t[1], t[2], y << 16), edge(t[2], t[0], y << 16) };
    while (y <= ylast) : (y += 1) {
        const fy: i32 = y << 16;
        var xl: i32 = std.math.maxInt(i32);
        var xr: i32 = std.math.minInt(i32);
        for (&edges) |*e| {
            defer e.x +%= e.slope; // the next row's x (wraps harmlessly once the edge is done)
            if (e.flat or fy < e.ay or fy >= e.by) continue;
            xl = @min(xl, e.x);
            xr = @max(xr, e.x);
        }
        if (xr < xl) continue;
        var l: i32 = (xl +| 0xFFFF) >> 16; // ceil
        var r: i32 = xr >> 16; // floor
        if (l < 0) l = 0;
        if (r > BS - 1) r = BS - 1;
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
