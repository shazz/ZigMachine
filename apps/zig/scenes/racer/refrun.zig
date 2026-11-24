// --------------------------------------------------------------------------
// RACER: the Lua reference's fixtures (tools/racer/phys_fixture.py: per tick the player's raw
// 16.16 state under z8lua, the buttons pressed and the wall hits so far) and a runner that plays
// the same buttons through car.zig. Used by the native tests and by lap v1 of the benchmark
// (the lap's input stream is the fixture's). No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const car = @import("car.zig");
const trk = @import("trk.zig");

pub const COUNTDOWN: u32 = 90; // the engine's start_ttl: control begins on tick 90
pub const Row = extern struct { btn: i32, hits: i32, pos: [3]i32, vel: [3]i32, angle: i32, face: i32, u: i32, v: i32, tr: i32, sa: i32, slide: i32 };

pub const Fixture = struct {
    rows: []const Row,

    pub fn parse(b: []align(4) const u8) !Fixture {
        const magic = std.mem.readInt(u32, b[0..4], .little);
        const n = std.mem.readInt(u32, b[4..8], .little);
        if (magic != 0x59485052 or b.len != 8 + n * @sizeOf(Row)) return error.BadFixture;
        const p: [*]const Row = @ptrCast(@alignCast(&b[8]));
        return .{ .rows = p[0..n] };
    }
};

/// The player's car on the grid's first slot, as the reference harness spawns it.
pub fn spawn(t: *const trk.Track) car.Car {
    const g = t.grid[0];
    return car.Car.init(t, g.pos, g.yaw, g.segment);
}

/// One reference tick (1-based): the countdown ticks run no control, as the harness does.
pub fn step(c: *car.Car, tick: u32, buttons: u8) void {
    if (tick >= COUNTDOWN) c.control(buttons);
    c.prepare();
    c.integrate();
    c.update();
}

/// The first field of tick `row` that differs from the car, by name; null when all of them match.
pub fn diff(c: *const car.Car, r: Row) ?[]const u8 {
    if (!std.mem.eql(i32, &c.pos, &r.pos)) return "pos";
    if (!std.mem.eql(i32, &c.vel, &r.vel)) return "vel";
    if (c.angle != r.angle) return "angle";
    if (c.faceId() != r.face) return "face";
    if (c.track.u != r.u) return "u";
    if (c.track.v != r.v) return "v";
    if (c.hits != r.hits) return "hits";
    if (c.total_r != r.tr) return "tr";
    if (c.steer_angle != r.sa) return "sa";
    if (@intFromBool(c.sliding()) != r.slide) return "slide";
    return null;
}
