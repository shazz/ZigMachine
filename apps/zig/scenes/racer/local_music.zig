// --------------------------------------------------------------------------
// RACER: the LOCAL test music's glue (music.zig has the logic): ask the host for the tune that suits
// the cart's state. `enabled` is the build option `-Dracer_music`; without it every function here is
// empty at comptime, so the cart holds no song name and behaves as before. Like keys.zig
// it works on any Demo (a struct with the fields below). Key `z` toggles the music off / on.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const opts = @import("cart_opts");
const music = @import("music.zig");

pub const enabled: bool = opts.racer_music;
/// The Demo's field: nothing at all (zero bytes) without the option.
pub const State = if (enabled) music.Player else struct {};

fn ctx(self: anytype) music.Ctx {
    const g = &self.game;
    return .{
        .bench = g.mode == .bench or self.drive.mode == .bench,
        .driving = self.drive.mode != .off,
        .racing = g.mode != .off,
        .state = g.s.fsm.state,
        .ticks = g.s.fsm.ticks,
        .outcome = g.s.outcome,
    };
}

/// Once a frame: a request only when the wished tune changes.
pub fn step(self: anytype) void {
    if (enabled) {
        const cue = self.music.step(ctx(self)) orelse return;
        if (cue == .silent) zg.stopSong() else zg.requestSong(music.SONGS[@intFromEnum(cue)]);
    }
}

/// Any key the cart's own switch does not take: `z` toggles the music (a prong in that switch would change the cart's code even with the option off).
pub fn key(self: anytype, cp: u32) void {
    if (enabled and cp == 'z') self.music.toggle();
}
