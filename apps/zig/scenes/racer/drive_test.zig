// RACER: driving: the tick cadence, the 60 Hz pose, the POV camera, the car's view, lap v1 against
// the Lua reference, the car's polygons in the sort, skidmarks. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const car = @import("car.zig");
const clip = @import("clip.zig");
const data = @import("data.zig");
const drive = @import("drive.zig");
const frame = @import("frame.zig");
const refrun = @import("refrun.zig");
const carmodel = @import("carmodel.zig");
const fix = @import("fix.zig");
const smoke = @import("smoke.zig");
const testutil = @import("testutil.zig");
const types = @import("types.zig");
const trk = @import("trk.zig");
const xf = @import("xform.zig");

const LAP_RAW = @embedFile("../../assets/screens/racer/phys_lap.bin");
const lap_blob: [LAP_RAW.len]u8 align(16) = LAP_RAW.*;

test "a tick every second update by count; off mode does not tick; a tick's frame shows the midpoint" {
    const t = try trk.parse(data.oval);
    var d = drive.Drive.init(&t);
    for (0..10) |_| d.update();
    try std.testing.expectEqual(@as(u32, 0), d.ticks);
    d.setMode(.drive);
    d.press(0, true);
    for (0..10) |_| d.update();
    try std.testing.expectEqual(@as(u32, 5), d.ticks);
    try std.testing.expectEqual(d.cur.pos, d.shown().pos); // frame 10 (no tick) shows the current pose
    d.update(); // frame 11 ticks: the midpoint of the last two poses
    try std.testing.expectEqual(d.prev.pos[0] + ((d.cur.pos[0] - d.prev.pos[0]) >> 1), d.shown().pos[0]);
}

test "lap v1: 720 frames of the reference's buttons end where the Lua is at tick 449, then the car is back on the grid" {
    const t = try trk.parse(data.oval);
    const fxt = try refrun.Fixture.parse(&lap_blob);
    var d = drive.Drive.init(&t);
    d.setMode(.bench);
    for (0..720) |_| d.update();
    try std.testing.expectEqual(@as(u32, 360), d.ticks);
    try std.testing.expectEqual(@as(?[]const u8, null), refrun.diff(&d.car, fxt.rows[448]));
    var slides: u32 = 0;
    for (fxt.rows[89..449]) |r| slides += @intCast(r.slide);
    try std.testing.expectEqual(slides, d.slides);
    d.update();
    try std.testing.expectEqual(@as(u32, 1), d.ticks);
    try std.testing.expect(d.car.track.segment <= t.grid[0].segment + 1); // the grid again, not 360 ticks on
}

test "the arrows and the joystick fire map to buttons; an unknown direction is ignored" {
    const t = try trk.parse(data.oval);
    var d = drive.Drive.init(&t);
    d.press(5, true);
    d.press(2, true);
    try std.testing.expectEqual(car.BTN_ACCEL | car.BTN_LEFT, d.held);
    d.press(5, false);
    d.press(9, true);
    try std.testing.expectEqual(car.BTN_LEFT, d.held);
}

test "the camera looks where the car points: the view's forward row equals the car's forward axis" {
    const t = try trk.parse(data.oval);
    var d = drive.Drive.init(&t);
    d.setMode(.drive);
    d.car.angle = 0x2345;
    d.cur.angle = 0x2345;
    d.prev.angle = 0x2345;
    d.frames = 2;
    var p = d.pose();
    p.pitch = 0;
    const v = cam.view(p);
    const fwd = d.car.axes().fwd;
    try std.testing.expect(@abs((v.r[2][0] >> 9) - fwd[0]) < 16 and @abs((v.r[2][2] >> 9) - fwd[2]) < 16);
}

test "the angle midpoint takes the short way round a full turn" {
    const t = try trk.parse(data.oval);
    var d = drive.Drive.init(&t);
    d.prev.angle = 0xFFF0;
    d.cur.angle = 0x10010;
    d.frames = 1;
    try std.testing.expectEqual(@as(i32, 0x10000), d.shown().angle);
}

test "the POV lerps over 30 ticks; the cockpit takes the 0.05 near plane only when settled and draws no body" {
    const t = try trk.parse(data.oval);
    var d = drive.Drive.init(&t);
    d.setMode(.drive);
    d.nextPov();
    d.nextPov();
    try std.testing.expectEqual(cam.Pov.cockpit, d.pov);
    try std.testing.expectEqual(clip.NEAR, d.near());
    for (0..60) |_| d.update();
    try std.testing.expectEqual(clip.NEAR_COCKPIT, d.near());
    d.nextPov();
    try std.testing.expectEqual(cam.Pov.far, d.pov);
}

