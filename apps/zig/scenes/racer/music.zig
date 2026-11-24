// --------------------------------------------------------------------------
// RACER: LOCAL test music (R82; not shipped, the real tunes are M4). Which song suits the moment
// the cart is in, as a pure function of the race's state, and the player that asks for a change
// only when the wish changes. Built only with `-Dracer_music` (racer.zig compiles the calls away
// otherwise, so a normal cart carries no song name); the files are the owner's own, gitignored
// (site/music/racer_*.vgz, fpga/tools/song_pack.py LOCAL_SONGS), never committed.
// A song request is a LOAD that replaces the song playing: so the Time Extend jingles are not
// used (a checkpoint would cut the race tune), and the benchmark laps (b, x) are silent.
// No ZigOS import.
// --------------------------------------------------------------------------
const fsm = @import("fsm.zig");
const rules = @import("rules.zig");

pub const Cue = enum { silent, title, start, loop, win, result };
pub const SONGS = [_][]const u8{ "", "racer_title.vgz", "racer_start.vgz", "racer_loop.vgz", "racer_win.vgz", "racer_result.vgz" };
/// The start tune runs 12.9 s, from the countdown's first tick: the race (30 Hz ticks) hands over to the looping tune after this.
pub const LOOP_AT: u32 = 300;

pub const Ctx = struct {
    bench: bool, // lap v1 / v2: the benchmark, never music
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
    cur: ?Cue = null, // null: nothing asked yet

    /// The cue to request now, or null when what plays is already right.
    pub fn step(self: *Player, c: Ctx) ?Cue {
        const want = if (self.on) cueFor(c) else Cue.silent;
        if (self.cur == want) return null;
        self.cur = want;
        return want;
    }

    pub fn toggle(self: *Player) void {
        self.on = !self.on;
    }
};
