// --------------------------------------------------------------------------
// RACER: a car out of the view is not transformed (R82 board optimisation, OPTIMIZE.md). carview.draw asks before the
// first vertex: a car's bounding sphere (carfile.radiusOf, at the car's size) wholly past one plane of the view means
// every vertex is past it, so every face would be rejected anyway: the picture is the same, the ~150 vertices and their
// faces are saved (the cars behind the camera, the ones round a bend). No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");

pub var break_cull = false; // the native test's A/B: every car transformed

/// True when a sphere of radius r (Q16) round the model's origin is wholly past one plane of the view (the near plane, the
/// sides, the top, the bottom: xform's rejectCodes), so every vertex of the car is too and every face is rejected. The
/// radius grows by a quarter for the posed wheels (a vertex turned about its axle may end a little farther out) and the
/// side planes' normals are taken at 1.5 (>= sqrt 2) and 23 (>= |(20, 11)|): conservative, so no pixel changes.
pub fn outOfView(mv: *const cam.View, r16: i32) bool {
    const r: i64 = r16 + (r16 >> 2);
    const x: i64 = mv.t[0];
    const y: i64 = mv.t[1];
    const z: i64 = mv.t[2];
    if (z + r < clip.near) return true;
    if (x + z + r + (r >> 1) < 0 or x - z - r - (r >> 1) > 0) return true;
    return 20 * y + 11 * z + 23 * r < 0 or 11 * z - 20 * y + 23 * r < 0;
}

test "a culled car would have pushed nothing: camera poses all round the GT" {
    const std = @import("std");
    const carmodel = @import("carmodel.zig");
    const carview = @import("carview.zig");
    const fix = @import("fix.zig");
    const testutil = @import("testutil.zig");
    const trk = @import("trk.zig");
    const t = try trk.parse(@import("data.zig").oval);
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    var cache = try testutil.newCache(carmodel.NV);
    defer std.testing.allocator.free(cache.e);
    var culled: u32 = 0;
    var kept: u32 = 0;
    for (0..16) |a| for (0..6) |d| for (0..3) |h| {
        const yaw: u32 = @intCast(a << 28); // sixteenths of a turn
        const back: i32 = @as(i32, @intCast(d)) * (3 << 15) - (2 << 16);
        const v = cam.view(.{ .pos = .{ back >> 1, @as(i32, @intCast(h)) << 15, -back }, .yaw = yaw, .pitch = 0 });
        const s = carview.Snap{ .pos = .{ 0, 0, 0 }, .angle = @intCast(a * 1000) };
        const mv = carview.modelView(&v, s);
        if (!outOfView(&mv, fix.mul(carmodel.gt.rad7 << 9, s.size))) {
            kept += 1;
            continue;
        }
        culled += 1;
        f.stats = .{};
        break_cull = true;
        defer break_cull = false;
        carview.draw(&f, &cache, &v, &t, s, null, &carmodel.gt, carmodel.LIVERY[1]);
        try std.testing.expectEqual(@as(u32, 0), f.stats.polys);
    };
    try std.testing.expect(culled > 50 and kept > 50); // the sweep tried both sides
}
