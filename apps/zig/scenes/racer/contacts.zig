// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// make_car's update_contacts.
//
// RACER: car-vs-car, as the original has it: only the PLAYER feels other cars. Two circular
// colliders sit 0.25 ahead of and behind the player's centre; one within 0.312 of another
// car's centre, and closing, pushes the player away (a force along the separation) and turns it
// (a torque about the collider's offset). The other car feels nothing, and the AI cars do not
// see each other: they can overlap (the painter's order then sorts whole cars by depth, M3.md).
// Only the first car within 2 units is looked at ("assumes only 1 actor in range"). Returns the
// number of contacts (the original's hit sound), which the reference runs count too.
// No ZigOS import.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const fix = @import("fix.zig");
const vec = @import("vec.zig");
const lit = fix.lit;

const RANGE = 2 << 16;
const RADIUS = lit(0.312);
const OFFSETS = [2]i32{ lit(0.25), -lit(0.25) };

/// Queue the contact forces on `me` for this tick (before its `prepare`). The player's velocity is the one after `control`.
pub fn update(me: *car.Car, others: []const car.Car) u32 {
    const fwd = me.axes().fwd;
    var n: u32 = 0;
    for (others) |*a| {
        if (vec.len(vec.between(me.pos, a.pos)) >= fix.mul(RANGE, me.size)) continue;
        for (OFFSETS) |off| n += @intFromBool(collide(me, a, fwd, fix.mul(off, me.size)));
        break;
    }
    return n;
}

fn collide(me: *car.Car, a: *const car.Car, fwd: vec.V, off: i32) bool {
    var axis = vec.between(a.pos, vec.add(me.pos, fwd, off));
    const depth = vec.len(axis);
    if (depth >= fix.mul(RADIUS, me.size)) return false; // size: the ARCADE car's scale (fix.ONE, exact, in CLASSIC)
    const spin: vec.V = .{ fix.mul(0 -% me.angv, off), 0, 0 }; // v2_ortho({0, 0, off}, angularv)
    const relv = vec.between(a.vel, vec.add(me.vel, spin, fix.ONE));
    if (vec.dot(axis, relv) >= 0) return false;
    axis = vec.scale(axis, 5 << 16);
    const cross = fix.mul(0, axis[2]) -% fix.mul(off, axis[0]); // v2_cross({0, 0, off}, axis)
    me.applyForceAndTorque(axis, fix.mul(fix.mul(-2 << 16, depth), cross));
    return true;
}
