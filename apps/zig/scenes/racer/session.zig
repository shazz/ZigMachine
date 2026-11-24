// --------------------------------------------------------------------------
// RACER: one race, tick by tick: the cars (race.zig), the player's rules (rules.zig), the state
// machine (fsm.zig), who finished when (standings.zig) and the records (records.zig, RAM only).
// `tick` is one 30 Hz step in whatever state the race is in: the grid and the results do nothing,
// the countdown holds every car for 90 ticks, the race runs the cars and the rules, the finish
// state lets the AI cars run on (until all have finished, or 20 s) once the player has won or the
// clock ran out. A car has finished when its track u passes the player's finish u. The watchdogs
// count each car's longest run off the asphalt and against a wall, for the race harness.
// No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const fsm = @import("fsm.zig");
const ground = @import("ground.zig");
const race = @import("race.zig");
const records = @import("records.zig");
const rules = @import("rules.zig");
const standings = @import("standings.zig");
const trk = @import("trk.zig");

pub const COUNTDOWN_TICKS = 90;
pub const FINISH_CAP = 20 * rules.HZ;
const N = race.NCARS;

/// Per car, the longest run of consecutive ticks off the asphalt and in contact with a wall.
pub const Watch = struct {
    off_run: [N]u32 = [_]u32{0} ** N,
    off_max: [N]u32 = [_]u32{0} ** N,
    wall_run: [N]u32 = [_]u32{0} ** N,
    wall_max: [N]u32 = [_]u32{0} ** N,
    last_hits: [N]u32 = [_]u32{0} ** N,

    fn note(self: *Watch, k: usize, c: *const @import("car.zig").Car) void {
        const off = if (c.old) |f| c.t.faces[f].flags & ground.FLAG_ASPHALT == 0 else true;
        self.off_run[k] = if (off) self.off_run[k] + 1 else 0;
        self.off_max[k] = @max(self.off_max[k], self.off_run[k]);
        self.wall_run[k] = if (c.hits != self.last_hits[k]) self.wall_run[k] + 1 else 0;
        self.last_hits[k] = c.hits;
        self.wall_max[k] = @max(self.wall_max[k], self.wall_run[k]);
    }
};

pub const Session = struct {
    t: *const trk.Track,
    race: race.Race,
    rules: rules.Rules,
    fsm: fsm.Fsm = .{},
    records: records.Records = .{},
    finish: [N]u32 = [_]u32{0} ** N, // the race tick each car crossed the finish (0 = not yet)
    outcome: rules.Result = .none, // win or timeout once the player is done
    lap_record: bool = false, // the last lap / the race beat the session's best
    race_record: bool = false,
    watch: Watch = .{},

    pub fn init(t: *const trk.Track) !Session {
        return .{ .t = t, .race = try race.Race.init(t, N), .rules = try rules.Rules.init(t) };
    }

    /// Back to the grid with fresh cars, clock and finish times; the records stay.
    pub fn reset(self: *Session) void {
        const keep = self.records;
        self.* = init(self.t) catch unreachable; // WHY: the same track parsed once at init: it cannot start failing now
        self.records = keep;
    }

    pub fn start(self: *Session) fsm.Error!void {
        try self.fsm.fire(.start);
    }

    /// The abort / again key: refused on the grid (nothing to leave).
    pub fn restart(self: *Session) fsm.Error!void {
        if (self.fsm.next(.restart) == null) return error.IllegalTransition;
        self.reset();
    }

    pub fn tick(self: *Session, buttons: u8) void {
        switch (self.fsm.state) {
            .grid, .results => {},
            .countdown => {
                self.fsm.tick();
                if (self.fsm.ticks >= COUNTDOWN_TICKS) self.fsm.fire(.go) catch unreachable; // WHY: go is legal in countdown
            },
            .race => self.runRace(buttons),
            .finish => self.runFinish(),
        }
    }

    fn runRace(self: *Session, buttons: u8) void {
        self.race.tick(buttons);
        self.fsm.tick();
        self.noteFinishers();
        switch (self.rules.tick(self.race.cars[0].track.u)) {
            .lap => self.lap_record = self.records.offerLap(self.rules.laps[self.rules.nlaps - 1]),
            .win => {
                self.lap_record = self.records.offerLap(self.rules.laps[self.rules.nlaps - 1]);
                self.race_record = self.records.offerRace(self.rules.total);
                self.end(.win);
            },
            .timeout => self.end(.timeout),
            else => {},
        }
    }

    fn end(self: *Session, how: rules.Result) void {
        self.outcome = how;
        self.fsm.fire(.finish) catch unreachable; // WHY: finish is legal in race
    }

    fn runFinish(self: *Session) void {
        self.race.tick(0);
        self.fsm.tick();
        self.noteFinishers();
        if (self.allFinished() or self.fsm.ticks >= FINISH_CAP) self.fsm.fire(.done) catch unreachable; // WHY: done is legal in finish
    }

    fn noteFinishers(self: *Session) void {
        const limit = self.rules.finishU();
        for (self.race.cars[0..self.race.n], 0..) |*c, k| {
            if (self.finish[k] == 0) self.watch.note(k, c); // a car that has finished is free to coast
            if (self.finish[k] == 0 and c.track.u > limit) self.finish[k] = self.race.ticks;
        }
    }

    pub fn allFinished(self: *const Session) bool {
        for (self.finish[0..self.race.n]) |f| if (f == 0) return false;
        return true;
    }

    /// The tracks' u of every car (the standings' input).
    pub fn us(self: *const Session) [N]i32 {
        var u: [N]i32 = undefined;
        for (self.race.cars[0..self.race.n], 0..) |*c, k| u[k] = c.track.u;
        return u;
    }

    pub fn playerPlace(self: *const Session) u32 {
        const u = self.us();
        return standings.place(0, &u, &self.finish, self.race.n);
    }

    /// A CRC-32 of the final order and every car's finish tick: the race harness' pin.
    pub fn resultHash(self: *const Session) u32 {
        const u = self.us();
        var ord: [N]u8 = undefined;
        const o = standings.order(&u, &self.finish, self.race.n, &ord);
        var h = std.hash.crc.Crc32IsoHdlc.init();
        h.update(o);
        h.update(std.mem.sliceAsBytes(self.finish[0..self.race.n]));
        return h.final();
    }
};
