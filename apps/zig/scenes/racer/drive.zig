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
const carview = @import("carview.zig");
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const clip = @import("clip.zig");
const data = @import("data.zig");
const frame = @import("frame.zig");
const pov = @import("pov.zig");
const refrun = @import("refrun.zig");
const skid = @import("skid.zig");
const trk = @import("trk.zig");
const vec = @import("vec.zig");
const xf = @import("xform.zig");

pub const Mode = enum { off, drive, bench };

fn zeroClock() u32 {
    return 0;
}
pub const POV_FRAMES = pov.FRAMES; // 30 ticks
pub const LAP_TICKS = 360;

pub const Snap = carview.Snap;

pub const Drive = struct {
    t: *const trk.Track,
    car: car.Car,
    skid: skid.Skid = .{},
    mode: Mode = .off,
    pov: cam.Pov = .far, // (pov.zig has the camera maths)
    from: cam.Pov = .far,
    pov_frames: u32 = POV_FRAMES,
    held: u8 = 0,
    frames: u32 = 0,
    ticks: u32 = 0,
    slides: u32 = 0,
    prev: Snap,
    cur: Snap,
    now: *const fn () u32 = zeroClock,
    us_sum: u64 = 0,
    us_max: u32 = 0,

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
        self.pov = pov.next(self.pov);
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
        const t0 = self.now();
        self.prev = self.cur;
        self.car.tick(b);
        self.cur = .{ .pos = self.car.pos, .angle = self.car.angle };
        self.ticks += 1;
        self.slides += @intFromBool(self.car.sliding());
        self.skid.emitCar(self.t, &self.car);
        self.skid.update();
        const us = self.now() -% t0;
        self.us_sum += us;
        self.us_max = @max(self.us_max, us);
    }

    /// Where the car is drawn: the previous / current pose midpoint on a tick's frame, the current one after.
    pub fn shown(self: *const Drive) Snap {
        if (self.frames % 2 == 0) return self.cur; // update() has already counted this frame
        return .{ .pos = mid(self.prev.pos, self.cur.pos), .angle = self.prev.angle +% (self.turn() >> 1) };
    }

    fn turn(self: *const Drive) i32 {
        return @as(i16, @truncate(self.cur.angle -% self.prev.angle));
    }

    /// The chase / cockpit camera behind the shown pose.
    pub fn pose(self: *const Drive) cam.Pose {
        const s = self.shown();
        return pov.pose(s.pos, s.angle, pov.offsets(self.pov, self.from, self.pov_frames));
    }

    /// The HUD's name for the mode and POV.
    pub fn label(self: *const Drive) []const u8 {
        const names = [2][3][]const u8{ .{ "DRIVE FAR", "DRIVE NEAR", "DRIVE COCKPIT" }, .{ "BENCH FAR", "BENCH NEAR", "BENCH COCKPIT" } };
        return names[@intFromBool(self.mode == .bench)][@intFromEnum(self.pov)];
    }

    /// The near plane this frame's POV wants (the cockpit is inside the car).
    pub fn near(self: *const Drive) i32 {
        return pov.near(self.pov, self.pov_frames);
    }

    /// Push the car's polygons (not in the cockpit) after collect and before sort.
    pub fn drawCar(self: *const Drive, fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View) void {
        if (self.pov != .cockpit) carview.draw(fr, cache, v, self.shown(), self.car.old, 0);
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

/// The tick's own cost over the lap so far: average and worst microseconds a tick (the host clock; 0 headless).
pub fn perfLine(d: *const Drive, buf: []u8) []const u8 {
    const std = @import("std");
    return std.fmt.bufPrint(buf, "racer,physus,{},{},{}", .{ d.ticks, if (d.ticks == 0) 0 else d.us_sum / d.ticks, d.us_max }) catch "racer,physus,overflow";
}
