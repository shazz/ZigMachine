// --------------------------------------------------------------------------
// The XM effect commands the sequencer runs: rowEffect on a row's first tick,
// tickEffect on the others, and apply, which turns a channel's state into the
// mixer's step and gain every tick. Implemented: 0 arpeggio, 1/2 portamento,
// 3 tone portamento, 4 vibrato, 5/6 slide with portamento or vibrato, A volume
// slide, B/D jumps, C set volume, F speed/BPM, E1 E2 EA EB (fine slides and
// volume), E9 (retrigger), EC (cut), ED (delay), EE (pattern delay).
// The rest are read and ignored (xm.zig's header lists them).
// Memoised parameters (1 2 3 4 5 6 A) keep their last non-zero value, as FT2
// does; processRow resolves them into c.param before any effect runs.
// --------------------------------------------------------------------------
const std = @import("std");
const xt = @import("xm_tables.zig");
const xv = @import("xm_voice.zig");
const XmPlayer = @import("xm.zig").XmPlayer;

/// The parameter an effect runs with: a memoised effect reuses its last non-zero one.
pub fn memoParam(c: *xv.Chan, eff: u8, param: u8) u8 {
    const memoised = switch (eff) {
        1, 2, 3, 4, 5, 6, 0xA => true,
        else => false,
    };
    if (!memoised) return param;
    if (param != 0) c.memo[eff] = param;
    return c.memo[eff];
}

/// The effect's first-tick part, after the row's note has been handled.
pub fn rowEffect(p: *XmPlayer, ch: usize) void {
    const c = &p.chan[ch];
    switch (c.eff) {
        0xC => c.vol = @min(c.param, 64),
        0xF => if (c.param < 0x20) {
            if (c.param > 0) p.speed = c.param;
        } else p.setBpm(c.param),
        0xB => p.jump_pos = c.param,
        0xD => p.break_row = @intCast(@as(u16, c.param >> 4) * 10 + (c.param & 0x0F)),
        0x9 => sampleOffset(p, c),
        0xE => eRowEffect(p, c),
        else => {},
    }
}

/// 9xx: start the sample at param x 256 frames. Past the sample's end the note is
/// silent, as FT2 has it, rather than wrapped.
fn sampleOffset(p: *const XmPlayer, c: *xv.Chan) void {
    if (!c.mix.active) return;
    const off: u32 = @as(u32, c.param) * 256;
    if (off >= p.tabs.samps[c.mix.sample].len) {
        c.mix.active = false;
        return;
    }
    c.mix.pos = @intCast(off << 16);
}

fn eRowEffect(p: *XmPlayer, c: *xv.Chan) void {
    const x = c.param & 0x0F;
    switch (c.param >> 4) {
        0x1 => c.period = xt.clampPeriod(c.period - 4 * @as(i32, x)),
        0x2 => c.period = xt.clampPeriod(c.period + 4 * @as(i32, x)),
        0xA => c.vol = @min(c.vol + x, 64),
        0xB => c.vol -|= x,
        0xE => p.row_delay = x,
        else => {},
    }
}

/// The effect's part on ticks 1..speed-1.
pub fn tickEffect(p: *XmPlayer, ch: usize) void {
    const c = &p.chan[ch];
    switch (c.eff) {
        0x1 => c.period = xt.clampPeriod(c.period - 4 * @as(i32, c.param)),
        0x2 => c.period = xt.clampPeriod(c.period + 4 * @as(i32, c.param)),
        0x3 => tonePorta(c, c.memo[3]),
        0x4 => vibrato(c, c.param),
        0x5 => {
            tonePorta(c, c.memo[3]);
            volumeSlide(c, c.param);
        },
        0x6 => {
            vibrato(c, c.memo[4]);
            volumeSlide(c, c.param);
        },
        0xA => volumeSlide(c, c.param),
        0xE => eTickEffect(p, ch),
        else => {},
    }
}

fn eTickEffect(p: *XmPlayer, ch: usize) void {
    const c = &p.chan[ch];
    const x = c.param >> 4;
    const y = c.param & 0x0F;
    switch (x) {
        0x9 => if (y != 0 and p.tick % y == 0) {
            c.mix.pos = 0;
        },
        0xC => if (p.tick == y) {
            c.vol = 0;
        },
        0xD => if (p.tick == y and c.pending != 0) {
            p.trigger(ch, c.pending);
            c.pending = 0;
        },
        else => {},
    }
}

fn volumeSlide(c: *xv.Chan, param: u8) void {
    const up = param >> 4;
    const down = param & 0x0F;
    c.vol = @intCast(std.math.clamp(@as(i32, c.vol) + up - down, 0, 64));
}

/// Slide the period toward the note set by 3xx (or 5xx), by `speed` x 4 a tick.
fn tonePorta(c: *xv.Chan, speed: u8) void {
    if (c.target == 0 or speed == 0) return;
    const step: i32 = 4 * @as(i32, speed);
    if (c.period < c.target) {
        c.period = @min(c.target, c.period + step);
    } else if (c.period > c.target) {
        c.period = @max(c.target, c.period - step);
    }
}

fn vibrato(c: *xv.Chan, param: u8) void {
    c.vib_pos +%= param >> 4;
}

/// Set the channel's step and gain from its state, once a tick. Arpeggio
/// re-pitches the note; vibrato offsets the period; the envelope sets the gain.
pub fn apply(p: *XmPlayer, ch: usize) void {
    const c = &p.chan[ch];
    if (c.inst == 0 or c.inst > p.hdr.num_instruments) {
        c.mix.active = false;
        return;
    }
    const ins = &p.tabs.insts[c.inst - 1];
    var per = c.period;
    if (c.eff == 0 and c.param != 0) per = arpPeriod(p, c);
    if (c.eff == 4 or c.eff == 6) per += xt.vibratoDelta(c.vib_pos, c.memo[4] & 0x0F);
    c.mix.step = xt.stepOf(xt.clampPeriod(per), p.hdr.linear);
    c.mix.gain = xv.gainOf(c, &ins.vol);
}

fn arpPeriod(p: *const XmPlayer, c: *const xv.Chan) i32 {
    const off: i32 = switch (p.tick % 3) {
        0 => 0,
        1 => c.param >> 4,
        else => c.param & 0x0F,
    };
    return xt.periodOf(c.semi + off, c.ft, p.hdr.linear);
}

/// The envelope and fadeout move on once a tick, from tick 1.
pub fn tickEnvelope(p: *XmPlayer, ch: usize) void {
    const c = &p.chan[ch];
    if (c.inst == 0 or c.inst > p.hdr.num_instruments) return;
    xv.tickEnvelope(c, p.tabs.insts[c.inst - 1].fadeout);
}
