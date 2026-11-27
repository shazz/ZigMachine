// --------------------------------------------------------------------------
// RACER: the race as the cart plays it (M3). The physics runs at 30 Hz: a tick every second 60 Hz frame BY COUNT, plus
// the ticks the real clock owes under 60 fps (pace.zig); between two ticks every car shows at its last two poses' midpoint. Modes: `off`; `race` (the player's keys; the grid waits for fire
// or S); `bench` (lap v2: the reference benchmark; the recorded autopilot drives, the race starts by
// itself after 1 s on the grid, a round is 2,880 frames, then the grid again). Key A / `auto`
// drives the player from the recorded stream in `race` mode too (the headless race). `warp` runs 16
// ticks a frame (the headless harness' 3 laps in a few hundred frames). A race runs rules.race_laps (the options
// screen), the bench the reference's LAPS. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const cam = @import("cam.zig");
const car = @import("car.zig");
const carmodel = @import("carmodel.zig");
const carview = @import("carview.zig");
const data = @import("data.zig");
const fsm = @import("fsm.zig");
const frame = @import("frame.zig");
const pov = @import("pov.zig");
const race = @import("race.zig");
const session = @import("session.zig");
const smoke = @import("smoke.zig");
const trk = @import("trk.zig");
const xf = @import("xform.zig");
const arcade = @import("arcade.zig");
const pace = @import("pace.zig");

pub const Mode = enum { off, race, bench };
pub const Snap = carview.Snap;
pub const ROUND_FRAMES = 2880; // lap v2: 1 s grid, 3 s countdown, then 1,320 ticks of racing
pub const GRID_FRAMES = 60;
pub const WARP = 16;
const N = race.NCARS;

fn zeroClock() u32 {
    return 0;
}

