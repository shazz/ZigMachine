// --------------------------------------------------------------------------
// One channel's block in passes (kt_block.zig): the FM modulator over the
// block, then the oscillators, then each wavetable voice, then the envelope,
// filter and panning, each pass a loop over a few fields. A sample's stages
// only meet through the modulator's output (a block of them, `mods`) and the
// oscillators' and voices' sum (`src`): the modulator, the phases and the
// envelope never read each other, and every stage of sample t reads its
// state as kt_synth.zig's sample loop has it at t. So the same bytes.
// Why: on BARD (wasm2c, rv32 with ~27 free registers) the one-loop form held
// a whole channel live and spilled most of it to the stack every sample (an
// FM-on-wavetable voice: ~700 of its ~2,300 instructions touch the stack).
// Not here: a wavetable that overrides the envelope (added after it), which
// stays on kt_block.zig's one-loop form.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const syn = @import("kt_synth.zig");
const osc = @import("kt_osc.zig");
const wave = @import("kt_wave.zig");
const fm = @import("kt_fm.zig");
const adsr = @import("kt_adsr.zig");
const filter = @import("kt_filter.zig");

pub const BLOCK = 64;

/// The passes apply: no envelope-overriding wavetable.
pub fn fits(ch: *const c.Channel) bool {
    return ch.flags & (c.WAVE | c.WAVE_OVERRIDE_ENV) != (c.WAVE | c.WAVE_OVERRIDE_ENV);
}

/// `n` (<= BLOCK) samples of `chp`, panned and added into dl/dr.
pub noinline fn channel(rate: u32, chp: *c.Channel, n: usize, dl: [*]i32, dr: [*]i32, comptime k: syn.Kind) void {
    var mods: [BLOCK]u32 = undefined; // the modulator's output before sample t's step: what sample t reads
    var src: [BLOCK]i32 = undefined;
    const has_fm = k.fm and chp.flags & c.FM != 0;
    if (has_fm) modulator(rate, &chp.fm, mods[0..n]);
    const gated = chp.flags & c.GATE != 0;
    oscillators(chp, src[0..n], &mods, has_fm, gated, k);
    if (k.wave and chp.flags & c.WAVE != 0) {
        const e = chp.wave_entry;
        const heard = gated and e != null; // fits(): a WAVE channel's wavetable is added before the envelope
        inline for (0..c.SUB_OSCS) |i| if (k.subs >> i & 1 != 0) {
            if (heard) voice(&chp.subosc[i].wave, e.?, src[0..n], &mods, has_fm) else stepOnly(&chp.subosc[i].wave, e, n);
        };
    }
    envelope(rate, chp, src[0..n], dl, dr, gated, k);
}

fn modulator(rate: u32, fp: *c.Fm, mods: []u32) void {
    var f = fp.*;
    for (mods) |*m| {
        m.* = f.current_modulation;
        fm.cycle(rate, &f);
    }
    fp.* = f;
}

/// kt_synth.zig voice + osc.advance: the oscillators' sum (heard samples) and the phases' step.
fn oscillators(chp: *c.Channel, src: []i32, mods: *const [BLOCK]u32, has_fm: bool, gated: bool, comptime k: syn.Kind) void {
    const sounding = k.osc and gated and chp.flags & c.WAVEFORMS & ~c.WAVE != 0;
    var ch = chp.*;
    for (src, 0..) |*s, t| {
        ch.sync_bit = 0;
        var ovr: i32 = 0;
        if (sounding) {
            const mod: u32 = if (has_fm) fm.modulate(mods[t]) else 0;
            inline for (&ch.subosc, 0..) |*o, i| {
                if (k.subs >> i & 1 != 0 and o.frequency != 0) {
                    const acc = (o.accumulator +% mod) % c.ACC_LENGTH;
                    ovr +%= osc.osc(ch.flags, acc, ch.pw, o.random, o.lfsr_acc) - c.WAVE_AMP / 2;
                }
            }
        }
        s.* = ovr;
        osc.advance(&ch, k.subs);
    }
    chp.* = ch;
}

/// A wavetable voice heard over the block: its samples added into src, its phase stepped.
fn voice(wp: *c.WaveState, ep: *const song.WaveEntry, src: []i32, mods: *const [BLOCK]u32, has_fm: bool) void {
    var w = wp.*;
    const e = ep.*;
    for (src, 0..) |*s, t| {
        if (w.playing and w.frequency != 0) {
            const ph = if (has_fm) fm.modulateWave(mods[t], &e, w.acc) else w.acc;
            s.* +%= wave.sample(&w, &e, ph);
        }
        wave.cycle(&w, &e);
    }
    wp.* = w;
}

fn stepOnly(wp: *c.WaveState, e: ?*const song.WaveEntry, n: usize) void {
    var w = wp.*;
    for (0..n) |_| wave.cycle(&w, e);
    wp.* = w;
}

/// The envelope (and filter) on each heard sample, panned into dl/dr; the envelope stepped.
fn envelope(rate: u32, chp: *c.Channel, src: []const i32, dl: [*]i32, dr: [*]i32, gated: bool, comptime k: syn.Kind) void {
    var a = chp.adsr;
    var flags = chp.flags;
    var flt = chp.flt;
    const shape = chp.ym_env_shape;
    const gl = chp.gain_left;
    const gr = chp.gain_right;
    const kind = chp.flttype;
    for (src, 0..) |s, t| {
        if (gated and flags & c.GATE != 0) {
            var o = adsr.output(flags, &a, s);
            if (k.filter and flags & c.FILTER != 0) {
                filter.cycle(&flt, o);
                o = filter.output(&flt, kind);
            }
            dl[t] +%= @divTrunc(o *% gl, c.STEREO_GAIN);
            dr[t] +%= @divTrunc(o *% gr, c.STEREO_GAIN);
        }
        flags = adsr.cycle(rate, flags, shape, &a);
    }
    chp.adsr = a;
    chp.flags = flags;
    chp.flt = flt;
}