test "a polygon across the 0.05 near plane is cut there, not at 0.25" {
    clip.near = clip.NEAR_COCKPIT;
    defer clip.near = clip.NEAR;
    var p = clip.Poly{};
    for ([_]clip.V3{ .{ -1000, 0, 2000 }, .{ 1000, 0, 2000 }, .{ 1000, 0, 90000 }, .{ -1000, 0, 90000 } }) |v| {
        p.p[p.n] = v;
        p.n += 1;
    }
    clip.clip(&p, 1 << @intFromEnum(clip.Plane.near));
    var at: usize = 0;
    for (p.p[0..p.n]) |v| {
        try std.testing.expect(v[2] >= clip.NEAR_COCKPIT);
        at += @intFromBool(v[2] == clip.NEAR_COCKPIT);
    }
    try std.testing.expectEqual(@as(usize, 2), at);
}

fn newFrame(t: *const trk.Track, cap: usize) !frame.Frame {
    const a = std.testing.allocator;
    const e = try a.alloc(xf.Entry, t.verts.len);
    @memset(e, std.mem.zeroes(xf.Entry));
    const seen = try a.alloc(u32, t.faces.len);
    @memset(seen, 0);
    return .{
        .cache = .{ .e = e }, .kept = try a.alloc(frame.Rec, cap), .key = try a.alloc(u16, cap),
        .order = try a.alloc(u16, cap), .count = try a.create([frame.BUCKETS + 1]u32), .seen = seen,
        .fkey = try a.alloc(u16, t.faces.len),
    };
}

fn freeFrame(f: *frame.Frame) void {
    const a = std.testing.allocator;
    a.free(f.cache.e);
    a.free(f.kept);
    a.free(f.key);
    a.free(f.order);
    a.destroy(f.count);
    a.free(f.seen);
    a.free(f.fkey);
}

test "the car's polygons join the frame in the far and near views, never the cockpit's, and sit after their road quad" {
    const t = try trk.parse(data.oval);
    var f = try newFrame(&t, frame.MAXP);
    defer freeFrame(&f);
    var cache = xf.Cache{ .e = try std.testing.allocator.alloc(xf.Entry, @import("carmodel.zig").NV) };
    defer std.testing.allocator.free(cache.e);
    @memset(cache.e, std.mem.zeroes(xf.Entry));
    var d = drive.Drive.init(&t);
    d.setMode(.drive);
    d.update();
    var counts: [3]u32 = undefined;
    for ([_]cam.Pov{ .far, .near, .cockpit }, 0..) |pov, i| {
        d.pov = pov;
        d.from = pov;
        const v = cam.view(d.pose());
        f.visibility(&t, &v, 5);
        f.collect(&t, &v, true);
        const before = f.stats.polys;
        d.drawCar(&f, &cache, &v);
        counts[i] = f.stats.polys - before;
    }
    try std.testing.expect(counts[0] >= 3 and counts[1] >= 3);
    try std.testing.expectEqual(@as(u32, 0), counts[2]);
}

test "tyre smoke (R82 bug pass): a sliding car puffs every EVERY ticks, a puff lives TTL ticks, the ring never overflows" {
    const t = try trk.parse(data.oval);
    var s = smoke.Smoke{};
    var c = car.Car.init(&t, t.grid[0].pos, t.grid[0].yaw, t.grid[0].segment);
    c.old = ground_face(&t, c.pos);
    c.rear_slide = true;
    for (0..10) |_| {
        s.emitCar(&c);
        s.update();
    }
    try std.testing.expectEqual(@as(usize, 10), s.live()); // 2 rear wheels x 5 puff ticks
    c.rear_slide = false;
    for (0..smoke.TTL) |_| s.update();
    try std.testing.expectEqual(@as(usize, 0), s.live());
    c.front_slide = true;
    c.rear_slide = true;
    for (0..400) |_| {
        s.emitCar(&c);
        s.update();
    }
    try std.testing.expect(s.live() <= smoke.MAXP);
    c.old = null; // off the ground: no puff
    var e = smoke.Smoke{};
    e.emitCar(&c);
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
    e.emitCar(&c);
    const dx = e.puffs[0].pos[0] - c.pos[0];
    try std.testing.expectEqual(fix.mul(carmodel.WHEELS[2][0] * 2, c.size), dx);
}

fn ground_face(t: *const trk.Track, p: [3]i32) u16 {
    return @import("ground.zig").findFace(t, p, null).?.face;
}

test "lap v1 with a moved slip threshold prints a different slide count (--break slip)" {
    const t = try trk.parse(data.oval);
    var a = drive.Drive.init(&t);
    a.setMode(.bench);
    for (0..720) |_| a.update();
    car.break_slip = true;
    defer car.break_slip = false;
    var b = drive.Drive.init(&t);
    b.setMode(.bench);
    for (0..720) |_| b.update();
    try std.testing.expect(a.slides != b.slides);
}
