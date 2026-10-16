// --------------------------------------------------------------------------
// The XM voice mixer: the arithmetic that turns the eight voices into the
// four PCM buffers the Paula channels play (xm.zig owns the chip writes).
//
// Two voices share one Paula channel, so each is attenuated by half before
// they add: a pair's sum is then within the signed 8-bit range by
// construction (-128..126), and the Paula channel's volume (mod.zig's
// chipVolume, HEADROOM included) is the only gain stage left. Positions are
// Q16 frames and step through each output frame by the voice's step; a
// ping-pong or forward loop folds the position back inside itself.
//
// 32-bit throughout: BARD's rv32im has no 64-bit ALU, so a sample is at most
// inst.MAX_SAMPLE_FRAMES frames (the Q16 position then fits an i32) and loop
// folds subtract instead of dividing.
// Pure: no chip, no allocation. Tested natively (xm_mix_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");
const inst = @import("xm_instr.zig");

/// One XM voice's playing state. `gain` is 0..64, set once a tick by
/// xm_voice.zig from the volume, envelope and fadeout.
pub const Voice = struct {
    active: bool = false,
    sample: u16 = 0, // index into the song's sample table
    pos: i32 = 0, // Q16 frames into the sample (signed: a ping-pong runs backward)
    step: u32 = 0, // Q16 frames per output frame, below 2^31 (xm_tables.stepOf)
    dir: i8 = 1, // +1 forward, -1 while a ping-pong loop runs backward
    gain: u32 = 0, // 0..64
};

/// Mix `out.len` output frames of `v` (its sample's frames `src`) ADDED into
/// `out`. A voice that runs off a sample with no loop goes inactive.
pub fn mixVoice(v: *Voice, src: []const i8, s: *const inst.Sample, out: []i8) void {
    if (!v.active) return;
    const step: i32 = @intCast(v.step);
    for (out) |*o| {
        if (!fold(v, src.len, s)) {
            v.active = false;
            return;
        }
        const idx: usize = @intCast(v.pos >> 16);
        const c: i32 = (@as(i32, src[idx]) * @as(i32, @intCast(v.gain))) >> 7;
        o.* = @intCast(@as(i32, o.*) + c);
        v.pos += if (v.dir > 0) step else -step;
    }
}

/// Bring the position inside the sample: a loop is followed, a ping-pong turns
/// round, a sample with no loop ends (false) once it has run out.
fn fold(v: *Voice, len: usize, s: *const inst.Sample) bool {
    const idx: i32 = v.pos >> 16;
    if (s.loop == inst.LOOP_NONE) return idx >= 0 and idx < @as(i32, @intCast(len));
    const start: i32 = @intCast(s.loop_start);
    const end: i32 = @intCast(s.loop_start + s.loop_len);
    if (idx >= end or idx < start) {
        const next = if (s.loop == inst.LOOP_FORWARD) forwardIndex(idx, start, end) else pingPongIndex(v, idx, start, end);
        v.pos = (next << 16) | (v.pos & 0xFFFF);
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
