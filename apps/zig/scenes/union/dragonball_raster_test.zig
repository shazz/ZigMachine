// dragonball_raster.renderBall and dragonball_squash's Sprite.build (fixed point since
// 2026-10-25) against their first, f32 versions (dragonball.zig's renderBall, drawStars and
// drawDisc over gm.fillTriangle, and the per-pixel resample, kept here verbatim) at the same
// angles and squashes, over 20,000 frames of the accumulators: only a handful of pixels may
// differ (measured: 107 ball texels in 20,000 frames, at most 1 a frame -- the rows a
// triangle seen edge-on covers or not -- and none in the squash).
const std = @import("std");
const gm = @import("dragonball_math.zig");
const raster = @import("dragonball_raster.zig");
const sq = @import("dragonball_squash.zig");
const fixsin = @import("fixsin.zig");

const TWO_PI: f32 = std.math.pi * 2.0; // the reference's star phases
const BS = gm.BALL_SIZE;

// The five stars' y rotations, 72 degrees apart (dragonball.zig rounds them as the f32 sums).
fn phases(roty: u32) [gm.NSTARS]u32 {
    var t: [gm.NSTARS]u32 = undefined;
    for (&t, 0..) |*p, k| p.* = roty +% @as(u32, @intCast(k)) *% 858993459;
    return t;
}

fn radians(a: u32) f32 {
    return @floatCast(@as(f64, @floatFromInt(a)) / 4294967296.0 * 2.0 * std.math.pi);
}

var worst_reach: usize = 0;
const MAX_A_FRAME = 4; // differing ball texels allowed in one frame

// Pixels of `got` (w x h) that differ from `want`; worst_reach keeps how far the nearest pixel
// of the same colour in `want` was (9: none within 8).
fn edgeDiffs(want: []const u8, got: []const u8, w: usize, h: usize) usize {
    var n: usize = 0;
    for (0..h) |y| for (0..w) |x| {
        const v = got[y * w + x];
        if (want[y * w + x] == v) continue;
        n += 1;
        const d = distance(want, w, h, x, y, v, 8);
        worst_reach = @max(worst_reach, d);
    };
    return n;
}

// The Chebyshev distance from (x, y) to the nearest `v` in `pic`, up to `max` (else max + 1).
fn distance(pic: []const u8, w: usize, h: usize, x: usize, y: usize, v: u8, max: usize) usize {
    for (1..max + 1) |r| {
        for (y -| r..@min(y + r + 1, h)) |yy| for (x -| r..@min(x + r + 1, w)) |xx| {
            if (pic[yy * w + xx] == v) return r;
        };
    }
    return max + 1;
}

fn refRender(buf: *raster.Buf, rotx: f32, roty: f32) void {
    @memset(buf, 0);
    var proj: [gm.NSTARS][gm.NVERTS]gm.Vec2 = undefined;
    for (0..gm.NSTARS) |s| {
        const phase: f32 = @as(f32, @floatFromInt(s)) * (TWO_PI / @as(f32, gm.NSTARS));
        const ay = roty + phase;
        for (0..gm.NVERTS) |v| proj[s][v] = gm.project(gm.rotate(gm.VERTS[v], rotx, ay));
    }
    refStars(buf, &proj, false);
    for (gm.DISC_SPAN, 0..) |span, y| {
        for (buf[y * BS + span[0] ..][0 .. span[1] - span[0]]) |*px| {
            if (px.* == raster.PAL_BACK) px.* = raster.PAL_DISC_ON_BACK else if (px.* == 0) px.* = raster.PAL_DISC;
        }
    }
    refStars(buf, &proj, true);
}

fn refStars(buf: *raster.Buf, proj: *const [gm.NSTARS][gm.NVERTS]gm.Vec2, front: bool) void {
    for (0..gm.NSTARS) |s| {
        for (gm.TRIS) |t| {
            const v0 = proj[s][t[0]];
            const v1 = proj[s][t[1]];
            const v2 = proj[s][t[2]];
            const is_front = gm.signedArea(v0, v1, v2) <= 0;
            if (is_front != front) continue;
            gm.fillTriangle(buf, v0, v1, v2, if (front) raster.PAL_FRONT else raster.PAL_BACK);
        }
    }
}

