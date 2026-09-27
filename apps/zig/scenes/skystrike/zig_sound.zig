// --------------------------------------------------------------------------
// ZIG mode's sound effects: synthesized samples (tools/skystrike/make_sfx.py)
// on the machine's Paula sample channels, while the YM keeps the music.
//
// The samples ride in skystrike.sndh (sound.s) and are played by its op 9,
// ZPLAY, through the STE DMA sound chip, which this machine plays on its
// Paula channels (libs/zig/players/ste_dma.zig); op 10, ZSTOP, stops them.
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
// The game's own command log (sound.log) is the same in both modes.
// --------------------------------------------------------------------------
const sound = @import("sound.zig");
const hooks = @import("zig_hooks.zig");

/// The order of sound.s's ztab.
pub const Sample = enum(u8) { gun, bang, crash, bomb, splash, hit };
pub const Cue = enum { none, engine, effect };

pub var cue: Cue = .none;

const LOOP: u8 = 0x80;
const STOP_ANY: u8 = 0;
const STOP_LOOP: u8 = 1;

pub fn route(op: sound.Op, arg: u8) void {
    switch (cue) {
        .effect => {},
        .engine => if (op == .samstop) sound.send(.zstop, STOP_LOOP) else sound.send(op, arg),
        .none => {
            if (op == .samstop) sound.send(.zstop, STOP_ANY);
            sound.send(op, arg);
        },
    }
}

/// Z was pressed: stop what the mode just left may have looping, which the
/// new mode's commands never reach -- ORIGINAL's SAMSTOP does not stop a
/// ZIG gun burst on the DMA chip, and ZIG's engine only stops its own loop,
/// not the Maestro digi. Only once the image is resident: a stop must not
/// be what loads it.
pub fn switched(zig: bool) void {
    if (!sound.resident) return;
    if (zig) sound.send(.samstop, 0) else sound.send(.zstop, STOP_ANY);
}

/// The effect's sample, in ZIG mode.
pub fn play(s: Sample, loop: bool) void {
    if (!hooks.zig) return;
    sound.send(.zplay, @intFromEnum(s) | if (loop) LOOP else 0);
}
