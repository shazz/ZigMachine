// --------------------------------------------------------------------------
// RACER: driving (M2). The physics runs at 30 Hz, every second `update()` by COUNT (never the
// clock); the 60 Hz frames show the car between two ticks: the tick's frame the midpoint of the
// previous and the current pose, the next frame the current one. Three modes: `off` (M1's lap v0
// camera, no car), `drive` (the keyboard, the arrows and the joystick) and `bench` (lap v1: the
// Lua reference's lap as a button stream, 360 ticks = 720 frames, the car back on the grid at
// every lap). The three POVs lerp over 30 ticks; the cockpit sits in the car with the near plane
// at 0.05 and does not draw the body.
// No ZigOS import: drive_test.zig runs it natively.
// --------------------------------------------------------------------------
const car = @import("car.zig");
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const clip = @import("clip.zig");
const data = @import("data.zig");
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const fx = @import("fx.zig");
const project = @import("project.zig");
const refrun = @import("refrun.zig");
const skid = @import("skid.zig");
const trk = @import("trk.zig");
const types = @import("types.zig");
const vec = @import("vec.zig");
const xf = @import("xform.zig");

pub const Mode = enum { off, drive, bench };
pub const POV_FRAMES = 60; // 30 ticks
pub const LAP_TICKS = 360;

pub const Snap = struct { pos: [3]i32, angle: i32 };

pub const Drive = struct {
    t: *const trk.Track,
    car: car.Car,
    skid: skid.Skid = .{},
    mode: Mode = .off,
    pov: cam.Pov = .far,
    from: cam.Pov = .far,
    pov_frames: u32 = POV_FRAMES,
    held: u8 = 0,
    frames: u32 = 0,
    ticks: u32 = 0,
    slides: u32 = 0,
    prev: Snap,
    cur: Snap,

    pub fn init(t: *const trk.Track) Drive {
        const c = refrun.spawn(t);
        const s = Snap{ .pos = c.pos, .angle = c.angle };
        return .{ .t = t, .car = c, .prev = s, .cur = s };
    }

    /// The car back on the grid, the clocks at zero (a lap's start, or a mode change).
    pub fn reset(self: *Drive) void {
        const keep = .{ self.mode, self.pov, self.held };
        self.* = init(self.t);
        self.mode, self.pov, self.held = keep;
        self.from = self.pov;
        self.pov_frames = POV_FRAMES;
    }

    pub fn setMode(self: *Drive, m: Mode) void {
        self.mode = m;
        self.reset();
    }

    pub fn nextPov(self: *Drive) void {
        self.from = self.pov;
        self.pov = @enumFromInt((@intFromEnum(self.pov) + 1) % 3);
        self.pov_frames = 0;
    }

    /// The host's arrows / joystick: 0 up, 1 down, 2 left, 3 right, 5 fire.
    pub fn press(self: *Drive, dir: u8, down: bool) void {
        const b: u8 = switch (dir) {
            0, 5 => car.BTN_ACCEL,
            1 => car.BTN_BRAKE,
            2 => car.BTN_LEFT,
            3 => car.BTN_RIGHT,
            else => 0,
        };
        if (down) self.held |= b else self.held &= ~b;
    }

    /// One 60 Hz frame of the game: a tick every second frame.
    pub fn update(self: *Drive) void {
        if (self.mode == .off) return;
        if (self.mode == .bench and self.frames % (2 * LAP_TICKS) == 0 and self.frames != 0) self.reset();
        if (self.frames % 2 == 0) self.tick();
        self.frames += 1;
        self.pov_frames = @min(self.pov_frames + 1, POV_FRAMES);
    }

    fn tick(self: *Drive) void {
        const b: u8 = if (self.mode == .bench) data.lap_v1[self.ticks % data.lap_v1.len] else self.held;
        self.prev = self.cur;
        self.car.tick(b);
        self.cur = .{ .pos = self.car.pos, .angle = self.car.angle };
        self.ticks += 1;
        self.slides += @intFromBool(self.car.sliding());
        self.emitSkids();
        self.skid.update();
    }

    fn emitSkids(self: *Drive) void {
        const old = self.car.old orelse return;
        const ax = self.car.axes();
        for (carmodel.WHEELS, 0..) |w, k| {
            if (!(if (k < 2) self.car.front_slide else self.car.rear_slide)) continue;
            const p = vec.add(vec.add(self.car.pos, ax.right, w[0]), ax.fwd, w[2]);
            self.skid.emit(self.t, k, p, old);
        }
    }

    /// Where the car is drawn: the previous / current pose midpoint on a tick's frame, the current one after.
    pub fn shown(self: *const Drive) Snap {
        if (self.frames % 2 == 0) return self.cur; // update() has already counted this frame
        return .{ .pos = mid(self.prev.pos, self.cur.pos), .angle = self.prev.angle +% (self.turn() >> 1) };
    }

    fn turn(self: *const Drive) i32 {
        return @as(i16, @truncate(self.cur.angle -% self.prev.angle));
    }

    fn offsets(self: *const Drive) [3]i32 {
        const to = povParams(self.pov);
        const from = povParams(self.from);
        const k: i32 = @intCast(self.pov_frames * 65536 / POV_FRAMES);
        var o: [3]i32 = undefined;
        for (&o, from, to) |*r, a, b| r.* = a + fx.mulsh16(b - a, k);
        return o;
    }

    /// The chase / cockpit camera behind the shown pose.
    pub fn pose(self: *const Drive) cam.Pose {
        const s = self.shown();
        const yaw: u32 = @as(u32, @as(u16, @truncate(@as(u32, @bitCast(s.angle))))) << 16;
        const o = self.offsets();
        var p = s.pos;
        p[0] -= fx.mulsh16(o[0], fx.sin(yaw));
        p[2] -= fx.mulsh16(o[0], fx.cos(yaw));
        p[1] += o[1];
        return .{ .pos = p, .yaw = yaw, .pitch = @bitCast(o[2]) };
    }

    /// The near plane this frame's POV wants (the cockpit is inside the car).
    pub fn near(self: *const Drive) i32 {
        return if (self.pov == .cockpit and self.pov_frames == POV_FRAMES) clip.NEAR_COCKPIT else clip.NEAR;
    }

    /// Push the car's polygons (not in the cockpit) into the frame's list, after collect and before sort.
    pub fn drawCar(self: *const Drive, fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View) void {
        if (self.pov == .cockpit) return;
        const s = self.shown();
        const mv = modelView(v, s);
        const floor = if (self.car.old) |o| fr.faceKey(o) orelse 0 else 0;
        cache.next();
        for (&carmodel.faces) |*f| {
            if (types.facing(f, &mv) <= f.cp) continue;
            _ = project.build(fr, cache, &carmodel.verts, &mv, f, .{ .floor = floor });
        }
    }

    /// One line a host can compare with the reference: raw 16.16 state after `ticks` ticks.
    pub fn stateLine(self: *const Drive, buf: []u8) []const u8 {
        const std = @import("std");
        const c = &self.car;
        return std.fmt.bufPrint(buf, "racer,phys,{},{},{},{},{},{},{},{}", .{
            self.ticks, c.pos[0], c.pos[1], c.pos[2], c.angle, c.track.u, c.hits, self.slides,
        }) catch "racer,phys,overflow";
    }
};

