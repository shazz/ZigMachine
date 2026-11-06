// --------------------------------------------------------------------------
// The source passes (kt_passes.zig) of a channel hard-synced to another: as
// those, but after every sample whose sync source wrapped its phase that
// sample (cyd_cycle: the source's sync bit, set by its first sub-oscillator's
// step), every sub-oscillator's phase, noise and LFSR registers and wavetable
// phase go back to their start. kt_block.zig runs this only when the source
// is not itself synced, so its wraps follow from its own phase alone
// (kt_osc.zig syncBits, before any pass moves it). The general (unspecialised)
// loops: a synced voice is rare, it only has to stay exact and in a block.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const osc = @import("kt_osc.zig");
const wave = @import("kt_wave.zig");
const fm = @import("kt_fm.zig");
const passes = @import("kt_passes.zig");

pub noinline fn sources(rate: u32, chp: *c.Channel, src: []i32, heard: bool, resets: [*]const u8) void {
    var mods: [passes.BLOCK]u32 = undefined;
    const n = src.len;
    const has_fm = chp.flags & c.FM != 0;
    if (has_fm) passes.modulator(rate, &chp.fm, mods[0..n]);
    oscillators(chp, src, &mods, has_fm, heard, resets);
    const e = chp.wave_entry;
    if (chp.flags & c.WAVE != 0) {
        const read = heard and e != null;
        for (&chp.subosc) |*o| voice(&o.wave, e, if (read) src else null, n, &mods, has_fm, resets);
    } else for (resets[0..n]) |r| {
        if (r == 0) continue;
        for (&chp.subosc) |*o| { // the wavetable phase does not move here: only the resets touch it
            o.wave.acc = 0;
            o.wave.direction = 0;
        }
        break;
    }
}

fn oscillators(chp: *c.Channel, src: []i32, mods: *const [passes.BLOCK]u32, has_fm: bool, heard: bool, resets: [*]const u8) void {
    const sounding = heard and chp.flags & c.WAVEFORMS & ~c.WAVE != 0;
    var ch = chp.*;
    for (src, 0..) |*s, t| {
        ch.sync_bit = 0;
        var ovr: i32 = 0;
        if (sounding) {
            const mod: u32 = if (has_fm) fm.modulate(mods[t]) else 0;
            for (&ch.subosc) |*o| {
                if (o.frequency != 0) {
                    const acc = (o.accumulator +% mod) % c.ACC_LENGTH;
                    ovr +%= osc.osc(ch.flags, acc, ch.pw, o.random, o.lfsr_acc) - c.WAVE_AMP / 2;
                }
            }
        }
        s.* = ovr;
        osc.advance(&ch, 0b111);
        if (resets[t] != 0) for (&ch.subosc) |*o| {
            o.accumulator = 0;
            o.random = c.RANDOM_SEED;
            o.reg4 = 1;
            o.reg5 = 1;
            o.reg9 = 1;
            o.lfsr_ctr = 0;
        };
    }
    chp.* = ch;
}

/// One sub-oscillator's wavetable voice: read into src (when heard), stepped, reset after a wrap.
fn voice(wp: *c.WaveState, e: ?*const song.WaveEntry, src: ?[]i32, n: usize, mods: *const [passes.BLOCK]u32, has_fm: bool, resets: [*]const u8) void {
    var w = wp.*;
    for (0..n) |t| {
        if (src) |s| if (w.playing and w.frequency != 0) {
            const ph = if (has_fm) fm.modulateWave(mods[t], e.?, w.acc) else w.acc;
            s[t] +%= wave.sample(&w, e.?, ph);
        };
        wave.cycle(&w, e);
        if (resets[t] != 0) {
            w.acc = 0;
            w.direction = 0;
        }
    }
    wp.* = w;
}
