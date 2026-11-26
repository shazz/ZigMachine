// --------------------------------------------------------------------------
// RACER: a car under the ARCADE physics (R82, the "32X feel"; FEEL.md). car.zig's tick calls in here when
// `model == .arcade`; freds72's steering, tyre slip and yaw (car.steer) are kept, the rest is ours:
//   control   the pedals ramp in (arcade.Engine): accelerate, brake
//   prepare   the contact forces and the yaw as freds72's; the FORWARD speed from our engine curves
//             (arcade.speed), the sideways speed damped as freds72's 0.97 does
//   move      the position advances vel x world (the track's world scale, trk.Scale: the velocity stays
//             in freds72's units, so its km/h and its handling are his, the ground goes by `world` times
//             faster), in sub-steps of at most STEP so no wall or segment is skipped; each sub-step finds
//             the ground and answers a wall (wall.zig)
//   finish    the wheels off the asphalt (the next tick's off-road drag), the engine note's rpm
// Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const arcade = @import("arcade.zig");
const car = @import("car.zig");
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const vec = @import("vec.zig");
const wall = @import("wall.zig");
const lit = fix.lit;

const DT = lit(0.5 / 30.0); // car.zig's
pub const STEP = lit(0.4); // the longest sub-step (world units): under a segment, under the wall collider's reach
pub const MAX_STEPS = 16;
const SPIN = lit(60.0 / 900.0); // wheelspin (skidmarks) under 60 km/h with the throttle more than 3/4 in

pub fn pedals(c: *car.Car, buttons: u8) void {
    c.eng.press(buttons & car.BTN_ACCEL != 0, buttons & car.BTN_BRAKE != 0);
}

/// The end of car.steer: freds72's yaw torque only (the engine is ours); the engine note's rpm back.
pub fn steered(c: *car.Car, torque: i32, braking: bool) i32 {
    if (braking) c.brakes += @intFromBool(c.npc);
    c.applyForceAndTorque(.{ 0, 0, 0 }, torque);
    const s = vec.dot(c.axes().fwd, c.vel);
    c.rear_slide = c.eng.thr > 192 and s < SPIN;
    return arcade.rpm(arcade.block(), s);
}

pub fn prepare(c: *car.Car) void {
    c.vel = vec.add(c.vel, c.forces, DT);
    c.angv +%= fix.div(fix.mul(c.torque, lit(0.5)), 30 << 16);
    c.angv = fix.mul(c.angv, lit(0.8));
    const fwd = c.axes().fwd;
    const s = vec.dot(fwd, c.vel);
    const side = vec.scale(vec.add(c.vel, fwd, -s), lit(0.97));
    c.vel = vec.add(side, fwd, arcade.speed(arcade.block(), s, c.eng.thr, c.eng.brake, c.eng.off));
}

/// How many sub-steps a tick's displacement `d` needs.
pub fn steps(d: vec.V) u32 {
    const n = @divTrunc(fix.abs(d[0]) + fix.abs(d[2]), STEP) + 1;
    return @intCast(@min(n, MAX_STEPS));
}

pub fn move(c: *car.Car) void {
    c.angv = fix.mid(c.angv, -fix.ONE, fix.ONE);
    c.angle +%= c.angv;
    c.forces = .{ 0, 0, 0 };
    c.torque = 0;
    const d = vec.scale(c.vel, c.world);
    const n = steps(d);
    const piece = vec.scale(d, @intCast(@divTrunc(fix.ONE, @as(i32, @intCast(n)))));
    for (0..n) |_| {
        const prev = c.pos;
        c.pos = vec.add(c.pos, piece, fix.ONE);
        if (ground.findFace(c.t, c.pos, c.old)) |f| {
            c.pos[1] = f.y;
            c.old = f.face;
        }
        c.pos[1] = fix.max(c.pos[1], 0);
        const hit = wall.respond(c, prev);
        c.track.update(c.pos);
        if (hit) break; // the velocity is the wall's answer now: the rest of the tick is not driven
    }
}

pub fn finish(c: *car.Car) void {
    c.steer_angle = fix.mul(c.steer_angle, lit(0.8));
    c.eng.off = wall.wheelsOff(c);
    c.total_r +%= fix.div(fix.mul(vec.dot(c.axes().fwd, c.vel), c.world), lit(0.2638));
}
