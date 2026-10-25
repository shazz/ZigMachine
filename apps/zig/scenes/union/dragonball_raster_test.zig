// dragonball_raster.renderBall and dragonball_squash's Sprite.build against their first
// versions (dragonball.zig's renderBall, drawStars and drawDisc over gm.fillTriangle, and the
// per-pixel resample, kept here verbatim), byte for byte, at every rotation and squash the
// main screen's f32 accumulators take over 20,000 frames.
const std = @import("std");
const gm = @import("dragonball_math.zig");
const raster = @import("dragonball_raster.zig");
const sq = @import("dragonball_squash.zig");

const TWO_PI: f32 = std.math.pi * 2.0;
const BS = gm.BALL_SIZE;

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

test "renderBall paints what the first version painted" {
    var a: raster.Buf = undefined;
    var b: raster.Buf = undefined;
    var rotx: f32 = 0;
    var roty: f32 = 0;
    var spans: raster.Spans = undefined;
    var back_seen = false; // the comparison covers balls with back faces on and off the disc
    for (0..20_000) |_| {
        rotx = @mod(rotx + 0.01, TWO_PI); // Dragonballs.update
        roty = @mod(roty + 0.06, TWO_PI);
        refRender(&a, rotx, roty);
        raster.renderBall(&b, &spans, rotx, roty);
        try std.testing.expectEqualSlices(u8, &a, &b);
        try expectSpansCover(&b, &spans);
        back_seen = back_seen or std.mem.indexOfScalar(u8, &a, raster.PAL_DISC_ON_BACK) != null;
    }
    try std.testing.expect(back_seen);
}

test "a mutant raster is caught" {
    var a: raster.Buf = undefined;
    var b: raster.Buf = undefined;
    var spans: raster.Spans = undefined;
    refRender(&a, 0.3, 1.1);
    raster.renderBall(&b, &spans, 0.3, 1.1);
    b[BS * 32 + 32] +%= 1;
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
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

test "Sprite.build resamples what the first version resampled" {
    var ball: raster.Buf = undefined;
    var ref: [sq.MAX_SPAN * sq.MAX_SPAN]u8 = undefined;
    var s: sq.Sprite = .{};
    var spans: raster.Spans = undefined;
    var rotx: f32 = 0;
    var roty: f32 = 0;
    var u: f32 = 0;
    for (0..20_000) |_| {
        rotx = @mod(rotx + 0.01, TWO_PI); // Dragonballs.update
        roty = @mod(roty + 0.06, TWO_PI);
        u = @mod(u + 0.2, TWO_PI);
        raster.renderBall(&ball, &spans, rotx, roty);
        const sx = 1.0 + @sin(u) / 6.0; // Dragonballs.draw
        const sy = 1.0 + @sin(u + 10.0) / 6.0;
        const d = refBuild(&ref, &ball, sx, sy);
        s.build(&ball, &spans, sx, sy);
        try std.testing.expectEqual(d.w, s.w);
        try std.testing.expectEqual(d.h, s.h);
        for (0..d.h) |r| try std.testing.expectEqualSlices(u8, ref[r * d.w ..][0..d.w], s.pixels()[r * s.stride ..][0..s.w]);
    }
}
