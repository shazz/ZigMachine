// --------------------------------------------------------------------------
// One channel's block in passes (kt_block.zig): the FM modulator over the
// block, then the oscillators, then each wavetable voice, then the envelope,
// filter and panning, each pass a loop over a few fields. A sample's stages
// only meet through the modulator's output (a block of them, `mods`) and the
// oscillators' and voices' sum (`src`): the modulator, the phases and the
// envelope never read each other, and every stage of sample t reads its
// state as kt_synth.zig's sample loop has it at t. So the same bytes. The
// envelope pass is kt_envpass.zig, run once every channel's sums are known.
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

pub const BLOCK = @import("kt_block.zig").BLOCK;

/// The passes apply: no envelope-overriding wavetable.
pub fn fits(ch: *const c.Channel) bool {
    return ch.flags & (c.WAVE | c.WAVE_OVERRIDE_ENV) != (c.WAVE | c.WAVE_OVERRIDE_ENV);
}

/// The block's first passes for `chp`: its source sum (oscillators and wavetable voices, before the
/// envelope) into src where `heard` (gated, or the ring source of a gated channel), every phase and
/// the modulator stepped. kt_envpass.zig does the rest.
pub noinline fn sources(rate: u32, chp: *c.Channel, src: []i32, heard: bool, comptime k: syn.Kind) void {
    var mods: [BLOCK]u32 = undefined; // the modulator's output before sample t's step: what sample t reads
    const n = src.len;
    const has_fm = chp.flags & c.FM != 0;
    if (has_fm) modulator(rate, &chp.fm, mods[0..n]);
    oscillators(chp, src, &mods, has_fm, heard, k);
    if (chp.flags & c.WAVE != 0) {
        const e = chp.wave_entry;
        const read = heard and e != null; // fits(): a WAVE channel's wavetable is added before the envelope
        inline for (0..c.SUB_OSCS) |i| if (k.subs >> i & 1 != 0) {
            if (read) voiceAny(&chp.subosc[i].wave, e.?, src, &mods, has_fm) else stepOnly(&chp.subosc[i].wave, e, n);
        };
    }
}

/// The modulator over the block, built for its wave entry's shape (kt_wave.zig Shape).
pub fn modulator(rate: u32, fp: *c.Fm, mods: []u32) void {
    const e = fp.wave_entry orelse return modulatorS(rate, fp, mods, null);
    switch (wave.shapeCode(e)) {
        inline else => |v| modulatorS(rate, fp, mods, wave.shape(v)),
    }
}

fn modulatorS(rate: u32, fp: *c.Fm, mods: []u32, comptime s: ?wave.Shape) void {
    var f = fp.*;
    for (mods) |*m| {
        m.* = f.current_modulation;
        fm.cycleS(rate, &f, s);
    }
    fp.* = f;
}

/// kt_synth.zig voice + osc.advance: the oscillators' sum (heard samples) and the phases' step.
fn oscillators(chp: *c.Channel, src: []i32, mods: *const [BLOCK]u32, has_fm: bool, heard: bool, comptime k: syn.Kind) void {
    const sounding = k.osc and heard and chp.flags & c.WAVEFORMS & ~c.WAVE != 0;
    if (!sounding and chp.flags & c.LFSR == 0) { // only the phases move (a wavetable voice)
        @memset(src, 0);
        osc.advanceN(chp, src.len, k.subs);
        return;
    }
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

/// A wavetable voice heard over the block: its samples added into src, its phase stepped; built for
/// its entry's shape and whether FM moves its phase.
fn voiceAny(wp: *c.WaveState, ep: *const song.WaveEntry, src: []i32, mods: *const [BLOCK]u32, has_fm: bool) void {
    switch (@as(u5, wave.shapeCode(ep)) | @as(u5, @intFromBool(has_fm)) << 4) {
        inline else => |v| voice(wp, ep, src, mods, wave.shape(v & 15), v & 16 != 0),
    }
}

fn voice(wp: *c.WaveState, ep: *const song.WaveEntry, src: []i32, mods: *const [BLOCK]u32, comptime s: wave.Shape, comptime has_fm: bool) void {
    var w = wp.*;
    const e = ep.*;
    for (src, 0..) |*o, t| {
        if (w.playing and w.frequency != 0) {
            const ph = if (has_fm) fm.modulateWave(mods[t], &e, w.acc) else w.acc;
            o.* +%= wave.sampleS(&w, &e, ph, s);
        }
        wave.cycleS(&w, &e, s);
    }
    wp.* = w;
}

fn stepOnly(wp: *c.WaveState, e: ?*const song.WaveEntry, n: usize) void {
    var w = wp.*;
    for (0..n) |_| wave.cycle(&w, e);
    wp.* = w;
}