test "renderBall paints the first version's picture but for edge pixels" {
    var a: raster.Buf = undefined;
    var b: raster.Buf = undefined;
    var rotx: u32 = 0;
    var roty: u32 = 0;
    var spans: raster.Spans = undefined;
    var back_seen = false; // the comparison covers balls with back faces on and off the disc
    var diffs: usize = 0;
    var worst: usize = 0;
    for (0..20_000) |_| {
        rotx +%= fixsin.rad(0.01); // Dragonballs.update
        roty +%= fixsin.rad(0.06);
        refRender(&a, radians(rotx), radians(roty));
        raster.renderBall(&b, &spans, rotx, &phases(roty));
        const n = edgeDiffs(&a, &b, BS, BS);
        diffs += n;
        worst = @max(worst, n);
        try expectSpansCover(&b, &spans);
        back_seen = back_seen or std.mem.indexOfScalar(u8, &a, raster.PAL_DISC_ON_BACK) != null;
    }
    std.debug.print("raster: {d} differing texels in 20000 frames, worst frame {d}, worst reach {d} px\n", .{ diffs, worst, worst_reach });
    try std.testing.expect(back_seen);
    try std.testing.expect(worst <= MAX_A_FRAME);
    try std.testing.expect(diffs < 1_000); // of ~2,000 star texels a frame
}

test "a mutant raster is caught" {
    var a: raster.Buf = undefined;
    var b: raster.Buf = undefined;
    var spans: raster.Spans = undefined;
    refRender(&a, radians(1 << 28), radians(3 << 29));
    raster.renderBall(&b, &spans, 1 << 28, &phases(3 << 29));
    @memset(b[BS * 32 ..][0..8], raster.PAL_FRONT ^ 1); // 8 wrong pixels: more than an edge moves
    try std.testing.expect(edgeDiffs(&a, &b, BS, BS) > MAX_A_FRAME);
}

// Every non-zero pixel of a row lies in its span (Sprite.build gathers only there).
fn expectSpansCover(buf: *const raster.Buf, spans: *const raster.Spans) !void {
    for (spans, 0..) |span, y| for (buf[y * BS ..][0..BS], 0..) |px, x| {
        if (px != 0) try std.testing.expect(x >= span[0] and x < span[1]);
    };
}

// The first Sprite.build: a w x h picture, one pixel at a time.
fn refBuild(out: []u8, ball: *const raster.Buf, sx: f32, sy: f32) struct { w: usize, h: usize } {
    const x0 = @floor(-gm.CENTER * sx);
    const y0 = @floor(-gm.CENTER * sy);
    const w: usize = @intCast(@min(@as(i32, @intFromFloat(@ceil(gm.CENTER * sx) - x0)), sq.MAX_SPAN));
    const h: usize = @intCast(@min(@as(i32, @intFromFloat(@ceil(gm.CENTER * sy) - y0)), sq.MAX_SPAN));
    var cols: [sq.MAX_SPAN]i16 = undefined;
    for (cols[0..w], 0..) |*c, k| c.* = refTexel(x0, k, sx);
    for (0..h) |r| {
        const row = out[r * w ..][0..w];
        const ty = refTexel(y0, r, sy);
        if (ty < 0) {
            @memset(row, 0);
            continue;
        }
        const src = ball[@as(usize, @intCast(ty)) * BS ..][0..BS];
        for (row, cols[0..w]) |*px, c| px.* = if (c < 0) 0 else src[@intCast(c)];
    }
    return .{ .w = w, .h = h };
}

fn refTexel(o: f32, k: usize, s: f32) i16 {
    const v = gm.CENTER + (o + @as(f32, @floatFromInt(k)) + 0.5) / s;
    if (v < 0 or v >= @as(f32, BS)) return -1;
    return @intFromFloat(v);
}

test "Sprite.build resamples the first version's picture but for edge pixels" {
    var ball: raster.Buf = undefined;
    var ref: [sq.MAX_SPAN * sq.MAX_SPAN]u8 = undefined;
    var got: [sq.MAX_SPAN * sq.MAX_SPAN]u8 = undefined;
    var s: sq.Sprite = .{};
    var spans: raster.Spans = undefined;
    var rotx: u32 = 0;
    var roty: u32 = 0;
    var u: u32 = 0;
    var diffs: usize = 0;
    for (0..20_000) |_| {
        rotx +%= fixsin.rad(0.01); // Dragonballs.update
        roty +%= fixsin.rad(0.06);
        u +%= fixsin.rad(0.2);
        raster.renderBall(&ball, &spans, rotx, &phases(roty));
        const sx = sq.squash(u); // Dragonballs.draw
        const sy = sq.squash(u +% fixsin.rad(10.0));
        const d = refBuild(&ref, &ball, @as(f32, @floatFromInt(sx)) / 65536.0, @as(f32, @floatFromInt(sy)) / 65536.0);
        s.build(&ball, &spans, sx, sy);
        try std.testing.expectEqual(d.w, s.w);
        try std.testing.expectEqual(d.h, s.h);
        for (0..d.h) |r| @memcpy(got[r * d.w ..][0..d.w], s.pixels()[r * s.stride ..][0..s.w]);
        diffs += edgeDiffs(ref[0 .. d.w * d.h], got[0 .. d.w * d.h], d.w, d.h);
    }
    std.debug.print("squash: {d} differing pixels in 20000 frames\n", .{diffs});
    try std.testing.expect(diffs < 100);
}
