// --------------------------------------------------------------------------
// A .kt channel's notes (music.c): an instrument's trigger
// (mus_trigger_instrument_internal), the note's frequencies on the three
// sub-oscillators, wavetable and buzz envelope (mus_set_note), the volume
// (update_volumes) and the per-tick work of a playing channel
// (mus_advance_channel: drum, slide, program, vibrato, PWM).
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const c = @import("kt_cyd.zig");
const eng = @import("kt_engine.zig");
const set = @import("kt_cyd_set.zig");
const tab = @import("kt_tables.zig");
const prog = @import("kt_prog.zig");
const trig = @import("kt_trigger.zig");

const Engine = eng.Engine;

pub const trigger = trig.trigger;

/// The volume a channel plays at: `v` scaled by the song, global and channel volumes.
pub fn scaleVolume(e: *const Engine, v: u32, chn_volume: u8) u8 {
    return @truncate(v * e.volume / s.MAX_VOLUME * e.play_volume / s.MAX_VOLUME * chn_volume / s.MAX_VOLUME);
}

pub fn updateVolumes(e: *Engine, i: usize, volume: u8) void {
    const mc = &e.chn[i];
    const t = &e.track[i];
    t.volume = volume;
    const disabled = mc.flags & eng.CHN_DISABLED != 0;
    const v: u32 = if (mc.instrument) |ins| (if (ins.flags & s.INST_RELATIVE_VOLUME != 0) @as(u32, ins.volume) * volume / s.MAX_VOLUME else volume) else volume;
    e.cyd(i).adsr.volume = if (disabled) 0 else scaleVolume(e, v, mc.volume);
}

pub fn updateAllVolumes(e: *Engine) void {
    for (0..e.synth.n) |i| updateVolumes(e, i, e.track[i].volume);
}

/// The note of sub-oscillator `sub` (0, or 1 and 2 for a multi-oscillator
/// instrument's extended arpeggio); 0 is off.
fn subNote(e: *const Engine, i: usize, note: u16, sub: usize) u16 {
    const t = &e.track[i];
    const multi = if (e.chn[i].instrument) |ins| ins.flags & s.INST_MULTIOSC != 0 else false;
    if (sub == 0) return note;
    if (!multi) return 0;
    const arp = if (sub == 1) t.extarp1 else t.extarp2;
    return if (arp != 0) note +% (@as(u16, arp) << 8) else 0;
}

fn freqOf(e: *const Engine, note: u16) u16 {
    return @truncate(tab.getFreq(note) & e.pitch_mask);
}

/// mus_set_note: the oscillators', the wavetable's and the buzz envelope's frequencies.
pub fn setNote(e: *Engine, i: usize, note: u16, update: bool, divider: u16) void {
    const mc = &e.chn[i];
    const ch = e.cyd(i);
    const rate = e.synth.rate;
    if (update) mc.note = note;
    for (0..c.SUB_OSCS) |sub| {
        const n = subNote(e, i, note, sub);
        const f: u16 = if (n != 0) freqOf(e, n) else 0;
        set.setFrequency(ch, rate, sub, f / divider);
    }
    const ins = mc.instrument orelse return;
    if (ins.cydflags & c.WAVE != 0) if (ch.wave_entry) |we| {
        for (0..c.SUB_OSCS) |sub| {
            const n = subNote(e, i, note, sub);
            var f: u16 = 0;
            if (n != 0) f = freqOf(e, if (ins.flags & s.INST_WAVE_LOCK_NOTE != 0) we.base_note else n);
            set.setWavetableFrequency(ch, rate, sub, f);
        }
    };
    if (ins.flags & s.INST_YM_BUZZ != 0) setBuzz(e, i, note);
}

