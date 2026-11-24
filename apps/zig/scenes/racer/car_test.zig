// RACER: the physics against the Lua reference (tools/racer/phys_fixture.py), plus its
// behaviour and error paths. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const car = @import("car.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const refrun = @import("refrun.zig");
const seg = @import("seg.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");

const LAP_RAW = @embedFile("../../assets/screens/racer/phys_lap.bin");
const WALL_RAW = @embedFile("../../assets/screens/racer/phys_wall.bin");
const lap_blob: [LAP_RAW.len]u8 align(16) = LAP_RAW.*;
const wall_blob: [WALL_RAW.len]u8 align(16) = WALL_RAW.*;

/// The first tick (1-based) where the port differs from the reference, with the field's name.
fn firstDiff(blob: []align(4) const u8) !?struct { tick: u32, field: []const u8 } {
    const t = try trk.parse(data.oval);
    const fx = try refrun.Fixture.parse(blob);
    var c = refrun.spawn(&t);
    for (fx.rows, 1..) |r, tick| {
        refrun.step(&c, @intCast(tick), @intCast(r.btn));
        if (refrun.diff(&c, r)) |f| return .{ .tick = @intCast(tick), .field = f };
    }
    return null;
}

test "1,500 ticks of the autopilot's buttons (a whole lap) match the Lua bit for bit" {
    try std.testing.expect((try firstDiff(&lap_blob)) == null);
}

test "600 ticks into the outer wall match the Lua bit for bit, hits included" {
    try std.testing.expect((try firstDiff(&wall_blob)) == null);
    const fx = try refrun.Fixture.parse(&wall_blob);
    try std.testing.expect(fx.rows[599].hits > 10);
}

test "--break slip: the slip threshold moved makes the lap differ, in the slide column" {
    car.break_slip = true;
    defer car.break_slip = false;
    const d = (try firstDiff(&lap_blob)).?;
    try std.testing.expectEqualStrings("slide", d.field);
}

test "the lap and the wall run both slide (the slide flag is exercised, not constant)" {
    for ([_][]align(4) const u8{ &lap_blob, &wall_blob }) |b| {
        const fx = try refrun.Fixture.parse(b);
        var on: usize = 0;
        for (fx.rows) |r| on += @intCast(r.slide);
        try std.testing.expect(on > 50 and on < fx.rows.len);
    }
}

test "lap v1's stream from the grid, control from tick 0, ends where the reference is at tick 449" {
    const t = try trk.parse(data.oval);
    const fx = try refrun.Fixture.parse(&lap_blob);
    var c = refrun.spawn(&t);
    for (data.lap_v1) |b| {
        c.control(b);
        c.prepare();
        c.integrate();
        c.update();
    }
    try std.testing.expectEqual(@as(usize, 360), data.lap_v1.len);
    try std.testing.expectEqual(@as(?[]const u8, null), refrun.diff(&c, fx.rows[448]));
}

test "an unknown fixture is refused" {
    var bad: [64]u8 align(4) = @splat(0);
    try std.testing.expectError(error.BadFixture, refrun.Fixture.parse(&bad));
}

test "the car stays on the ground, never touches a wall and laps the oval" {
    const t = try trk.parse(data.oval);
    const fx = try refrun.Fixture.parse(&lap_blob);
    var c = refrun.spawn(&t);
    for (fx.rows, 1..) |r, tick| {
        refrun.step(&c, @intCast(tick), @intCast(r.btn));
        try std.testing.expect(c.old != null);
    }
    try std.testing.expect(c.track.u > 120 << 16); // a whole lap: past segment 120
    try std.testing.expectEqual(@as(u32, 0), c.hits);
}

test "findFace: a point off the grid or over no ground finds nothing; the start finds its face" {
    const t = try trk.parse(data.oval);
    try std.testing.expect(ground.findFace(&t, .{ 200 << 16, 0, 0 }, null) == null);
    try std.testing.expect(ground.findFace(&t, .{ 0, 0, -200 << 16 }, null) == null);
    try std.testing.expect(ground.findFace(&t, .{ 0, 0, 0 }, null) == null); // the infield
    const g = t.grid[0];
    const f = ground.findFace(&t, g.pos, null).?;
    try std.testing.expect(t.faces[f.face].flags & ground.FLAG_ASPHALT != 0);
    try std.testing.expectEqual(f.face, ground.findFace(&t, g.pos, f.face).?.face);
}

test "isInside: a point just past an edge is outside; the plane height comes back" {
    const t = try trk.parse(data.oval);
    const g = t.grid[0];
    const f = ground.findFace(&t, g.pos, null).?;
    const p = ground.poly(&t, f.face);
    try std.testing.expect(ground.isInside(&p, g.pos) != null);
    var out = g.pos;
    out[0] += 40 << 16;
    try std.testing.expect(ground.isInside(&p, out) == null);
}

test "faceCollide: a car in the middle of the road is not pushed; on the shoulder edge it is, along the wall normal" {
    const t = try trk.parse(data.oval);
    var shoulder: ?u16 = null;
    for (t.faces, 0..) |f, i| if (f.borders != 0 and f.flags & ground.FLAG_GROUND != 0) {
        shoulder = @intCast(i);
        break;
    };
    const id = shoulder.?;
    const f = ground.poly(&t, id);
    var k: usize = 0;
    while (t.faces[id].borders & (@as(u16, 1) << @intCast(k)) == 0) k += 1;
    const n = ground.borderNormal(&f, k);
    const on_edge = vec.add(f.p[k], n, fix.lit(0.1)); // 0.1 inside the wall edge: closer than the 0.25 radius
    const h = ground.faceCollide(&t, id, on_edge, fix.lit(0.25));
    try std.testing.expect(h.hit and std.mem.eql(i32, &h.n, &n));
    try std.testing.expect(vec.dot(h.force, n) > 0);
    const far = vec.add(f.p[k], n, 2 << 16);
    try std.testing.expect(!ground.faceCollide(&t, id, far, fix.lit(0.25)).hit);
}

test "two borders on one corner: both push, the later edge's normal is reported" {
    const t = try trk.parse(data.oval);
    // the generator gives a ground face one border: make two from a synthetic mask on a copy
    var faces = try std.testing.allocator.dupe(trk.Face, t.faces);
    defer std.testing.allocator.free(faces);
    const id: u16 = 0;
    faces[id].borders = 0b0101;
    var t2 = t;
    t2.faces = faces;
    const f = ground.poly(&t2, id);
    const centre = vec.lerp(f.p[0], f.p[2], fix.ONE / 2);
    const h = ground.faceCollide(&t2, id, centre, 64 << 16); // a huge radius: every border reaches
    try std.testing.expect(h.hit and std.mem.eql(i32, &h.n, &ground.borderNormal(&f, 2)));
}

test "track position: segment advance, wrap, and a flat segment cannot loop forever" {
    const t = try trk.parse(data.oval);
    var tp = seg.TrackPos.init(&t, 0);
    const q1 = seg.quad(&t, 5);
    const mid5 = vec.lerp(q1.l, q1.r, fix.ONE / 2);
    for (0..7) |_| tp.update(mid5); // one segment a call, as in the original
    try std.testing.expect(tp.segment >= 4 and tp.segment <= 5);
    try std.testing.expect(tp.v > 20000 and tp.v < 46000); // near the middle
    const wrap = seg.quad(&t, -1);
    const last = seg.quad(&t, @intCast(t.lr.len - 1));
    try std.testing.expect(std.mem.eql(i32, &wrap.l, &last.l));
}
