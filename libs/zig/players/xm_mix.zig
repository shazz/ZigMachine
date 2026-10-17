// --------------------------------------------------------------------------
// The XM voice mixer: the arithmetic that turns the eight voices into the
// four PCM buffers the Paula channels play (xm.zig owns the chip writes).
//
// Two voices share one Paula channel, so each is attenuated by half before
// they add: a pair's sum is then within the signed 8-bit range by
// construction (-128..126), and the Paula channel's volume (mod.zig's
// chipVolume, HEADROOM included) is the only gain stage left.
//
// A position is a frame index (i32: a ping-pong may step below 0 before its
// fold) and a u16 fraction, so a sample has no length cap beyond song RAM. The
// step is a Q16 u32 (xm_tables.stepOf), split the same way: its integer part is
// added to the index, its fraction to the fraction, and the fraction's carry
// goes to the index. That is the Q16 arithmetic, with no 64-bit operation
// anywhere (BARD is rv32im). A loop fold subtracts the loop length.
// Pure: no chip, no allocation. Tested natively (xm_mix_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const inst = @import("xm_instr.zig");

/// One XM voice's playing state. `gain` is 0..64, set once a tick by
/// xm_voice.zig from the volume, envelope and fadeout.
pub const Voice = struct {
    active: bool = false,
    sample: u16 = 0, // index into the song's sample table
    idx: i32 = 0, // frame index into the sample (signed: a ping-pong runs backward)
    frac: u16 = 0, // fraction of a frame, Q16
    step: u32 = 0, // Q16 frames per output frame (xm_tables.stepOf: below 2^31)
    dir: i8 = 1, // +1 forward, -1 while a ping-pong loop runs backward
    gain: u32 = 0, // 0..64
};

/// Mix `out.len` output frames of `v` (its sample's frames `src`) ADDED into
/// `out`. A voice that runs off a sample with no loop goes inactive.
pub fn mixVoice(v: *Voice, src: []const i8, s: *const inst.Sample, out: []i8) void {
    if (!v.active) return;
    const step_int: i32 = @intCast(v.step >> 16);
    const step_frac: u32 = v.step & 0xFFFF;
    for (out) |*o| {
        if (!fold(v, src.len, s)) {
            v.active = false;
            return;
        }
        const c: i32 = (@as(i32, src[@intCast(v.idx)]) * @as(i32, @intCast(v.gain))) >> 7;
        o.* = @intCast(@as(i32, o.*) + c);
        advance(v, step_int, step_frac);
    }
}

/// One output frame's step: the fraction adds (or subtracts, backward) and its
/// carry (or borrow) moves the index. The same as Q16 addition, split in two.
fn advance(v: *Voice, step_int: i32, step_frac: u32) void {
    if (v.dir > 0) {
        const sum: u32 = @as(u32, v.frac) + step_frac;
        v.frac = @truncate(sum);
        v.idx += step_int + @as(i32, @intCast(sum >> 16));
    } else {
        const diff: i32 = @as(i32, v.frac) - @as(i32, @intCast(step_frac));
        const borrow: i32 = if (diff < 0) 1 else 0;
        v.frac = @intCast(diff + borrow * 65536);
        v.idx -= step_int + borrow;
    }
}

/// Bring the index inside the sample: a loop is followed, a ping-pong turns
/// round, a sample with no loop ends (false) once it has run out.
fn fold(v: *Voice, len: usize, s: *const inst.Sample) bool {
    if (s.loop == inst.LOOP_NONE) return v.idx >= 0 and v.idx < @as(i32, @intCast(len));
    const start: i32 = @intCast(s.loop_start);
    const end: i32 = @intCast(s.loop_start + s.loop_len);
    // Below the loop and still running forward is the sample's attack, before the
    // loop is reached: only a backward run turns round at the loop start.
    if (v.idx >= end or (v.idx < start and v.dir < 0)) {
        v.idx = if (s.loop == inst.LOOP_FORWARD) forwardIndex(v.idx, start, end) else pingPongIndex(v, v.idx, start, end);
    }
    return true;
}

/// Wrap `idx` into [start, end) by subtracting the loop length. A voice steps at
/// most a few frames a sample, so this runs round the loop a handful of times.
fn forwardIndex(idx: i32, start: i32, end: i32) i32 {
    if (idx < start) return idx;
    const span = end - start;
    var i = idx - start;
    while (i >= span) i -= span;
    return start + i;
}

fn pingPongIndex(v: *Voice, idx: i32, start: i32, end: i32) i32 {
    var i = idx;
    if (i >= end) {
        i = 2 * (end - 1) - i;
        v.dir = -1;
    } else if (i < start) {
        i = 2 * start - i;
        v.dir = 1;
    }
    return std.math.clamp(i, start, end - 1);
}

/// The fixed gain of a voice: volume (0..64) x envelope (0..64) x fadeout
/// (0..65536), as 0..64. Integer only: it is run once a tick.
pub fn voiceGain(vol: u32, env: u32, fade: u32) u32 {
    return @intCast(@min((vol * env * fade) >> 22, 64));
}
