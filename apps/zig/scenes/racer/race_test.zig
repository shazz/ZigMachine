// RACER: the AI cars against the Lua reference (tools/racer/race_fixture.py), plus the grid and
// the error paths. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const car = @import("car.zig");
const contacts = @import("contacts.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const npc = @import("npc.zig");
const race = @import("race.zig");
const racefix = @import("racefix.zig");
const seg = @import("seg.zig");
const trk = @import("trk.zig");

test "2 AI cars and the player match the Lua every tick for 600 ticks, every column" {
    const t = try trk.parse(data.oval);
    var r = try race.Race.init(&t, 3);
    try std.testing.expectEqual(@as(?u32, null), racefix.firstDiff(&r, try racefix.full(.npc2)));
    try std.testing.expect(r.brakes() > 0); // the AI's hard braking ran, not only the straight line
}

test "the AI cars follow the racing line (its far target is ahead, the heading error folded)" {
    const t = try trk.parse(data.oval);
    var r = try race.Race.init(&t, 3);
    const tgt = npc.target(&r.cars[1], &r.lens);
    const a = npc.angleTo(&r.cars[1], tgt);
    try std.testing.expect(a >= fix.lit(0.5) and a <= fix.ONE);
    try std.testing.expect(tgt[2] > r.cars[1].pos[2]); // the oval's start straight runs along +z
}

test "ramming a parked AI car matches the Lua tick for tick, and the contacts really fire" {
    const t = try trk.parse(data.oval);
    var r = try race.Race.init(&t, 3);
    r.parked = 1;
    const fx = try racefix.full(.ram);
    const p = &r.cars[0];
    r.cars[1].pos = .{ p.pos[0], p.pos[1], p.pos[2] + (6 << 16) }; // the scenario's fwd (0, 0, 1) times 6
    try std.testing.expectEqual(@as(?u32, null), racefix.firstDiff(&r, fx));
    try std.testing.expect(r.contacts >= 2); // both colliders pushed
}

test "a parked AI car that is steered anyway makes the ram run differ (the fixture sees the AI)" {
    const t = try trk.parse(data.oval);
    var r = try race.Race.init(&t, 3);
    const p = &r.cars[0];
    r.cars[1].pos = .{ p.pos[0], p.pos[1], p.pos[2] + (6 << 16) };
    try std.testing.expect(racefix.firstDiff(&r, try racefix.full(.ram)) != null);
}

test "7 AI cars: all 8 cars match the Lua's CRC on each of 4,400 ticks (a 3-lap race), and finish when it says" {
    const t = try trk.parse(data.oval);
    const f = try racefix.crc();
    var r = try race.Race.init(&t, 8);
    var finish = [_]u32{0} ** 8;
    const limit: i32 = (3 * 120 - 1) << 16;
    for (0..f.ticks) |k| {
        r.tick(racefix.player_btn[k]);
        try std.testing.expectEqual(f.crcs[k], racefix.crcOf(&r));
        for (&r.cars, &finish) |*c, *fin| {
            if (fin.* == 0 and c.track.u > limit) fin.* = @intCast(k + 1);
        }
    }
    try std.testing.expectEqualSlices(u32, f.finish, &finish);
}

test "the PID starts fresh (nil, not 0) and keeps its state between calls" {
    var p = npc.Pid{};
    const a = p.step(0, fix.lit(0.1), fix.ONE / 30);
    try std.testing.expect(p.prev_err.? == fix.lit(0.1));
    try std.testing.expect(a == fix.mul(2 << 16, fix.lit(0.1)) + p.i_err.? + 0); // d_err is 0 on the first call
    const b = p.step(0, fix.lit(0.1), fix.ONE / 30);
    try std.testing.expect(@abs(a - b) <= 2); // a constant error: only the integrator's rounding moves
}

test "contacts: a car beyond 2 units is ignored, a separating one is not pushed" {
    const t = try trk.parse(data.oval);
    var r = try race.Race.init(&t, 3);
    try std.testing.expectEqual(@as(u32, 0), contacts.update(&r.cars[0], r.cars[1..r.n])); // the grid's cars are 3.7 away
    r.cars[1].pos = r.cars[0].pos; // on top of the player, both at rest: not closing, so no push
    try std.testing.expectEqual(@as(u32, 0), contacts.update(&r.cars[0], r.cars[1..r.n]));
    r.cars[1].vel = .{ 0, 0, -fix.lit(0.1) };
    try std.testing.expect(contacts.update(&r.cars[0], r.cars[1..r.n]) > 0);
}

test "a race needs a grid of at least its cars, and the segment lengths a track within the limit" {
    const t = try trk.parse(data.oval);
    try std.testing.expectError(error.NoGrid, race.Race.init(&t, 9));
    try std.testing.expectError(error.NoGrid, race.Race.init(&t, 0));
    var short = t;
    short.lr = t.lr[0..0];
    short.lr.len = seg.MAXSEG + 1;
    short.lr.ptr = t.lr.ptr;
    try std.testing.expectError(error.TooManySegments, seg.Lens.init(&short));
}

test "the NPC steer sets the angle and brakes harder than the player's" {
    const t = try trk.parse(data.oval);
    var a = car.Car.init(&t, t.grid[0].pos, t.grid[0].yaw, 0);
    var b = a;
    b.npc = true;
    a.vel = .{ 0, 0, fix.ONE };
    b.vel = a.vel;
    a.steer_angle = fix.lit(0.1);
    b.steer_angle = fix.lit(0.1);
    _ = a.steer(fix.lit(0.05), fix.lit(0.7), true);
    _ = b.steer(fix.lit(0.05), fix.lit(0.7), true);
    try std.testing.expectEqual(fix.lit(0.1) + fix.lit(0.05), a.steer_angle); // accumulated
    try std.testing.expectEqual(fix.lit(0.05), b.steer_angle);
    try std.testing.expect(b.vel[2] < a.vel[2]);
}
