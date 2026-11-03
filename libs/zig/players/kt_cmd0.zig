// --------------------------------------------------------------------------
// music.c do_command, the commands that run on tick 0 only: the set-value
// commands (volume, panning, filter, pulse width, buzz, FM, waveform, speed,
// rate, arpeggio, sync/ring sources, FX bus, wavetable) and the fine Exy ones.
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const c = @import("kt_cyd.zig");
const eng = @import("kt_engine.zig");
const set = @import("kt_cyd_set.zig");
const chan = @import("kt_chan.zig");
const fx = @import("kt_fx.zig");
const cmd = @import("kt_cmd.zig");

const Engine = eng.Engine;

pub fn run(e: *Engine, i: usize, inst: u16, from_program: bool) void {
    if (inst & 0xff00 == 0x0e00) return ext(e, i, inst);
    const ch = e.cyd(i);
    const t = &e.track[i];
    switch (inst & 0xf000) {
        0x6000 => { // CUTOFF_FINE_SET
            t.filter_cutoff = @min(inst & 0xfff, 0x7ff);
            set.setFilterCoeffs(ch, t.filter_cutoff, t.filter_resonance);
        },
        0x5000 => set.setWavetableOffset(ch, inst & 0xfff), // WAVETABLE_OFFSET
        else => {},
    }
    setValue(e, i, inst, from_program);
}

fn ext(e: *Engine, i: usize, inst: u16) void {
    const t = &e.track[i];
    const x: u8 = @intCast(inst & 0xf);
    const enabled = e.chn[i].flags & eng.CHN_DISABLED == 0;
    switch (inst & 0xfff0) {
        0x0ea0 => if (enabled) { // FADE_VOLUME_DN
            t.volume -%= x;
            if (t.volume > s.MAX_VOLUME) t.volume = 0;
            chan.updateVolumes(e, i, t.volume);
        },
        0x0eb0 => if (enabled) { // FADE_VOLUME_UP
            t.volume +%= x;
            if (t.volume > s.MAX_VOLUME) t.volume = s.MAX_VOLUME;
            chan.updateVolumes(e, i, t.volume);
        },
        0x0e10 => cmd.slideUp(e, i, x), // EXT_PORTA_UP
        0x0e20 => cmd.slideDown(e, i, x), // EXT_PORTA_DN
        else => {},
    }
}

fn filterCmd(e: *Engine, i: usize, inst: u16) void {
    const ch = e.cyd(i);
    const t = &e.track[i];
    const p: u16 = inst & 0xff;
    switch (inst & 0x7f00) {
        0x2b00 => ch.flttype = @intCast((inst & 0xf) % 3), // FILTER_TYPE
        0x2900 => t.filter_cutoff = @min(p << 3, 0x7ff), // CUTOFF_SET
        0x2c00 => { // CUTOFF_SET_COMBINED
            t.filter_cutoff = (if (p < 0x80) p else p - 0x80) << 4;
            ch.flttype = if (p < 0x80) c.FLT_LP else c.FLT_HP;
        },
        else => t.filter_resonance = @intCast(inst & 3), // 0x2a00 RESONANCE_SET
    }
    if (inst & 0x7f00 != 0x2b00) set.setFilterCoeffs(ch, t.filter_cutoff, t.filter_resonance);
}

fn waveform(inst: u16) u32 {
    var w: u32 = inst & (c.NOISE | c.PULSE | c.TRIANGLE | c.SAW); // MUS_FX_WAVE_* = CYD_CHN_ENABLE_* here
    if (inst & 32 != 0) w |= c.WAVE;
    if (inst & 16 != 0) w |= c.LFSR;
    return w;
}

