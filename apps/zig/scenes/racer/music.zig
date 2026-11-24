// --------------------------------------------------------------------------
// RACER: the music (R82 M3 local tunes, M4 placeholders). Which song suits the moment the cart is in,
// as a pure function of the race's state, and the player that asks for a change only when the wished
// FILE changes. Two song tables: SHIPPED, the three placeholder tunes (tools/racer/make_tunes.py, ours,
// committed: kr_*.vgm), and SONGS, the LOCAL test tunes asked for only with `-Dracer_music` (the
// owner's own, gitignored: site/music/racer_*.vgz, fpga/tools/song_pack.py LOCAL_SONGS, never
// committed); with the option the local table wins (audio.zig). A song request is a LOAD that
// replaces the song playing: the Time Extend jingles are sound effects (sfx.zig), and the benchmark
// laps (b, x) are silent unless the bench's audio is switched on (key j).
// No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const fsm = @import("fsm.zig");
const rules = @import("rules.zig");

pub const Cue = enum { silent, title, start, loop, win, result };
pub const SONGS = [_][]const u8{ "", "racer_title.vgz", "racer_start.vgz", "racer_loop.vgz", "racer_win.vgz", "racer_result.vgz" };
/// The shipped placeholders: one race tune for the start and the loop, one for both endings.
pub const SHIPPED = [_][]const u8{ "", "kr_title.vgm", "kr_race.vgm", "kr_race.vgm", "kr_results.vgm", "kr_results.vgm" };
pub const Table = [SONGS.len][]const u8;
/// The start tune runs 12.9 s, from the countdown's first tick: the race (30 Hz ticks) hands over to the looping tune after this.
pub const LOOP_AT: u32 = 300;

pub const Ctx = struct {
    bench: bool, // lap v1 / v2: the benchmark, silent (unless its audio is on: the caller says bench = false then)
    driving: bool, // M2's free drive
    racing: bool, // the race mode (e): the FSM below is live
    state: fsm.State = .grid,
    ticks: u32 = 0, // ticks in that state
    outcome: rules.Result = .none,
};

pub fn cueFor(c: Ctx) Cue {
    if (c.bench or c.driving) return .silent;
    if (!c.racing) return .title; // the attract lap
    return switch (c.state) {
        .grid => .silent,
        .countdown => .start,
        .race => if (c.ticks >= LOOP_AT) .loop else .start,
        .finish, .results => if (c.outcome == .win) .win else .result,
    };
}

pub const Player = struct {
    on: bool = true,
    songs: *const Table = &SONGS,
    cur: ?Cue = null, // null: nothing asked yet

    /// The cue to request now, or null when the file it names already plays.
    pub fn step(self: *Player, c: Ctx) ?Cue {
        const want = if (self.on) cueFor(c) else Cue.silent;
        if (self.cur) |had| if (std.mem.eql(u8, self.name(had), self.name(want))) return null;
        self.cur = want;
        return want;
    }

    pub fn name(self: *const Player, c: Cue) []const u8 {
        return self.songs[@intFromEnum(c)];
    }

    /// Ask again for what the state wants (after the effects device opened: a load may have been lost).
    pub fn forget(self: *Player) void {
        self.cur = null;
    }

    pub fn toggle(self: *Player) void {
        self.on = !self.on;
    }
};
