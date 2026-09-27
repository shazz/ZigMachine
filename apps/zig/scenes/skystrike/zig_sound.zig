// --------------------------------------------------------------------------
// ZIG mode's sound: a MOD per situation (zig_music.zig), the synthesized
// effects (tools/skystrike/make_sfx.py) played OVER it on its quietest Paula
// channel (zig_fx.zig, zg.sfxPlay), and the engine's PSG note written to the
// YM, which a MOD leaves idle (zig_psg.zig, zg.ymWrite). skystrike.sndh is
// not loaded in ZIG at all.
//
// The original's effects are its routines 990-998 (sfx.zig), each a string
// of STOS commands: MUSIC OFF to free the YM, then a Maestro digi or the
// PSG's noise. In ZIG each routine marks itself (cue) and names its sample:
//
//   995 the guns        gun burst, looped (as SAMLOOP ON makes the digi)
//   998 a hit / flak    airburst
//   994 a crash         crash
//   993 on the ground   ground explosion (a bomb's or a rocket's)
//   993 on the water    splash (the original's is PSG noise)
//   997 a scrape        hit
//   990 the engine      the original's PSG engine note, unchanged
//
// Inside an effect routine the original's commands are not sent -- the
// sample replaces them, and the music is no longer stopped for it. The
// engine's SAMSTOP stops only a LOOPING sample (the gun burst ends where the
// original's did); a SAMSTOP elsewhere (a pause, the verdicts) stops any.
// Maestro's own commands (SAMPLAY, SAMLOOP) and MUSIC have no ZIG meaning
// outside a routine. The game's own command log (sound.log) is the same in
// both modes.
// --------------------------------------------------------------------------
const sound = @import("sound.zig");
const hooks = @import("zig_hooks.zig");
const fx = @import("zig_fx.zig");
const psg = @import("zig_psg.zig");

/// The order of sound.s's ztab.
pub const Sample = enum(u8) { gun, bang, crash, bomb, splash, hit };
pub const Cue = enum { none, engine, effect };

pub var cue: Cue = .none;

pub fn route(op: sound.Op, arg: u8) void {
    switch (cue) {
        .effect => {},
        .engine => if (op == .samstop) fx.stop(true) else psg.command(op, arg),
        .none => if (op == .samstop) fx.stop(false) else psg.command(op, arg),
    }
}

/// Z was pressed: the other mode's music for the moment (zig_music.zig).
/// Its load ends whatever the mode left was sounding: the SNDH's digi or
/// the MOD with its effect and PSG note.
pub fn switched(zig: bool) void {
    @import("zig_music.zig").switched(zig);
}

/// The effect's sample, in ZIG mode.
pub fn play(s: Sample, loop: bool) void {
    if (!hooks.zig) return;
    fx.play(s, loop);
}