pub fn setBuzz(e: *Engine, i: usize, note: u16) void {
    const mc = &e.chn[i];
    const ins = mc.instrument orelse return;
    if (ins.flags & s.INST_YM_BUZZ == 0) return;
    const n: i32 = @as(i32, note) + mc.buzz_offset; // int, not Uint16: get_freq clamps it
    set.setEnvFrequency(e.cyd(i), e.synth.rate, @truncate(tab.getFreq(n) & e.pitch_mask));
}

pub fn doPwm(e: *Engine, i: usize) void {
    const ins = e.chn[i].instrument.?;
    const t = &e.track[i];
    t.pwm_position +%= ins.pwm_speed;
    const sh: i32 = tab.shape(t.pwm_position >> 1, ins.pwm_shape);
    e.cyd(i).pw = @truncate(@as(u32, @bitCast(@as(i32, t.pw) + @divTrunc(sh * ins.pwm_depth, 32))));
}

/// mus_advance_channel: a playing channel's tick.
pub fn advance(e: *Engine, i: usize) void {
    const mc = &e.chn[i];
    const t = &e.track[i];
    const ch = e.cyd(i);
    if (ch.flags & c.GATE == 0) {
        mc.flags &= ~eng.CHN_PLAYING;
        return;
    }
    const ins = mc.instrument.?;
    if (ins.flags & s.INST_DRUM != 0 and mc.current_tick == 1) set.setWaveform(ch, ins.cydflags);
    if (t.slide_speed != 0) {
        if (mc.target_note > mc.note) {
            mc.note +%= @min(t.slide_speed, mc.target_note - mc.note);
        } else if (mc.target_note < mc.note) {
            mc.note -%= @min(t.slide_speed, mc.note - mc.target_note);
        }
    }
    mc.current_tick +%= 1;
    if (mc.flags & eng.CHN_PROGRAM_RUNNING != 0) {
        const u = @as(u32, mc.program_counter) + 1 >= mc.prog_period;
        prog.progTick(e, i, u);
        mc.program_counter +%= 1;
        if (u) mc.program_counter = 0;
    }
    const vib = vibrato(e, i, ins);
    doPwm(e, i);
    const base: i32 = if (mc.fixed_note != 0xffff) mc.fixed_note else mc.note;
    var note: i32 = base + vib + (@as(i32, mc.arpeggio_note) << 8);
    if (note < 0) note = 0;
    if (note > @as(i32, s.FREQ_TAB_SIZE) << 8) note = (@as(i32, s.FREQ_TAB_SIZE) - 1) << 8;
    setNote(e, i, @intCast(note), false, if (ins.flags & s.INST_QUARTER_FREQ != 0) 4 else 1);
}

fn vibrato(e: *Engine, i: usize, ins: *const s.Instrument) i32 {
    const t = &e.track[i];
    var ctrl: u8 = 0;
    var depth: i32 = @max(0, @as(i32, ins.vibrato_depth) - @as(i32, t.vib_delay));
    var speed: i32 = ins.vibrato_speed;
    if (t.pattern != null) {
        const st = t.step();
        ctrl = st.ctrl;
        if (st.command & 0xff00 == 0x0400) { // MUS_FX_VIBRATO
            ctrl |= s.CTRL_VIB;
            if (st.command & 0xff != 0) {
                depth = @as(i32, st.command & 0xf) << 2;
                speed = @as(i32, st.command & 0xf0) >> 2;
                if (speed == 0) speed = ins.vibrato_speed;
                if (depth == 0) depth = ins.vibrato_depth;
            }
        }
    }
    const on = ctrl & s.CTRL_VIB != 0;
    const invert = ins.flags & s.INST_INVERT_VIBRATO_BIT != 0;
    if (on == invert) return 0;
    t.vibrato_position +%= @truncate(@as(u32, @bitCast(speed)));
    const v: i32 = @divTrunc(@as(i32, tab.shape(t.vibrato_position >> 1, ins.vib_shape)) * depth, 64);
    if (t.vib_delay != 0) t.vib_delay -= 1;
    return @as(i16, @truncate(v)); // Sint16 vib
}