pub const Game = struct {
    t: *const trk.Track,
    s: session.Session,
    mode: Mode = .off,
    pov: cam.Pov = .far,
    from: cam.Pov = .far,
    pov_frames: u32 = pov.FRAMES,
    held: u8 = 0,
    auto: bool = false, // the player follows the recorded stream
    pilot: bool = false, // ... or, on a local VR track (no stream), the AI's controller flies the player
    apilot: bool = false, // key L: the AI's controller flies the player in the PHYSICS option's model (the arcade harness' driver)
    warp: bool = false,
    frames: u32 = 0,
    prev: [N]Snap = undefined,
    cur: [N]Snap = undefined,
    smoke: smoke.Smoke = .{},
    now: *const fn () u32 = zeroClock,
    pace: pace.Pace = .{},
    logged: fsm.State = .grid,

    pub fn init(t: *const trk.Track, now: *const fn () u32) !Game {
        var g = Game{ .t = t, .s = try session.Session.init(t), .now = now };
        g.s.race.now = now;
        g.snap();
        g.prev = g.cur;
        return g;
    }

    fn snap(self: *Game) void {
        for (self.s.race.cars[0..N], &self.cur) |*c, *o| o.* = .{ .pos = c.pos, .angle = c.angle, .size = c.size };
    }

    /// A fresh race on the grid (the records and the camera stay).
    pub fn reset(self: *Game) void {
        self.s.reset();
        self.s.race.now = self.now;
        self.smoke = .{};
        self.frames = 0;
        self.snap();
        self.prev = self.cur;
    }

    pub fn setMode(self: *Game, m: Mode) void {
        self.mode = m;
        self.warp = false;
        self.auto = m == .bench;
        self.s.laps = if (m == .race) @import("rules.zig").race_laps else @import("rules.zig").LAPS;
        self.reset();
        self.logged = .grid; // a new mode starts a new log (a reset inside a mode logs the state change)
    }

    /// Out of a race into the front end (front.zig): no race runs, the session (its FSM's state) stays.
    pub fn toFront(self: *Game) void {
        self.mode = .off;
        self.warp = false;
        self.auto = false;
    }

    pub fn nextPov(self: *Game) void {
        self.from = self.pov;
        self.pov = pov.next(self.pov);
        self.pov_frames = 0;
    }

    /// The host's arrows / joystick: fire or up on the grid starts the countdown.
    pub fn press(self: *Game, dir: u8, down: bool) void {
        const b: u8 = switch (dir) {
            0, 5 => car.BTN_ACCEL,
            1 => car.BTN_BRAKE,
            2 => car.BTN_LEFT,
            3 => car.BTN_RIGHT,
            else => 0,
        };
        if (down) self.held |= b else self.held &= ~b;
        if (down and (dir == 0 or dir == 5)) self.go();
    }

    /// The start key: grid -> countdown. Refused anywhere else, and in the benchmark (which starts itself: input must not move its CRCs).
    pub fn go(self: *Game) void {
        if (self.mode != .bench) self.s.start() catch {}; // WHY: only the grid may start; in any other state the key does nothing
    }

    /// Keys `a` and `w`: the recorded driver and warp, both fixed in the benchmark.
    pub fn toggleAuto(self: *Game) void {
        if (self.mode != .bench) self.auto = !self.auto;
    }

    pub fn toggleWarp(self: *Game) void {
        if (self.mode != .bench) self.warp = !self.warp;
    }

    /// The abort / again key (Enter, R): a fresh grid. Refused on the grid itself.
    pub fn again(self: *Game) void {
        self.s.restart() catch return; // WHY: nothing to abort on the grid
        self.reset();
    }

    fn buttons(self: *const Game) u8 {
        if (!self.auto) return self.held;
        const k = self.s.race.ticks;
        return if (k < data.race_v2.len) data.race_v2[k] else 0;
    }

    /// One 60 Hz frame: a tick (16 when warping) every second frame.
    pub fn update(self: *Game) void {
        if (self.mode == .off) return;
        if (self.mode == .bench) self.benchClock();
        const counted: u32 = if (self.frames % 2 != 0) 0 else if (self.warp) WARP else 1;
        for (0..counted + self.pace.step(!self.warp, self.now(), counted)) |_| self.tick(); // a harness' clock reads 0: pins hold
        self.frames += 1;
        self.pov_frames = @min(self.pov_frames + 1, pov.FRAMES);
    }

    fn benchClock(self: *Game) void {
        const f = self.frames % ROUND_FRAMES;
        if (f == 0 and self.frames != 0) self.reset();
        if (f == GRID_FRAMES) self.s.start() catch {}; // WHY: as go()
    }

    /// A tick's physics (R82 32X feel): the reference's drivers (bench, `a`) CLASSIC, so their pins hold; else the option.
    pub fn physics(self: *const Game) arcade.Model {
        return if (self.mode == .race and !self.auto) arcade.model else .classic;
    }

    fn tick(self: *Game) void {
        self.prev = self.cur;
        self.s.race.setModel(self.physics());
        self.s.race.pilot = (self.pilot and self.auto) or (self.apilot and !self.auto);
        self.s.tick(self.buttons());
        self.snap();
        const st = self.s.fsm.state;
        if (st == .race or st == .finish) {
            self.smoke.emitCar(&self.s.race.cars[0], carmodel.of(0).foot);
            self.smoke.update();
        }
    }

    pub fn shown(self: *const Game, k: usize) Snap {
        return if (self.frames % 2 == 0) self.cur[k] else carview.midway(self.prev[k], self.cur[k]);
    }

    /// The race camera: the POV's offsets (zoned under a roof), grown with an ARCADE car's size (FEEL.md).
    pub fn pose(self: *const Game) cam.Pose {
        const s = self.shown(0);
        const o = pov.zoned(self.t, self.pov, pov.offsets(self.pov, self.from, self.pov_frames), self.s.race.cars[0].track.u);
        return pov.pose(s.pos, s.angle, pov.sized(o, s.size));
    }

    pub fn near(self: *const Game) i32 {
        return pov.near(self.pov, self.pov_frames);
    }

    /// Push every car in range (the player's body not in the cockpit) after collect and before sort.
    pub fn drawCars(self: *const Game, fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View, tiles: u32) void {
        var snaps: [N]carview.Snap = undefined;
        var under: [N]?u16 = undefined;
        for (&snaps, &under, self.s.race.cars[0..N], 0..) |*s, *g, *c, k| {
            s.* = self.shown(k);
            g.* = c.old;
        }
        carview.drawRace(fr, cache, v, self.t, &snaps, &under, self.pov == .cockpit, tiles);
    }
};