fn setValue(e: *Engine, i: usize, inst: u16, from_program: bool) void {
    const ch = e.cyd(i);
    const t = &e.track[i];
    const mc = &e.chn[i];
    const p: u16 = inst & 0xff;
    const waves = e.song.waves;
    switch (inst & 0x7f00) {
        0x1d00 => { // SET_GLOBAL_VOLUME
            e.play_volume = @intCast(@min(p, s.MAX_VOLUME));
            chan.updateAllVolumes(e);
        },
        0x1a00 => { // FADE_GLOBAL_VOLUME
            e.play_volume -%= @intCast(inst & 0xf);
            if (e.play_volume > s.MAX_VOLUME) e.play_volume = 0;
            e.play_volume +%= @intCast((inst & 0xf0) >> 4);
            if (e.play_volume > s.MAX_VOLUME) e.play_volume = s.MAX_VOLUME;
            chan.updateAllVolumes(e);
        },
        0x1c00 => { // SET_CHANNEL_VOLUME
            mc.volume = @intCast(@min(p, s.MAX_VOLUME));
            chan.updateVolumes(e, i, t.volume);
        },
        0x0900 => t.pw = p << 4, // PW_SET
        0x3f00 => set.setEnvShape(ch, @intCast(inst & 3)), // BUZZ_SHAPE
        0x3a00 => { // BUZZ_SET_SEMI
            mc.buzz_offset = @intCast((@as(i32, p) - 0x80) << 8);
            chan.setBuzz(e, i, mc.note);
        },
        0x3900 => { // BUZZ_SET
            mc.buzz_offset = @bitCast((@as(u16, @bitCast(mc.buzz_offset)) & 0xff00) | p);
            chan.setBuzz(e, i, mc.note);
        },
        0x3300 => ch.fm.adsr.volume = @intCast(inst % 128), // FM_SET_MODULATION
        0x3500 => ch.fm.harmonic = @truncate(inst), // FM_SET_HARMONIC (inst % 256)
        0x3400 => ch.fm.feedback = @intCast(inst % 8), // FM_SET_FEEDBACK
        0x3600 => if (p < s.MAX_WAVES) {
            ch.fm.wave_entry = &waves[p];
        }, // FM_SET_WAVEFORM
        0x1800 => set.setPanning(ch, @intCast(p)), // SET_PANNING
        0x2b00, 0x2900, 0x2c00, 0x2a00 => filterCmd(e, i, inst),
        0x0f00 => if (from_program) { // SET_SPEED
            mc.prog_period = @intCast(p);
        } else {
            e.song.song_speed = @intCast(inst & 0xf);
            e.song.song_speed2 = if (inst & 0xf0 == 0) e.song.song_speed else @intCast((inst >> 4) & 0xf);
        },
        0x1f00 => { // SET_RATE
            e.song.song_rate = @intCast(@max(p, 1));
            e.setTickRate(e.song.song_rate);
        },
        0x1100 => { // PORTA_UP_SEMI
            const prev = mc.note;
            mc.note +%= p << 8;
            if (prev > mc.note or mc.note >= @as(u16, s.FREQ_TAB_SIZE) << 8) mc.note = (s.FREQ_TAB_SIZE - 1) << 8;
            mc.target_note = mc.note;
        },
        0x1200 => cmd.slideDown(e, i, p << 8), // PORTA_DN_SEMI
        0x4000 => { // ARPEGGIO_ABS
            mc.arpeggio_note = 0;
            mc.fixed_note = p << 8;
        },
        0x0000 => arpeggio(e, i, p), // ARPEGGIO
        0x0c00 => { // SET_VOLUME
            t.volume = @intCast(@min(p, s.MAX_VOLUME));
            chan.updateVolumes(e, i, t.volume);
        },
        0x7a00 => if (p != 0xff) { // SET_SYNCSRC
            ch.sync_source = @intCast(p % s.MAX_FX);
            ch.flags |= c.SYNC;
        } else {
            ch.flags &= ~c.SYNC;
        },
        0x7b00 => if (p != 0xff) { // SET_RINGSRC
            ch.ring_mod = @intCast(p % s.MAX_FX);
            ch.flags |= c.RING_MODULATION;
        } else {
            ch.flags &= ~c.RING_MODULATION;
        },
        0x1b00 => ch.fx_bus = @intCast(p % s.MAX_FX), // SET_FXBUS
        0x1e00 => fx.setCrush(&e.synth.bus[ch.fx_bus].crush, e.synth.rate, p, -1, -1, -1), // SET_DOWNSAMPLE
        0x3b00 => if (p < s.MAX_WAVES) {
            ch.wave_entry = &waves[p];
        }, // SET_WAVETABLE_ITEM
        0x0b00 => set.setWaveform(ch, waveform(inst)), // SET_WAVEFORM
        0x7d00 => if (!from_program) { // RESTART_PROGRAM
            mc.program_counter = 0;
            mc.program_tick = 0;
            mc.program_loop = 1;
        },
        else => {},
    }
}

fn arpeggio(e: *Engine, i: usize, p: u16) void {
    const mc = &e.chn[i];
    const t = &e.track[i];
    if (mc.fixed_note != 0xffff) {
        mc.note = mc.last_note;
        mc.fixed_note = 0xffff;
    }
    mc.arpeggio_note = if (p == 0xf0) t.extarp1 else if (p == 0xf1) t.extarp2 else @intCast(p);
}
