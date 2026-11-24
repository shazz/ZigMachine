// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// make_pid, make_npc (its control) and angle_to.
//
// RACER: an AI car's driver. Each tick it looks 1 to 4 segments ahead along the racing line for
// the farthest point it can see across the track (a line of sight that stays inside the middle
// 60% of a segment), aims at it, and feeds the angle error to a PID whose output is the steering
// angle. The car's own physics is car.zig (`npc = true`: the angle is set, braking 0.92). Every
// number is PICO-8 16.16 in the original's order of operations (a 16.16 `0.5 * len1 / len2` is
// `(0.5 * len1) / len2`, a unary minus binds before `*`), so the state after N ticks is the Lua's
// bit for bit (race_test.zig). The original's `rpm` is never read back (the NPC passes a literal
// 0.7 each tick), so it is not modelled. No ZigOS import.
// --------------------------------------------------------------------------
const fix = @import("fix.zig");
const seg = @import("seg.zig");
const vec = @import("vec.zig");
const car = @import("car.zig");
const V = vec.V;
const lit = fix.lit;

const DT = fix.ONE / 30; // the `1/30` argument: 2184 as the Lua divides it (PICO-8 truncates)
const NPC_RPM = lit(0.7);
const BRAKE_AT = lit(0.12);
const LOOKAHEAD_MAX = 5;

/// The harness' `--break pid` (key W): the derivative gain 0.5 -> 0.45, which every AI car's steering shows at once.
pub var break_pid: bool = false;

/// make_pid(2, 1, 0.5): fresh (nil) on the first call, so the state is optional, not zero.
pub const Pid = struct {
    prev_err: ?i32 = null,
    i_err: ?i32 = null,

    pub fn step(self: *Pid, cur: i32, tgt: i32, dt: i32) i32 {
        const err = tgt -% cur;
        const prev = self.prev_err orelse err;
        const i_err = fix.mul(fix.ONE -% dt, self.i_err orelse err) +% fix.mul(dt, err);
        self.i_err = i_err;
        const d_err = fix.div(err -% prev, dt);
        self.prev_err = err;
        return fix.mul(2 << 16, err) +% fix.mul(fix.ONE, i_err) +% fix.mul(if (break_pid) lit(0.45) else lit(0.5), d_err);
    }
};

/// v2_cross: the x/z cross product.
fn cross2(a: V, b: V) i32 {
    return fix.mul(a[0], b[2]) -% fix.mul(a[2], b[0]);
}

/// The point the NPC aims at: the first of the segments 1..4 ahead whose line of sight leaves the middle of the track.
pub fn target(c: *const car.Car, lens: *const seg.Lens) V {
    var look: i32 = 1;
    var tgt: V = undefined;
    while (look < LOOKAHEAD_MAX) : (look += 1) {
        const c1 = c.track.next(look);
        const c2 = c.track.next(look + 1);
        const ln = lens.at(c.track.segment + look);
        tgt = vec.lerp(c2.l, c2.r, fix.mid(fix.div(fix.mul(lit(0.5), ln[0]), ln[1]), lit(0.2), lit(0.8)));
        const v = vec.normz(vec.between(c.pos, tgt));
        const t = fix.div(cross2(vec.between(c.pos, c1.l), v), cross2(vec.between(c1.r, c1.l), v));
        if (t > lit(0.8) or t < lit(0.2)) break;
    }
    return tgt;
}

/// angle_to: the heading error to `tgt`, folded to 0.5 .. 1 (the PID's setpoint is 0.75 minus this).
pub fn angleTo(c: *const car.Car, tgt: V) i32 {
    var a = fix.mod(fix.atan2(tgt[0] -% c.pos[0], tgt[2] -% c.pos[2]) -% c.angle, fix.ONE);
    if (a < lit(0.5)) a = fix.ONE -% a;
    return a;
}

/// make_npc's control: choose the steering and the braking, hand them to the car's `steer`.
pub fn control(c: *car.Car, pid: *Pid, lens: *const seg.Lens) void {
    const tgt = target(c, lens);
    const steer_to = pid.step(0, lit(0.75) -% angleTo(c, tgt), DT);
    _ = c.steer(steer_to, NPC_RPM, fix.abs(steer_to) > BRAKE_AT);
}
