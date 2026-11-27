// RACER: the stuck-car rescue (rescue.zig, R82 32X look item 4): an AI car parked off the asphalt is put back on the
// racing line after STUCK_TICKS, not before; --break rescue (the flag) leaves it there; CLASSIC never rescues; a car
// that leaves the asphalt briefly is not rescued. `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const arcade = @import("arcade.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const race = @import("race.zig");
const rescue = @import("rescue.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const wall = @import("wall.zig");

const K = 3; // the AI car parked off the road (race.parked bit K - 1: never steered)

/// A race on Salt Flats with car K parked, stopped, on the first ground face where all its wheels are off the asphalt.
fn offRoad(t: *const trk.Track, m: arcade.Model) !race.Race {
    var r = try race.Race.init(t, race.NCARS);
    r.setModel(m);
    r.parked = 1 << (K - 1);
    const c = &r.cars[K];
    for (t.faces, 0..) |f, i| {
        if (f.flags & ground.FLAG_GROUND == 0 or f.flags & ground.FLAG_ASPHALT != 0) continue;
        var p = vec.V{ 0, 0, 0 };
        for (f.v[0..f.nv]) |id| p = vec.add(p, ground.vertex(t, id), @divTrunc(fix.ONE, @as(i32, f.nv)));
        c.pos = p;
        c.old = @intCast(i);
        c.vel = .{ 0, 0, 0 };
        if (wall.wheelsOff(c) == arcade.OFF_FULL) return r;
    }
    return error.NoOffRoadFace;
}

test "an AI car off the asphalt is put back on the line after STUCK_TICKS (not before), stopped, its counter reset" {
    const t = try trk.parse(data.salt);
    var r = try offRoad(&t, .arcade);
    for (0..rescue.STUCK_TICKS - 1) |_| r.tick(0);
    try std.testing.expectEqual(@as(u32, 0), r.rescues);
    try std.testing.expectEqual(arcade.OFF_FULL, r.cars[K].eng.off);
    const seg0 = r.cars[K].track.segment;
    r.tick(0);
    try std.testing.expectEqual(@as(u32, 1), r.rescues);
    const c = &r.cars[K];
    try std.testing.expectEqual(seg0 + 1, c.track.segment); // one on, never back: the lap count is kept
    try std.testing.expectEqual(arcade.OFF_NONE, wall.wheelsOff(c)); // on the asphalt
    try std.testing.expect(fix.abs(c.track.v - fix.ONE / 2) < fix.ONE / 8); // on the line's middle
    try std.testing.expectEqual(@as(u16, 0), r.stuck[K].off);
}

test "--break rescue leaves the car off the road; CLASSIC (freds72's) never rescues" {
    const t = try trk.parse(data.salt);
    rescue.break_rescue = true;
    var r = try offRoad(&t, .arcade);
    for (0..3 * rescue.STUCK_TICKS) |_| r.tick(0);
    rescue.break_rescue = false;
    try std.testing.expectEqual(@as(u32, 0), r.rescues);
    try std.testing.expectEqual(arcade.OFF_FULL, wall.wheelsOff(&r.cars[K]));
    var c = try offRoad(&t, .classic);
    for (0..3 * rescue.STUCK_TICKS) |_| c.tick(0);
    try std.testing.expectEqual(@as(u32, 0), c.rescues);
}

test "a short trip off the asphalt is not rescued: the counter restarts when the car is back on it" {
    const t = try trk.parse(data.salt);
    var r = try offRoad(&t, .arcade);
    const c = &r.cars[K];
    var w = rescue.Watch{ .mark = c.track.u };
    const S = struct { // the car crawls on along the line (a segment every 60 ticks): only the off-asphalt rule counts
        fn step(car: anytype, watch: *rescue.Watch, k: usize) bool {
            if (k % 60 == 59) car.track.u += fix.ONE;
            return rescue.tick(car, watch);
        }
    };
    for (0..rescue.STUCK_TICKS - 1) |k| try std.testing.expect(!S.step(c, &w, k));
    c.eng.off = arcade.OFF_HALF; // back on with two wheels
    try std.testing.expect(!S.step(c, &w, 0));
    try std.testing.expectEqual(@as(u16, 0), w.off);
    c.eng.off = arcade.OFF_FULL;
    for (0..rescue.STUCK_TICKS - 1) |k| try std.testing.expect(!S.step(c, &w, k));
    try std.testing.expect(S.step(c, &w, 0));
}

test "a car on the asphalt that gains no segment for STILL_TICKS is put back; one that drives on is not" {
    const t = try trk.parse(data.salt);
    var r = try race.Race.init(&t, race.NCARS);
    r.setModel(.arcade);
    const c = &r.cars[K];
    var w = rescue.Watch{ .mark = c.track.u };
    c.eng.off = arcade.OFF_NONE; // pinned on the road (a wall, a deck): not moving
    for (0..rescue.STILL_TICKS - 1) |_| try std.testing.expect(!rescue.tick(c, &w));
    const seg0 = c.track.segment;
    try std.testing.expect(rescue.tick(c, &w));
    try std.testing.expectEqual(seg0 + 1, c.track.segment);
    w = .{ .mark = c.track.u };
    for (0..2 * rescue.STILL_TICKS) |k| { // a segment gained every 100 ticks: never still long enough
        if (k % 100 == 99) c.track.u += fix.ONE;
        try std.testing.expect(!rescue.tick(c, &w));
    }
}
