// --------------------------------------------------------------------------
// RACER: the ARCADE physics' ground contact (R82, the "32X feel"; FEEL.md), our code for the 32X's behaviour:
//   - off-road: the four wheel corners are looked up on the ground; 3 or 4 off the asphalt = the full
//     off-road drag (arcade.zig), 1 or 2 = half of it;
//   - walls: a car whose centre touches a wall edge is rolled back to the last quarter of its tick's
//     motion that was free (no push out of the wall), turned onto the racing line's heading there, and
//     keeps cos(heading error) of its speed along it;
//   - a hard crash (fast, at a steep angle: thresholds of our own) puts the car back on the racing line,
//     stopped, one segment on.
// CLASSIC keeps freds72's push-out (car.zig `collide`). Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const arcade = @import("arcade.zig");
const car = @import("car.zig");
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const seg = @import("seg.zig");
const vec = @import("vec.zig");
const V = vec.V;
const lit = fix.lit;

const RADIUS = lit(0.25); // freds72's collider radius
const HALF_W = lit(0.11); // the wheel corners: our car model's half width ...
const HALF_L = lit(0.2); // ... and half length (carmodel.zig, M2's halved model)
pub const CRASH_SPEED = lit(150.0 / 900.0); // 150 km/h
pub const CRASH_ANGLE = lit(1.0 / 12.0); // 30 degrees off the racing line
const MIN_KEEP = lit(0.25);

/// How many wheels are off the asphalt, as the engine's off-road level.
pub fn wheelsOff(c: *const car.Car) u2 {
    const ax = c.axes();
    var n: u32 = 0;
    for ([4][2]i32{ .{ 1, 1 }, .{ -1, 1 }, .{ 1, -1 }, .{ -1, -1 } }) |k| {
        const p = vec.add(vec.add(c.pos, ax.right, k[0] * fix.mul(HALF_W, c.size)), ax.fwd, k[1] * fix.mul(HALF_L, c.size));
        const f = ground.findFace(c.t, p, c.old) orelse {
            n += 1;
            continue;
        };
        n += @intFromBool(c.t.faces[f.face].flags & ground.FLAG_ASPHALT == 0);
    }
    return if (n >= 3) arcade.OFF_FULL else if (n >= 1) arcade.OFF_HALF else arcade.OFF_NONE;
}

/// The racing line's heading at segment i (a car angle: axes().fwd points along it).
pub fn lineYaw(c: *const car.Car, i: i32) i32 {
    const a = seg.corners(c.t, i);
    const b = seg.corners(c.t, i + 1);
    const d = vec.between(vec.lerp(a.l, a.r, fix.ONE / 2), vec.lerp(b.l, b.r, fix.ONE / 2));
    return fix.atan2(d[0], d[2]) +% fix.ONE / 4;
}

fn radius(c: *const car.Car) i32 {
    _ = c;
    return RADIUS;
}

/// A point is free when it has ground and no wall edge of its face within the collider's radius.
fn free(c: *const car.Car, p: V) bool {
    const f = ground.findFace(c.t, p, c.old) orelse return false;
    return !ground.faceCollide(c.t, f.face, p, radius(c)).hit;
}

/// After `update` found the ground: a wall hit rolls back, turns and slows the car (or crashes it). True on a hit.
pub fn respond(c: *car.Car, prev: V) bool {
    const old = c.old orelse return false;
    if (c.t.faces[old].borders == 0) return false;
    const hit = ground.faceCollide(c.t, old, c.pos, radius(c));
    if (!hit.hit) return false;
    c.hits += 1;
    const s = vec.dot(c.axes().fwd, c.vel);
    const yaw = surfaceYaw(c, hit.n);
    const err = @as(i32, @as(i16, @truncate(c.angle -% yaw))); // -0.5 .. 0.5 of a turn
    if (s > CRASH_SPEED and fix.abs(err) > CRASH_ANGLE) return crash(c);
    c.pos = rollback(c, prev);
    if (ground.findFace(c.t, c.pos, c.old)) |f| c.old = f.face;
    const h = ground.faceCollide(c.t, c.old.?, c.pos, radius(c));
    if (h.hit) c.pos = vec.add(c.pos, h.force, fix.ONE); // still within reach (it was, the tick before): out, as freds72's
    c.angle = yaw;
    c.angv = 0;
    c.vel = vec.scale(c.axes().fwd, fix.mul(fix.max(s, 0), fix.max(fix.cos(err), MIN_KEEP)));
    return true;
}

/// The surface's heading where the car hit: the racing line's, or, where that runs into the wall (the outside of a
/// hairpin), the wall's own direction taken the line's way, so the car always slides on.
fn surfaceYaw(c: *const car.Car, n: V) i32 {
    const yaw = lineYaw(c, c.track.segment);
    const fwd = V{ -fix.sin(yaw), 0, fix.cos(yaw) };
    if (vec.dot(fwd, n) >= 0) return yaw;
    var t = V{ n[2], 0, -n[0] }; // along the wall
    if (vec.dot(t, fwd) < 0) t = .{ -t[0], 0, -t[2] };
    return fix.atan2(t[0], t[2]) +% fix.ONE / 4;
}

/// The last free quarter of the step's motion from `prev`; when even the first is not (a car already against the wall,
/// sliding along it) the whole step, which the caller pushes out of the wall (freds72's slide), or it could never move.
fn rollback(c: *const car.Car, prev: V) V {
    const d = vec.between(prev, c.pos);
    var keep = c.pos;
    for (1..5) |k| {
        const p = vec.add(prev, d, @as(i32, @intCast(k)) << 14);
        if (!free(c, p)) break;
        keep = p;
    }
    return keep;
}

/// A hard crash: the car back on the racing line one segment on, on its heading, stopped.
fn crash(c: *car.Car) bool {
    putBack(c, c.track.segment + 1);
    c.crashes += 1;
    return true;
}

/// The car on the racing line's middle at segment i, on its heading, stopped (a crash, rescue.zig's stuck car).
pub fn putBack(c: *car.Car, i: i32) void {
    const a = seg.corners(c.t, i);
    c.pos = vec.lerp(a.l, a.r, fix.ONE / 2);
    c.old = null;
    if (ground.findFace(c.t, c.pos, null)) |f| {
        c.pos[1] = f.y;
        c.old = f.face;
    }
    c.angle = lineYaw(c, i);
    c.angv = 0;
    c.vel = .{ 0, 0, 0 };
    c.eng = .{};
    c.track = seg.TrackPos.init(c.t, i);
    c.track.update(c.pos);
}