fn mid(a: [3]i32, b: [3]i32) [3]i32 {
    return .{ a[0] + ((b[0] - a[0]) >> 1), a[1] + ((b[1] - a[1]) >> 1), a[2] + ((b[2] - a[2]) >> 1) };
}

/// back (Q16), height (Q16), pitch (turns u32 as i32) of a POV.
fn povParams(p: cam.Pov) [3]i32 {
    const k = @intFromEnum(p);
    return .{ cam.BACK[k], cam.HEIGHT[k], @bitCast(cam.PITCH[k]) };
}

/// The camera's view recomposed for the car's own space: rows right-multiplied by the car's yaw,
/// the translation carrying the car's position, the eye in the car's Q7 space (the back-face test).
pub fn modelView(v: *const cam.View, s: Snap) cam.View {
    const c = fix.cos(s.angle);
    const d = -fix.sin(s.angle);
    var m = v.*;
    for (0..3) |i| {
        const r = v.r[i];
        m.r[i] = .{ fx.mulsh16(r[0], c) + fx.mulsh16(r[2], -d), r[1], fx.mulsh16(r[0], d) + fx.mulsh16(r[2], c) };
        m.t[i] = v.t[i] + ((fx.mulsh16(r[0], s.pos[0]) + fx.mulsh16(r[1], s.pos[1]) + fx.mulsh16(r[2], s.pos[2])) >> 9);
    }
    const dx = v.eye7[0] - (s.pos[0] >> 9);
    const dz = v.eye7[2] - (s.pos[2] >> 9);
    m.eye7 = .{ fx.mulsh16(c, dx) + fx.mulsh16(-d, dz), v.eye7[1] - (s.pos[1] >> 9), fx.mulsh16(d, dx) + fx.mulsh16(c, dz) };
    if (fx.use_f32) cam.floatView(&m);
    return m;
}
