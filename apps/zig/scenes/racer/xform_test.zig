// RACER natively: the transform's two paths (mulsh and the f32 A/B) agree to a few LSB of Q16, and the
// vertex cache transforms each vertex once a frame (a second sight is free, a new frame redoes it).
const std = @import("std");
const cam = @import("cam.zig");
const data = @import("data.zig");
const fx = @import("fx.zig");
const trk = @import("trk.zig");
const xf = @import("xform.zig");

test "the f32 transform is within 64 LSB of Q16 of the mulsh one on every vertex of the city" {
    const t = try trk.parse(data.city);
    var v = cam.view(cam.fixedPose(&t, 1));
    cam.floatView(&v);
    var c = xf.Cache{ .e = try std.testing.allocator.alloc(xf.Entry, t.verts.len) };
    defer std.testing.allocator.free(c.e);
    @memset(c.e, std.mem.zeroes(xf.Entry));
    c.next();
    var worst: i32 = 0;
    for (0..t.verts.len) |i| {
        fx.use_f32 = false;
        const a = xf.get(&c, &v, t.verts, @intCast(i)).v;
        c.e[i].stamp = 0; // force the second path to compute it too
        fx.use_f32 = true;
        const b = xf.get(&c, &v, t.verts, @intCast(i)).v;
        for (a, b) |p, q| worst = @max(worst, @as(i32, @intCast(@abs(p - q))));
    }
    fx.use_f32 = false;
    try std.testing.expect(worst <= 64);
}

test "a vertex is transformed once a frame: touched counts first sights, next() starts over" {
    const t = try trk.parse(data.oval);
    const v = cam.view(cam.fixedPose(&t, 0));
    var c = xf.Cache{ .e = try std.testing.allocator.alloc(xf.Entry, t.verts.len) };
    defer std.testing.allocator.free(c.e);
    @memset(c.e, std.mem.zeroes(xf.Entry));
    c.next();
    _ = xf.get(&c, &v, t.verts, 5);
    _ = xf.get(&c, &v, t.verts, 5);
    _ = xf.get(&c, &v, t.verts, 6);
    try std.testing.expectEqual(@as(u32, 2), c.touched);
    c.next();
    _ = xf.get(&c, &v, t.verts, 5);
    try std.testing.expectEqual(@as(u32, 1), c.touched);
}

test "the stamp wrapping to zero clears the cache instead of trusting stale entries" {
    var e = [_]xf.Entry{std.mem.zeroes(xf.Entry)};
    var c = xf.Cache{ .e = &e, .stamp = 0xFFFF };
    e[0].stamp = 7;
    c.next();
    try std.testing.expectEqual(@as(u16, 1), c.stamp);
    try std.testing.expectEqual(@as(u16, 0), e[0].stamp);
}
