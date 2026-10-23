// --------------------------------------------------------------------------
// The soundtrack, played by BARD, chosen by the timeline (so a jump plays what
// that moment plays):
//   OLDSCHOOL  "Reset" from the Cuddly Demos, Mad Max (Jochen Hippel), 1988:
//              the plain YM of the era (SNDH archive Mad_Max/Demos/Cuddly_Demos/
//              Reset.sndh, flags ~y)
//   THE GAG    silence from the freeze on: the ST "crashed"
//   NEWSCHOOL  "Breath 2000", Tao (SNDH archive Tao/Breath_2000.sndh, flags
//              ~ady: SID voices and digidrums on timers, no STE DMA); ANIMA is
//              the breath, the tune is the demo's namesake
// SNDH archive tunes are distributed freely for the scene; both are credited
// in the end scroller.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const T = @import("timeline.zig");
const gag = @import("gag.zig");

pub const OLD = "cuddly_reset.sndh";
pub const NEW = "breath_2000.sndh";

const Song = enum(u8) { none, old, new };
var playing: Song = .none;

pub fn reset() void {
    playing = .none;
}

fn wanted(t: u32) Song {
    if (t < T.GAG + gag.FREEZE) return .old;
    if (t < T.TUNNEL) return .none;
    return .new;
}

/// Ask for the tune tick t wants, once, when it changes.
pub fn follow(t: u32) void {
    const w = wanted(t);
    if (w == playing) return;
    playing = w;
    switch (w) {
        .none => zg.stopSong(),
        .old => zg.requestSong(OLD),
        .new => zg.requestSong(NEW),
    }
}
