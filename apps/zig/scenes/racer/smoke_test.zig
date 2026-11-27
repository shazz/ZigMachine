// RACER: tyre smoke (smoke.zig, R82 bug pass): the emission at the drawn tyres, the ring, a puff's two lightened halves on
// one key over its ground face's. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const car = @import("car.zig");
const carmodel = @import("carmodel.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const smoke = @import("smoke.zig");
const testutil = @import("testutil.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");

fn ground_face(t: *const trk.Track, p: [3]i32) u16 {
    return @import("ground.zig").findFace(t, p, null).?.face;
}

test "tyre smoke (R82 bug pass): a sliding car puffs every EVERY ticks, a puff lives TTL ticks, the ring never overflows" {
    const t = try trk.parse(data.oval);
    var s = smoke.Smoke{};
    var c = car.Car.init(&t, t.grid[0].pos, t.grid[0].yaw, t.grid[0].segment);
    c.old = ground_face(&t, c.pos);
    c.rear_slide = true;
    for (0..10) |_| {
        s.emitCar(&c, carmodel.gt.foot);
        s.update();
    }
    try std.testing.expectEqual(@as(usize, 10), s.live()); // 2 rear wheels x 5 puff ticks
    c.rear_slide = false;
    for (0..smoke.TTL) |_| s.update();
    try std.testing.expectEqual(@as(usize, 0), s.live());
    c.front_slide = true;
    c.rear_slide = true;
    for (0..400) |_| {
        s.emitCar(&c, carmodel.gt.foot);
        s.update();
    }
    try std.testing.expect(s.live() <= smoke.MAXP);
    c.old = null; // off the ground: no puff
    var e = smoke.Smoke{};
    e.emitCar(&c, carmodel.gt.foot);
    try std.testing.expectEqual(@as(usize, 0), e.live());
}

test "a puff drawn: two lightened halves on one key, never below its ground face's key; scaled wheel points" {
    const t = try trk.parse(data.oval);
    var f = try testutil.newFrame(&t);
    defer testutil.freeFrame(&f);
    var cache = try testutil.newCache(smoke.MAXP * smoke.VERTS);
    defer std.testing.allocator.free(cache.e);
    var s = smoke.Smoke{};
    const g = t.grid[0];
    s.puff(.{ g.pos[0], g.pos[1], g.pos[2] + (3 << 16) }, ground_face(&t, g.pos), fix.ONE);
    const v = cam.view(.{ .pos = .{ g.pos[0], g.pos[1] + (1 << 16), g.pos[2] }, .yaw = 0, .pitch = 0x0400_0000 });
    f.visibility(&t, &v, 5);
    f.collect(&t, &v, true);
    const b = f.stats.polys;
    s.draw(&f, &cache, &v);
    try std.testing.expectEqual(b + 2, f.stats.polys);
    const under = f.faceKey(ground_face(&t, g.pos)).?;
    for (f.kept[b .. b + 2], f.key[b .. b + 2]) |r, k| {
        try std.testing.expect(r.n & types.LIGHT != 0 and r.n & types.SHADOW == 0);
        try std.testing.expectEqual(f.key[b], k);
        try std.testing.expect(k >= under);
    }
    // the drawn wheels: twice freds72's points, times the car scale
    var c = car.Car.init(&t, g.pos, 0, g.segment);
    c.old = ground_face(&t, c.pos);
    c.rear_slide = true;
    c.size = 2 << 16;
    var e = smoke.Smoke{};
    e.emitCar(&c, carmodel.gt.foot);
    const dx = e.puffs[0].pos[0] - c.pos[0];
    try std.testing.expectEqual(fix.mul(smoke.wheels(carmodel.gt.foot)[2][0] << 9, c.size), dx); // the rear left tyre, in the footprint
    try std.testing.expect(dx < 0 and -dx > fix.mul(carmodel.WHEELS[2][0] * -2, c.size) >> 1); // left, about the GT's drawn tyre
}
