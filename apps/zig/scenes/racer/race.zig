// --------------------------------------------------------------------------
// Algorithms of this file follow freds72's PICO-8 racer engine (github.com/freds72/virtua-on,
// vracing_main.p8; MIT, Copyright (c) freds72; licence text at the head of frame.zig): `_update`'s
// order of work.
//
// RACER: the cars of a race and one physics tick of all of them, in the original's order: the
// player (control, contacts with the AI cars, prepare, integrate, update), then each AI car
// (control, prepare, integrate, update). The cars start on the track's grid (slot 0 the player,
// at the back; slots 1..7 the AI cars, two a row ahead). The race's own clock and rules are in
// rules.zig, the grid / countdown / finish states in fsm.zig. Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const car = @import("car.zig");
const carmodel = @import("carmodel.zig");
const contacts = @import("contacts.zig");
const pushes = @import("pushes.zig");
const rescue = @import("rescue.zig");
const arcade = @import("arcade.zig");
const fix = @import("fix.zig");
const npc = @import("npc.zig");
const seg = @import("seg.zig");
const trk = @import("trk.zig");

fn zeroClock() u32 {
    return 0;
}

pub const NCARS = 8; // the player + seven AI cars
pub const WORDS_CAR = 10;
pub const WORDS = NCARS * WORDS_CAR + 3;

pub const Race = struct {
    t: *const trk.Track,
    cars: [NCARS]car.Car,
    pids: [NCARS - 1]npc.Pid = [_]npc.Pid{.{}} ** (NCARS - 1),
    lens: seg.Lens,
    n: usize, // cars in the race (the player + AI cars): all 8, or fewer in the reference's short runs
    contacts: u32 = 0, // the original's hit sound: car-vs-car pushes on the player
    pilot: bool = false, // the player is flown by the AI's controller (a local VR track's benchmark: no recorded stream fits it)
    ppid: npc.Pid = .{},
    parked: u8 = 0, // a test hook: bit k set = AI car k+1 is never steered (the reference's `ram` run)
    ticks: u32 = 0,
    now: *const fn () u32 = zeroClock, // the host's microsecond clock on the board (0 headless): times the AI half of a tick
    ai_us: u64 = 0,
    ai_max: u32 = 0,
    stuck: [NCARS]rescue.Watch = [_]rescue.Watch{.{}} ** NCARS, // ARCADE: each AI car's stuck watch (rescue.zig)
    rescues: u32 = 0, // AI cars put back on the line (off the asphalt or without progress too long)

    pub fn init(t: *const trk.Track, n: usize) error{ NoGrid, TooManySegments }!Race {
        if (n < 1 or n > NCARS or t.grid.len < n) return error.NoGrid;
        var r = Race{ .t = t, .cars = undefined, .lens = try seg.Lens.init(t), .n = n };
        for (r.cars[0..n], t.grid[0..n], 0..) |*c, g, k| {
            c.* = car.Car.init(t, g.pos, g.yaw, g.segment);
            c.npc = k > 0;
            r.stuck[k] = .{ .mark = c.track.u };
        }
        return r;
    }

    /// Every car's physics (R82 32X feel): CLASSIC (freds72's, the default) or ARCADE at the track's world and car scales.
    pub fn setModel(self: *Race, m: arcade.Model) void {
        const world: i32 = @as(i32, self.t.scale.world) << 8;
        const size: i32 = @as(i32, self.t.scale.car) << 8;
        for (self.cars[0..self.n], 0..) |*c, k| {
            c.model = m;
            c.world = if (m == .arcade) world else fix.ONE;
            c.size = if (m == .arcade) size else fix.ONE;
            c.body = if (m == .arcade) bodyOf(carmodel.of(k).foot, size) else .{};
        }
    }

    /// ARCADE: does car-vs-car on every pair at the drawn size (pushes.zig); CLASSIC (or --break push): freds72's player only.
    fn arcadePushes(self: *const Race) bool {
        return self.cars[0].model == .arcade and !pushes.break_push;
    }

    /// One 30 Hz tick of every car; `buttons` are the player's.
    pub fn tick(self: *Race, buttons: u8) void {
        const p = &self.cars[0];
        if (self.pilot) {
            p.npc = true;
            npc.control(p, &self.ppid, &self.lens);
        } else p.control(buttons);
        if (!self.arcadePushes()) self.contacts += contacts.update(p, self.cars[1..self.n]);
        p.prepare();
        p.integrate();
        p.update();
        if (self.pilot and rescue.tick(p, &self.stuck[0])) { // a player flown by the AI's controller is rescued as the AI is
            self.rescues += 1;
            self.ppid = .{};
        }
        const t0 = self.now();
        self.aiTick();
        if (self.arcadePushes()) self.contacts += pushes.update(self.cars[0..self.n]);
        const us = self.now() -% t0;
        self.ai_us += us;
        self.ai_max = @max(self.ai_max, us);
        self.ticks += 1;
    }

    fn aiTick(self: *Race) void {
        for (self.cars[1..self.n], self.pids[0 .. self.n - 1], 0..) |*c, *pid, k| {
            if (self.parked >> @intCast(k) & 1 == 0) npc.control(c, pid, &self.lens);
            c.prepare();
            c.integrate();
            c.update();
            if (rescue.tick(c, &self.stuck[k + 1])) {
                self.rescues += 1;
                pid.* = .{};
            }
        }
    }

    pub fn hits(self: *const Race) u32 {
        var n: u32 = 0;
        for (self.cars[0..self.n]) |*c| n += c.hits;
        return n;
    }

    pub fn brakes(self: *const Race) u32 {
        var n: u32 = 0;
        for (self.cars[0..self.n]) |*c| n += c.brakes;
        return n;
    }

    /// The CRC-32 of the state words: what the fixtures hold per tick and the cart logs (`racer,cars`).
    pub fn crc(self: *const Race) u32 {
        var w: [WORDS]i32 = undefined;
        return std.hash.crc.Crc32IsoHdlc.hash(std.mem.sliceAsBytes(self.words(&w)));
    }

    /// The state the reference dumps, per car (pos, vel, angle, face id, u, v) then the global hits, contacts and AI brakes.
    pub fn words(self: *const Race, w: *[WORDS]i32) []const i32 {
        for (self.cars[0..self.n], 0..) |*c, k| {
            const o = k * WORDS_CAR;
            w[o..][0..3].* = c.pos;
            w[o..][3..6].* = c.vel;
            w[o + 6] = c.angle;
            w[o + 7] = c.faceId();
            w[o + 8] = c.track.u;
            w[o + 9] = c.track.v;
        }
        const o = self.n * WORDS_CAR;
        w[o..][0..3].* = .{ @intCast(self.hits()), @intCast(self.contacts), @intCast(self.brakes()) };
        return w[0 .. o + 3];
    }
};

/// A model's footprint box (Q7, the model's own size) as the physics' body at car scale `size` (Q16).
pub fn bodyOf(f: @import("carfile.zig").Foot, size: i32) pushes.Body {
    const s = @as(i64, size);
    const q = struct {
        fn of(v: i32, k: i64) i32 {
            return @intCast((@as(i64, v) << 9) * k >> 17); // a half, Q7 -> Q16, times the scale
        }
    };
    return .{ .hw = q.of(f.x1 - f.x0, s), .hl = q.of(f.z1 - f.z0, s), .cz = q.of(f.z1 + f.z0, s) };
}
