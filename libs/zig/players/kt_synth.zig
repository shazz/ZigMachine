// --------------------------------------------------------------------------
// One sample of cyd (cyd.c cyd_output + cyd_cycle, STEREOOUTPUT): every song
// channel's oscillators, wavetable, ring modulation, envelope and filter,
// panned onto the dry mix or its FX bus, the buses' effects, then every
// channel's envelope, wavetable, FM and sync stepped. Only the song's
// channels are run (upstream's are exactly those: the cart reserves them),
// and a channel nobody hears (gate off, no gated channel ring-modulating from
// it) skips its oscillator and wavetable reads but still advances (the cart's
// cyd.c.sed): its output was never used, so the result is unchanged.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const osc = @import("kt_osc.zig");
const wave = @import("kt_wave.zig");
const fm = @import("kt_fm.zig");
const adsr = @import("kt_adsr.zig");
const filter = @import("kt_filter.zig");
const fx = @import("kt_fx.zig");

pub const Synth = struct {
    rate: u32 = 22050,
    n: usize = 0, // the song's channels
    chn: [song.MAX_CH]c.Channel = undefined,
    bus: [song.MAX_FX]fx.Bus = undefined,
    bus_used: u8 = 0, // buses with an effect on: the others pass their input through
};

/// The oscillators' sum of channel `ch` (cyd_output_channel) plus its
/// envelope-following wavetable voices.
inline fn voice(ch: *c.Channel) i32 {
    var ovr: i32 = 0;
    ch.sync_bit = 0;
    const mod: u32 = if (ch.flags & c.FM != 0) fm.modulate(&ch.fm) else 0;
    for (&ch.subosc) |*o| {
        if (o.frequency != 0) {
            const acc = (o.accumulator +% mod) % c.ACC_LENGTH;
            ovr +%= osc.osc(ch.flags, acc, ch.pw, o.random, o.lfsr_acc) - c.WAVE_AMP / 2;
        }
    }
    return ovr;
}

/// The wavetable voices of `ch` (cyd_output's two loops share this).
inline fn wavetable(ch: *const c.Channel, e: *const song.WaveEntry) i32 {
    var sum: i32 = 0;
    for (&ch.subosc) |*o| {
        if (!o.wave.playing or o.wave.frequency == 0) continue;
        const acc = if (ch.flags & c.FM != 0) fm.modulateWave(&ch.fm, e, o.wave.acc) else o.wave.acc;
        sum +%= wave.sample(&o.wave, e, acc);
    }
    return sum;
}

/// Which channels a gated channel ring-modulates from, this sample.
inline fn ringed(sy: *const Synth) u32 {
    var m: u32 = 0;
    for (sy.chn[0..sy.n]) |*ch| {
        if (ch.flags & (c.GATE | c.RING_MODULATION) == (c.GATE | c.RING_MODULATION)) m |= @as(u32, 1) << @intCast(ch.ring_mod & 31);
    }
    return m;
}

/// cyd_output: this sample's stereo mix (before the /4 and clamp).
pub fn output(sy: *Synth, left: *i32, right: *i32) void {
    var s: [song.MAX_CH]i32 = undefined;
    const ring = ringed(sy);
    for (sy.chn[0..sy.n], 0..) |*ch, i| {
        if (ch.flags & c.GATE == 0 and ring >> @intCast(i) & 1 == 0) {
            ch.sync_bit = 0;
            osc.advance(ch); // unheard: the phase, sync bit and noise still move
            s[i] = 0;
            continue;
        }
        s[i] = voice(ch);
        osc.advance(ch);
        if (ch.flags & (c.WAVE | c.WAVE_OVERRIDE_ENV) == c.WAVE) if (ch.wave_entry) |e| {
            s[i] +%= wavetable(ch, e);
        };
    }
    var l: i32 = 0;
    var r: i32 = 0;
    for (sy.chn[0..sy.n], 0..) |*ch, i| {
        if (ch.flags & c.GATE == 0) continue;
        var input = s[i];
        if (ch.flags & c.RING_MODULATION != 0) {
            const m: i32 = if (ch.ring_mod < sy.n) s[ch.ring_mod] else 0;
            input = @divTrunc(input *% (m +% c.WAVE_AMP / 2), c.WAVE_AMP);
        }
        var o = adsr.output(ch.flags, &ch.adsr, input);
        if (ch.flags & (c.WAVE | c.WAVE_OVERRIDE_ENV) == (c.WAVE | c.WAVE_OVERRIDE_ENV)) if (ch.wave_entry) |e| {
            o +%= wavetableOverride(ch, e);
        };
        if (ch.flags & c.FILTER != 0) {
            filter.cycle(&ch.flt, o);
            o = filter.output(&ch.flt, ch.flttype);
        }
        const ol = @divTrunc(o *% ch.gain_left, c.STEREO_GAIN);
        const or_ = @divTrunc(o *% ch.gain_right, c.STEREO_GAIN);
        if (ch.flags & c.FX != 0) {
            const b = &sy.bus[ch.fx_bus];
            b.in_l +%= ol;
            b.in_r +%= or_;
        } else {
            l +%= ol;
            r +%= or_;
        }
    }
    for (&sy.bus, 0..) |*b, i| {
        var bl = b.in_l;
        var br = b.in_r;
        b.in_l = 0;
        b.in_r = 0;
        if (sy.bus_used >> @intCast(i) & 1 != 0) fx.output(b, &bl, &br);
        l +%= bl;
        r +%= br;
    }
    left.* = l;
    right.* = r;
}

/// A wavetable that overrides the envelope: its voices at the channel volume only.
inline fn wavetableOverride(ch: *const c.Channel, e: *const song.WaveEntry) i32 {
    var sum: i32 = 0;
    for (&ch.subosc) |*o| {
        if (!o.wave.playing or o.wave.frequency == 0) continue;
        const acc = if (ch.flags & c.FM != 0) fm.modulateWave(&ch.fm, e, o.wave.acc) else o.wave.acc;
        sum +%= @divTrunc(wave.sample(&o.wave, e, acc) *% @as(i32, ch.adsr.volume), @as(i32, song.MAX_VOLUME));
    }
    return sum;
}

/// cyd_cycle: every channel's envelope, wavetable phase and FM, then sync.
pub fn cycle(sy: *Synth) void {
    for (sy.chn[0..sy.n]) |*ch| {
        ch.flags = adsr.cycle(sy.rate, ch.flags, ch.ym_env_shape, &ch.adsr);
        if (ch.flags & c.WAVE != 0) for (&ch.subosc) |*o| wave.cycle(&o.wave, ch.wave_entry);
        if (ch.flags & c.FM != 0) fm.cycle(sy.rate, &ch.fm);
    }
    for (sy.chn[0..sy.n]) |*ch| {
        if (ch.flags & c.SYNC == 0 or ch.sync_source >= sy.n) continue;
        if (sy.chn[ch.sync_source].sync_bit == 0) continue;
        for (&ch.subosc) |*o| {
            o.wave.acc = 0;
            o.wave.direction = 0;
            o.accumulator = 0;
            o.random = c.RANDOM_SEED;
            o.reg4 = 1;
            o.reg5 = 1;
            o.reg9 = 1;
            o.lfsr_ctr = 0;
        }
    }
}
