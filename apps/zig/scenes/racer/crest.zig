// --------------------------------------------------------------------------
// RACER: the crest test pose (key K, and the painter's-order tests): the oval's hump, with the
// player on its near side, one AI car just before the crest and one just past it, the rest of the
// field far away. From the player's chase camera the road over the crest must be painted over
// the car beyond it and under the car before it (the sort's one list: frame.zig, project.zig).
// The race stays on the grid, so nothing moves. No ZigOS import.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const game = @import("game.zig");
const trk = @import("trk.zig");

/// The racing-line segment with the highest centre.
pub fn segment(t: *const trk.Track) usize {
    var best: usize = 0;
    for (t.line, 0..) |s, i| {
        if (s.pos[1] > t.line[best].pos[1]) best = i;
    }
    return best;
}

/// Car `k` on the racing line at segment `s`, at rest, on the ground.
pub fn place(g: *game.Game, k: usize, s: usize) void {
    const l = g.t.line[s % g.t.line.len];
    var c = car.Car.init(g.t, l.pos, @as(i32, l.yaw), @intCast(s % g.t.line.len));
    c.npc = k > 0;
    c.update();
    g.s.race.cars[k] = c;
    g.cur[k] = .{ .pos = c.pos, .angle = c.angle };
    g.prev[k] = g.cur[k];
}

pub const BEHIND = 6; // the player's segments before the crest
pub const NEAR_CAR = 4; // AI car 1: segments before it
pub const FAR_CAR = 3; // AI car 2: segments past it

pub fn setup(g: *game.Game) void {
    const ci = segment(g.t);
    for (3..g.s.race.n) |k| place(g, k, ci + 40 + k);
    place(g, 0, ci - BEHIND);
    place(g, 1, ci - NEAR_CAR);
    place(g, 2, ci + FAR_CAR);
}
