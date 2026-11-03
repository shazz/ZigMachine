// --------------------------------------------------------------------------
// cyd.c's setters, the calls music.c makes on a channel between samples: init,
// frequencies, gate, envelope shape, panning, filter, wavetable. Integer only
// (the 64-bit products are upstream's Uint64 arithmetic, run once a tick).
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const tab = @import("kt_tables.zig");
const flt = @import("kt_filter.zig");
const adsr = @import("kt_adsr.zig");

/// cyd_init_channel (then sync_source = its own index, as cyd_reset).
pub fn initChannel(ch: *c.Channel, rate: u32, index: u8) void {
    ch.* = .{};
    setFilterCoeffs(ch, 2047, 0);
    setPanning(ch, c.PAN_CENTER);
    ch.sync_source = index;
    _ = rate;
}

/// envspd: the SID envelope's step per sample for a slope (0..255).
pub fn envSpeed(rate: u32, slope: u8) u32 {
    const k: u64 = 0xff0000;
    if (slope == 0) return @truncate(k * c.CYD_BASE_FREQ / rate);
    const sl: u64 = slope;
    const d: u64 = sl * sl * 256 / (c.ENVELOPE_SCALE * c.ENVELOPE_SCALE);
    return @truncate(k / d * c.CYD_BASE_FREQ / rate);
}

pub fn setFrequency(ch: *c.Channel, rate: u32, sub: usize, frequency: u16) void {
    const o = &ch.subosc[sub];
    if (frequency != 0) {
        o.frequency = @truncate(@as(u64, c.ACC_LENGTH) / 16 * frequency / rate);
        o.lfsr_period = @truncate(@as(u64, rate) * 16 / frequency);
    } else o.frequency = 0;
    if (sub == 0) setFmFrequency(&ch.fm, rate, frequency);
}

const harmonic = [16]u64{ 1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30 }; // x MUL (2)

/// cydfm_set_frequency.
pub fn setFmFrequency(fm: *c.Fm, rate: u32, base: u16) void {
    const hn = harmonic[fm.harmonic & 15];
    const hd = harmonic[fm.harmonic >> 4];
    fm.period = @truncate((@as(u64, c.ACC_LENGTH) / 16 * base / rate) * hn / hd);
    if (fm.wave_entry) |e| {
        fm.wave.playing = true;
        const f: u64 = (@as(u64, c.WAVETABLE_RESOLUTION) * e.sample_rate / rate * base / tab.getFreq(e.base_note)) * hn / hd;
        fm.wave.frequency = @truncate(f);
    }
}

pub fn setWavetableFrequency(ch: *c.Channel, rate: u32, sub: usize, frequency: u16) void {
    const o = &ch.subosc[sub];
    if (frequency != 0) if (ch.wave_entry) |e| {
        const f: u64 = @as(u64, c.WAVETABLE_RESOLUTION) * e.sample_rate / rate * frequency / tab.getFreq(e.base_note);
        o.wave.frequency = @truncate(f);
        return;
    };
    o.wave.playing = false;
    o.wave.frequency = 0;
}

pub fn setEnvFrequency(ch: *c.Channel, rate: u32, frequency: u16) void {
    ch.adsr.env_speed = @truncate(@as(u64, c.YM_LENGTH) / 16 * frequency / rate);
}

pub fn setEnvShape(ch: *c.Channel, shape: u8) void {
    ch.ym_env_shape = shape;
    if (ch.flags & c.KEY_SYNC != 0 or ch.adsr.state == c.DONE or ch.adsr.state == c.SUSTAIN) {
        if (shape & c.YM_ENV_ATT != 0) {
            ch.adsr.envelope = 0;
            ch.adsr.state = c.ATTACK;
        } else {
            ch.adsr.envelope = c.YM_LENGTH;
            ch.adsr.state = c.DECAY;
        }
    }
}

pub fn enableGate(ch: *c.Channel, rate: u32, on: bool) void {
    if (!on) {
        ch.flags &= ~c.WAVE_OVERRIDE_ENV;
        ch.adsr.state = c.RELEASE;
        ch.adsr.env_speed = envSpeed(rate, ch.adsr.r);
        ch.fm.adsr.state = c.RELEASE;
        ch.fm.adsr.env_speed = envSpeed(rate, ch.fm.adsr.r);
        return;
    }
    if (ch.flags & c.YM_ENV == 0) {
        ch.adsr.state = c.ATTACK;
        ch.adsr.envelope = 0;
        ch.adsr.env_speed = envSpeed(rate, ch.adsr.a);
        ch.flags = adsr.cycle(rate, ch.flags, ch.ym_env_shape, &ch.adsr);
        ch.fm.adsr.state = c.ATTACK;
        ch.fm.adsr.envelope = @as(u32, ch.fm.attack_start) << 19;
        ch.fm.adsr.env_speed = envSpeed(rate, ch.fm.adsr.a);
        _ = adsr.cycle(rate, 0, 0, &ch.fm.adsr);
    }
    if (ch.flags & c.KEY_SYNC != 0) {
        for (&ch.subosc) |*o| {
            o.accumulator = 0;
            o.reg4 = 1;
            o.reg5 = 1;
            o.reg9 = 1;
            o.lfsr_ctr = 0;
        }
        ch.fm.accumulator = 0;
        ch.fm.wave.acc = 0;
    }
    ch.flags |= c.GATE;
}

pub fn setWaveform(ch: *c.Channel, wave: u32) void {
    ch.flags = (ch.flags & ~c.WAVEFORMS) | (wave & c.WAVEFORMS);
}

const resonance_table = [4]u16{ 10, 512, 1300, 1950 };

pub fn setFilterCoeffs(ch: *c.Channel, cutoff: u16, resonance: u8) void {
    flt.setCoeff(&ch.flt, cutoff, resonance_table[resonance & 3]);
}

pub fn setPanning(ch: *c.Channel, panning: u8) void {
    if (ch.panning == panning) return;
    ch.panning = @min(c.PAN_RIGHT, panning);
    ch.gain_left = tab.pan_left[ch.panning];
    ch.gain_right = tab.pan_right[ch.panning];
}

pub fn setWaveEntry(ch: *c.Channel, entry: ?*const song.WaveEntry) void {
    ch.wave_entry = entry;
    for (&ch.subosc) |*o| o.wave = .{ .playing = true };
}

/// cyd_set_wavetable_offset: 0..0x1000 = 0..100 % of the sample.
pub fn setWavetableOffset(ch: *c.Channel, offset: u16) void {
    const e = ch.wave_entry orelse return;
    for (&ch.subosc) |*o| o.wave.acc = @truncate(@as(u64, offset) * c.WAVETABLE_RESOLUTION * e.samples / 0x1000);
}
