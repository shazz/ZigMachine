// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig):
// make_car (steer, prepare, integrate, update) and make_plyr (control).
//
// RACER: the player's car, one physics tick. The original runs at 30 Hz and so does this port:
// the render frames (60 Hz) interpolate between two ticks (drive.zig). Every number is PICO-8
// 16.16 (fix.zig) and the operations run in the original's order, so the state after N ticks of
// the same buttons is the Lua's bit for bit (car_test.zig pins 600 ticks of two runs).
// The car lies flat on its ground face: the matrix is a yaw only, `right = (c, 0, -d)` and
// `fwd = (d, 0, c)` with c = cos(angle), d = -sin(angle) (PICO-8's sin is upside down).
// A tick is: control(buttons) -> prepare -> integrate -> update, as the reference harness runs it.
// No ZigOS import.
// --------------------------------------------------------------------------
const fix = @import("fix.zig");
const ground = @import("ground.zig");
const seg = @import("seg.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const arcade = @import("arcade.zig");
const arcar = @import("arcadecar.zig");
const V = vec.V;
const lit = fix.lit;

pub const BTN_LEFT: u8 = 1;
pub const BTN_RIGHT: u8 = 2;
pub const BTN_ACCEL: u8 = 16;
pub const BTN_BRAKE: u8 = 32;

const DT = lit(0.5 / 30.0); // the constant 0.5/30 of the Lua, folded: 1092
const GRIP = lit(0.2638); // metres of road per wheel turn
const SLIP = lit(0.22); // front tyres slide above this slip

/// The harness' `--break slip` (key Z): the slip threshold moved, which the slide flag shows at once.
pub var break_slip: bool = false;
const MAX_STEER = lit(0.15);

pub const Car = struct {
    t: *const trk.Track,
    pos: V,
    vel: V = .{ 0, 0, 0 },
    angv: i32 = 0,
    forces: V = .{ 0, 0, 0 },
    torque: i32 = 0,
    angle: i32,
    steer_angle: i32 = 0,
    max_rpm: i32 = lit(0.6),
    total_r: i32 = 0,
    rpm: i32 = 0,
    old: ?u16 = null, // the last ground face under the car (0-based index)
    track: seg.TrackPos,
    front_slide: bool = false,
    rear_slide: bool = false,
    hits: u32 = 0,
    npc: bool = false, // make_npc's steer: the angle is set, not accumulated; braking is harder (0.92)
    brakes: u32 = 0, // NPC steers that braked (a coverage counter for the reference runs)
    // The ARCADE physics (R82 32X feel, arcadecar.zig); a car is CLASSIC unless its race says otherwise.
    model: arcade.Model = .classic,
    eng: arcade.Engine = .{},
    world: i32 = fix.ONE, // the track's world scale: positions move vel * world (arcade only; trk.Mood.world)
    size: i32 = fix.ONE, // the car's size against freds72's: colliders and wheels (arcade only; trk.Mood.car)
    crashes: u32 = 0,

    pub fn init(t: *const trk.Track, pos: V, angle: i32, segment: i32) Car {
        return .{ .t = t, .pos = pos, .angle = angle, .track = seg.TrackPos.init(t, segment) };
    }

    /// right, fwd: the car's axes (a yaw matrix).
    pub fn axes(self: *const Car) struct { right: V, fwd: V } {
        const c = fix.cos(self.angle);
        const d = -fix.sin(self.angle);
        return .{ .right = .{ c, 0, -d }, .fwd = .{ d, 0, c } };
    }

    pub fn tick(self: *Car, buttons: u8) void {
        self.control(buttons);
        self.prepare();
        self.integrate();
        self.update();
    }

    /// make_plyr's control: steering from left / right, rpm up on accelerate, 0 on brake.
    pub fn control(self: *Car, buttons: u8) void {
        if (self.model == .arcade) arcar.pedals(self, buttons);
        var da: i32 = 0;
        if (buttons & BTN_LEFT != 0) da = 1;
        if (buttons & BTN_RIGHT != 0) da = -1;
        if (buttons & BTN_ACCEL != 0) self.rpm +%= lit(0.1);
        if (buttons & BTN_BRAKE != 0) self.rpm = 0;
        self.rpm = self.steer(fix.div(da << 16, 32 << 16), self.rpm, false);
    }

    /// The tyres: slip angle, lateral grip, grip-scaled drive force and its torque. Returns the rpm to keep.
    pub fn steer(self: *Car, dt: i32, rpm_in: i32, braking: bool) i32 {
        self.steer_angle = fix.mid(if (self.npc) dt else self.steer_angle +% dt, -MAX_STEER, MAX_STEER);
        const a = self.angle -% self.steer_angle;
        var sa = vec.dot(.{ fix.cos(a), 0, fix.sin(a) }, self.vel);
        self.front_slide = fix.abs(sa) > (if (break_slip) lit(0.25) else SLIP);
        sa = fix.ONE -% fix.div(fix.min(fix.abs(sa), lit(0.2)), lit(0.8));
        const ax = self.axes();
        self.killLateral(ax.right, ax.fwd);
        var rpm = rpm_in;
        const eff = fix.div(fix.mul(30 << 16, vec.dot(ax.fwd, self.vel)), GRIP);
        const rps = fix.mul(fix.mul(30 << 16, rpm), 2 << 16);
        if (rps > 10 << 16) rpm = fix.mul(rpm, fix.lerp(lit(0.63), fix.ONE, fix.div(eff, rps)));
        const torque = fix.mul(fix.mul(-lit(0.72), sa), self.steer_angle);
        if (self.model == .arcade) return arcar.steered(self, torque, braking);
        if (braking) {
            self.vel = vec.scale(self.vel, if (self.npc) lit(0.92) else lit(0.95));
            self.brakes += @intFromBool(self.npc);
        }
        self.applyForceAndTorque(vec.scale(ax.fwd, rpm), torque);
        self.rear_slide = rps > 10 << 16 and fix.div(eff, rps) < lit(0.6);
        return fix.min(rpm, self.max_rpm);
    }

    fn killLateral(self: *Car, right: V, fwd: V) void {
        var drag = vec.dot(fwd, self.vel);
        drag = fix.lerp(lit(0.003), lit(0.008), fix.div(fix.mul(drag, drag), lit(0.12)));
        const sr = fix.mid(vec.dot(right, self.vel), -drag, drag);
        if (drag > lit(0.001)) self.vel = vec.add(self.vel, right, -sr);
    }

    pub fn applyForceAndTorque(self: *Car, f: V, t: i32) void {
        self.forces = vec.add(self.forces, f, fix.ONE);
        self.torque +%= t;
    }

    pub fn prepare(self: *Car) void {
        if (self.model == .arcade) return arcar.prepare(self);
        self.vel = vec.add(self.vel, self.forces, DT);
        self.angv +%= fix.div(fix.mul(self.torque, lit(0.5)), 30 << 16);
        self.angv = fix.mul(self.angv, lit(0.8));
        self.vel = vec.scale(self.vel, lit(0.97));
    }

    pub fn integrate(self: *Car) void {
        if (self.model == .arcade) return arcar.move(self);
        self.pos = vec.add(self.pos, self.vel, fix.ONE);
        self.angv = fix.mid(self.angv, -fix.ONE, fix.ONE);
        self.angle +%= self.angv;
        self.forces = .{ 0, 0, 0 };
        self.torque = 0;
    }

    /// Ground, walls, track position, wheel turn: the end of a tick.
    pub fn update(self: *Car) void {
        if (self.model == .arcade) return arcar.finish(self);
        self.steer_angle = fix.mul(self.steer_angle, lit(0.8));
        if (ground.findFace(self.t, self.pos, self.old)) |f| {
            self.pos[1] = f.y;
            self.old = f.face;
        }
        self.max_rpm = if (self.old != null and !self.onAsphalt()) lit(0.4) else lit(0.6);
        self.pos[1] = fix.max(self.pos[1], 0);
        self.collide();
        self.track.update(self.pos);
        self.total_r +%= fix.div(vec.dot(self.axes().fwd, self.vel), GRIP);
        self.rpm = fix.mul(self.rpm, lit(0.97));
    }

    fn onAsphalt(self: *const Car) bool {
        return self.t.faces[self.old.?].flags & ground.FLAG_ASPHALT != 0;
    }

    fn collide(self: *Car) void {
        const old = self.old orelse return;
        if (self.t.faces[old].borders == 0) return;
        const h = ground.faceCollide(self.t, old, self.pos, lit(0.25));
        if (!h.hit) return;
        self.hits += 1;
        self.pos = vec.add(self.pos, h.force, fix.ONE);
        const friction = vec.dot(self.vel, h.n);
        if (friction < lit(-0.01)) self.vel = vec.scale(self.vel, fix.ONE +% friction);
    }

    pub fn sliding(self: *const Car) bool {
        return self.front_slide or self.rear_slide;
    }

    /// The reference's dump id: the 1-based face index in 16.16, 0 off the ground.
    pub fn faceId(self: *const Car) i32 {
        return if (self.old) |f| (@as(i32, f) + 1) << 16 else 0;
    }
};
