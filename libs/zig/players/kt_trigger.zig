// --------------------------------------------------------------------------
// An instrument's note on (music.c mus_trigger_instrument_internal): the
// channel takes the instrument's waveforms, envelope, filter, pulse width,
// buzz, wavetable, FM and program, its note is set, and its gate opens.
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const c = @import("kt_cyd.zig");
const eng = @import("kt_engine.zig");
const set = @import("kt_cyd_set.zig");
const chan = @import("kt_chan.zig");

const Engine = eng.Engine;

pub fn trigger(e: *Engine, i: usize, ins: *const s.Instrument, note_in: u16, panning: i32) usize {
    const ch = e.cyd(i);
    const mc = &e.chn[i];
    const t = &e.track[i];
    const n_ch: u8 = @intCast(e.synth.n);
    mc.flags = eng.CHN_PLAYING | (mc.flags & eng.CHN_DISABLED);
    if (ins.prog_period > 0) mc.flags |= eng.CHN_PROGRAM_RUNNING;
    mc.prog_period = ins.prog_period;
    mc.instrument = ins;
    if (ins.flags & s.INST_NO_PROG_RESTART == 0) {
        mc.program_counter = 0;
        mc.program_tick = 0;
        mc.program_loop = 1;
    }
    ch.flags = ins.cydflags;
    mc.arpeggio_note = 0;
    mc.fixed_note = 0xffff;
    ch.fx_bus = ins.fx_bus & 7;
    if (ins.flags & s.INST_DRUM != 0) set.setWaveform(ch, c.NOISE);
    const note: u16 = if (ins.flags & s.INST_LOCK_NOTE != 0)
        @as(u16, ins.base_note) << 8
    else
        note_in +% (@as(u16, ins.base_note -% @as(u8, s.MIDDLE_C)) << 8);
    const fine: u16 = note +% @as(u16, @bitCast(@as(i16, ins.finetune)));
    chan.setNote(e, i, fine, true, if (ins.flags & s.INST_QUARTER_FREQ != 0) 4 else 1);
    mc.last_note = fine;
    mc.target_note = fine;
    mc.current_tick = 0;
    t.vibrato_position = 0;
    t.vib_delay = ins.vib_delay;
    t.slide_speed = 0;
    chan.updateVolumes(e, i, if (ins.flags & s.INST_RELATIVE_VOLUME != 0) s.MAX_VOLUME else ins.volume);
    ch.sync_source = if (ins.sync_source == 0xff) @intCast(i) else ins.sync_source;
    ch.ring_mod = if (ins.ring_mod == 0xff) @intCast(i) else ins.ring_mod;
    if (ch.ring_mod >= n_ch) ch.ring_mod = n_ch - 1;
    if (ch.sync_source >= n_ch) ch.sync_source = n_ch - 1;
    ch.flttype = ins.flttype;
    ch.lfsr_type = ins.lfsr_type;
    if (ins.cydflags & c.KEY_SYNC != 0) t.pwm_position = 0;
    if (ins.flags & s.INST_SET_CUTOFF != 0) {
        t.filter_cutoff = ins.cutoff;
        t.filter_resonance = ins.resonance;
        set.setFilterCoeffs(ch, ins.cutoff, ins.resonance);
    }
    if (ins.flags & s.INST_SET_PW != 0) {
        t.pw = ins.pw;
        chan.doPwm(e, i);
    }
    if (ins.flags & s.INST_YM_BUZZ != 0) {
        ch.flags |= c.YM_ENV;
        set.setEnvShape(ch, ins.ym_env_shape);
        mc.buzz_offset = ins.buzz_offset;
    } else {
        ch.flags &= ~c.YM_ENV;
        ch.adsr.a = ins.adsr.a;
        ch.adsr.d = ins.adsr.d;
        ch.adsr.s = ins.adsr.s;
        ch.adsr.r = ins.adsr.r;
    }
    const waves = e.song.waves;
    set.setWaveEntry(ch, if (ins.cydflags & c.WAVE != 0) &waves[ins.wavetable_entry & 127] else null);
    setFmWave(&ch.fm, if (ins.fm_flags & c.WAVE != 0) &waves[ins.fm_wave & 127] else null);
    if (panning != -1) set.setPanning(ch, @intCast(panning));
    const f = &ch.fm;
    f.flags = ins.fm_flags;
    f.harmonic = ins.fm_harmonic;
    f.adsr.a = ins.fm_adsr.a;
    f.adsr.d = ins.fm_adsr.d;
    f.adsr.s = ins.fm_adsr.s;
    f.adsr.r = ins.fm_adsr.r;
    f.adsr.volume = ins.fm_modulation;
    f.feedback = ins.fm_feedback & 7;
    f.attack_start = ins.fm_attack_start;
    set.enableGate(ch, e.synth.rate, true);
    return i;
}

/// cydfm_set_wave_entry.
pub fn setFmWave(f: *c.Fm, entry: ?*const s.WaveEntry) void {
    f.wave_entry = entry;
    f.wave.frequency = 0;
    f.wave.direction = 0;
}
