// --------------------------------------------------------------------------
// music.c do_command, the commands that run on every tick: portamento, pulse
// width, cutoff and buzz slides, release, volume fade, pan slides, note cut
// and retrigger. The tick-0 commands are kt_cmd0.zig.
// Note arithmetic is Uint16 that wraps, caught by upstream's "prev > note".
// --------------------------------------------------------------------------
const s = @import("kt_song.zig");
const eng = @import("kt_engine.zig");
const set = @import("kt_cyd_set.zig");
const chan = @import("kt_chan.zig");
const tab = @import("kt_tables.zig");
const cmd0 = @import("kt_cmd0.zig");

const Engine = eng.Engine;

pub fn slideUp(e: *Engine, i: usize, by: u16) void {
    const mc = &e.chn[i];
    const prev = mc.note;
    mc.note +%= by;
    if (prev > mc.note) mc.note = 0xffff;
    mc.target_note = mc.note;
}

pub fn slideDown(e: *Engine, i: usize, by: u16) void {
    const mc = &e.chn[i];
    const prev = mc.note;
    mc.note -%= by;
    if (prev < mc.note) mc.note = 0;
    mc.target_note = mc.note;
}

/// MUS_FX_PORTA_*_LOG's step: a constant ratio, as many 1/256 semitones as at middle C.
fn logStep(e: *const Engine, i: usize, p: u16) u16 {
    const n: u32 = @as(u32, tab.frequency[s.MIDDLE_C]) * p / tab.getFreq(e.chn[i].note);
    return @truncate(@max(1, n));
}

pub fn run(e: *Engine, i: usize, tick: u32, inst: u16, from_program: bool) void {
    perTick(e, i, tick, inst);
    if (tick == 0) cmd0.run(e, i, inst, from_program);
}

fn perTick(e: *Engine, i: usize, tick: u32, inst: u16) void {
    const ch = e.cyd(i);
    const t = &e.track[i];
    const mc = &e.chn[i];
    const p: u16 = inst & 0xff;
    switch (inst & 0x7f00) {
        0x0100 => slideUp(e, i, p << 2), // PORTA_UP
        0x0200 => slideDown(e, i, p << 2), // PORTA_DN
        0x0500 => slideUp(e, i, logStep(e, i, p)), // PORTA_UP_LOG
        0x0600 => slideDown(e, i, logStep(e, i, p)), // PORTA_DN_LOG
        0x0700 => { // PW_DN
            t.pw -%= p;
            if (t.pw > 0xf000) t.pw = 0;
        },
        0x0800 => { // PW_UP
            t.pw +%= p;
            if (t.pw > 0x7ff) t.pw = 0x7ff;
        },
        0x2200 => { // CUTOFF_DN
            t.filter_cutoff -%= p;
            if (t.filter_cutoff > 0xf000) t.filter_cutoff = 0;
            set.setFilterCoeffs(ch, t.filter_cutoff, t.filter_resonance);
        },
        0x2100 => { // CUTOFF_UP
            t.filter_cutoff +%= p;
            if (t.filter_cutoff > 0x7ff) t.filter_cutoff = 0x7ff;
            set.setFilterCoeffs(ch, t.filter_cutoff, t.filter_resonance);
        },
        0x3200 => { // BUZZ_DN
            if (@as(i32, mc.buzz_offset) >= -32768 + @as(i32, p)) mc.buzz_offset -%= @intCast(p);
            chan.setBuzz(e, i, mc.note);
        },
        0x3100 => { // BUZZ_UP
            if (@as(i32, mc.buzz_offset) <= 32767 - @as(i32, p)) mc.buzz_offset +%= @intCast(p);
            chan.setBuzz(e, i, mc.note);
        },
        0x7c00 => if (tick == p) set.enableGate(ch, e.synth.rate, false), // TRIGGER_RELEASE
        0x0a00 => if (mc.flags & eng.CHN_DISABLED == 0) { // FADE_VOLUME
            t.volume -%= @intCast(inst & 0xf);
            if (t.volume > s.MAX_VOLUME) t.volume = 0;
            t.volume +%= @intCast((inst >> 4) & 0xf);
            if (t.volume > s.MAX_VOLUME) t.volume = s.MAX_VOLUME;
            chan.updateVolumes(e, i, t.volume);
        },
        0x1700, 0x1900 => { // PAN_LEFT, PAN_RIGHT
            var pan: i32 = ch.panning;
            if (inst & 0xff00 == 0x1700) pan -= p else pan += p;
            set.setPanning(ch, @intCast(@min(128, @max(0, pan))));
        },
        0x0e00 => ext(e, i, tick, inst),
        else => {},
    }
}

/// Protracker-style Exy on every tick: note cut, retrigger.
fn ext(e: *Engine, i: usize, tick: u32, inst: u16) void {
    const ch = e.cyd(i);
    const t = &e.track[i];
    const mc = &e.chn[i];
    const x: u32 = inst & 0xf;
    switch (inst & 0xfff0) {
        0x0ec0 => if (mc.flags & eng.CHN_DISABLED == 0 and x <= tick) { // NOTE_CUT
            ch.adsr.volume = 0;
            t.volume = 0;
        },
        0x0e90 => if (x > 0 and tick % x == 0) { // RETRIGGER
            const prev_t = t.volume;
            const prev_c = ch.adsr.volume;
            _ = chan.trigger(e, i, mc.instrument orelse return, mc.last_note, -1);
            t.volume = prev_t;
            ch.adsr.volume = prev_c;
        },
        else => {},
    }
}
