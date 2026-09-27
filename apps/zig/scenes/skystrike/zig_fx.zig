// --------------------------------------------------------------------------
// ZIG mode's effect samples, played over the MOD with zg.sfxPlay: the audio
// thread lends each one the song's quietest Paula channel
// (libs/zig/players/sfx_voice.zig) and gives it back at the sample's end, or
// on a stop for the looped gun burst.
//
// The samples are tools/skystrike/make_sfx.py's, signed 8-bit at the STE DMA
// rates sound_zig.s gave them (its ztab's mode bytes: $81 = 12517 Hz, $80 =
// 6258 Hz). The cart holds them (@embedFile), so the pointer the host copies
// from at the end of the frame is always good.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const Sample = @import("zig_sound.zig").Sample;

const DIR = "../../assets/screens/skystrike/sfx/";
const HI: u32 = 12517;
const LO: u32 = 6258;

const Bank = struct { pcm: []const u8, rate: u32 };

const BANK = std.EnumArray(Sample, Bank).init(.{
    .gun = .{ .pcm = @embedFile(DIR ++ "gun.raw"), .rate = HI },
    .bang = .{ .pcm = @embedFile(DIR ++ "bang.raw"), .rate = HI },
    .crash = .{ .pcm = @embedFile(DIR ++ "crash.raw"), .rate = LO },
    .bomb = .{ .pcm = @embedFile(DIR ++ "bomb.raw"), .rate = LO },
    .splash = .{ .pcm = @embedFile(DIR ++ "splash.raw"), .rate = HI },
    .hit = .{ .pcm = @embedFile(DIR ++ "hit.raw"), .rate = HI },
});

/// Effects zg.sfxPlay / sfxStop refused (the queue was full): checked 0.
pub var refused: u32 = 0;

pub fn play(s: Sample, loop: bool) void {
    const b = BANK.get(s);
    if (!zg.sfxPlay(b.pcm, b.rate, loop)) refused +%= 1;
}

/// SAMSTOP: the effect (only a looped one when `loop_only`).
pub fn stop(loop_only: bool) void {
    if (!zg.sfxStop(loop_only)) refused +%= 1;
}

/// The harness's view: sample s's bytes and rate.
pub fn pcm(s: Sample) []const u8 {
    return BANK.get(s).pcm;
}
pub fn rate(s: Sample) u32 {
    return BANK.get(s).rate;
}
