// --------------------------------------------------------------------------
// cyd a block at a time: each channel's samples of the block in one loop over
// a COPY of its state (kt_synth.zig's per-sample stages, inlined), then the FX
// buses a sample at a time. The same arithmetic in the same order per channel
// as kt_synth.zig's sample loop, so the same bytes: channels only meet in the
// sums (wrapping adds, in any order the same) and in ring modulation and hard
// sync, which read another channel's sample; a block with either in effect
// runs kt_synth.zig's way instead (eligible).
// Why: on BARD the player is wasm2c'd demo-audio, where a field the release
// build re-reads from a channel is a load each sample; one channel's state in
// locals for a whole block keeps it in rv32 registers and the stack.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const syn = @import("kt_synth.zig");
const osc = @import("kt_osc.zig");
const fxb = @import("kt_fxblock.zig");
const passes = @import("kt_passes.zig");

pub const BLOCK = 64;
/// The mix's words: the dry pair, then each bus's pair, BLOCK samples each.
pub const WORDS = (2 + 2 * song.MAX_FX) * BLOCK;

/// No ring modulation into a gated channel and no hard sync: channels independent for the block.
pub fn eligible(sy: *const syn.Synth) bool {
    for (sy.chn[0..sy.n]) |*ch| {
        if (ch.flags & c.SYNC != 0) return false;
        if (ch.flags & (c.GATE | c.RING_MODULATION) == (c.GATE | c.RING_MODULATION)) return false;
    }
    return true;
}

/// One channel's `n` samples, panned and added into dl/dr (its bus or the dry mix). Most channels run
/// in passes (kt_passes.zig), built for whether the channel has oscillators and a filter and whether
/// sub-oscillators 1 and 2 are idle (a voice playing one note, the common case): 8 of them, the FM
/// and wavetable stages chosen at run time (a pass each). An envelope-overriding wavetable runs the
/// one-loop form, built for what the channel uses this block (kt_synth.zig Kind), 16 of them.
fn channel(rate: u32, chp: *c.Channel, n: usize, dl: [*]i32, dr: [*]i32) void {
    const f = chp.flags;
    const has_osc = f & c.WAVEFORMS & ~c.WAVE != 0;
    const has_filter = f & c.FILTER != 0;
    if (passes.fits(chp)) {
        switch (@as(u3, @intFromBool(has_osc)) | @as(u3, @intFromBool(has_filter)) << 1 |
            @as(u3, @intFromBool(idle(chp, 1) and idle(chp, 2))) << 2) {
            inline else => |v| passes.channel(rate, chp, n, dl, dr, .{
                .osc = v & 1 != 0,
                .filter = v & 2 != 0,
                .subs = if (v & 4 != 0) 0b001 else 0b111,
            }),
        }
        return;
    }
    switch (@as(u4, @intFromBool(has_osc)) | @as(u4, @intFromBool(f & c.FM != 0)) << 1 |
        @as(u4, @intFromBool(f & c.WAVE != 0)) << 2 | @as(u4, @intFromBool(has_filter)) << 3) {
        inline else => |v| channelK(rate, chp, n, dl, dr, .{ .osc = v & 1 != 0, .fm = v & 2 != 0, .wave = v & 4 != 0, .filter = v & 8 != 0 }),
    }
}

/// Sub-oscillator `i` does nothing for the block: no phase step (frequency 0, no LFSR), no
/// wavetable voice (stopped, or at frequency 0 inside its sample, where kt_wave.zig cycle leaves it).
fn idle(ch: *const c.Channel, i: usize) bool {
    const o = &ch.subosc[i];
    if (o.frequency != 0 or ch.flags & c.LFSR != 0) return false;
    if (ch.flags & c.WAVE == 0 or !o.wave.playing) return true;
    if (o.wave.frequency != 0) return false;
    const e = ch.wave_entry orelse return true;
    const looped = e.flags & song.WAVE_LOOP != 0 and e.loop_end != e.loop_begin;
    return o.wave.direction == 0 and o.wave.acc / c.WAVETABLE_RESOLUTION < (if (looped) e.loop_end else e.samples);
}

noinline fn channelK(rate: u32, chp: *c.Channel, n: usize, dl: [*]i32, dr: [*]i32, comptime k: syn.Kind) void {
    var ch = chp.*;
    var t: usize = 0;
    while (t < n) : (t += 1) {
        if (ch.flags & c.GATE != 0) {
            const o = syn.shaped(&ch, syn.source(&ch, k), k);
            dl[t] +%= @divTrunc(o *% ch.gain_left, c.STEREO_GAIN);
            dr[t] +%= @divTrunc(o *% ch.gain_right, c.STEREO_GAIN);
        } else {
            ch.sync_bit = 0;
            osc.advance(&ch, k.subs); // unheard: the phase and noise still move
        }
        syn.cycleOne(rate, &ch, k);
    }
    chp.* = ch;
}

/// `out.len / 2` (<= BLOCK) stereo samples, s16, with no sequencer tick inside them.
pub fn render(sy: *syn.Synth, mix: []i32, out: []i16) void {
    const n = out.len / 2;
    const m = mix.ptr;
    for (sy.chn[0..sy.n]) |*ch| {
        var at: usize = 0; // the dry pair
        if (ch.flags & c.FX != 0 and sy.bus_used >> @intCast(ch.fx_bus) & 1 != 0) at = 2 + 2 * @as(usize, ch.fx_bus);
        channel(sy.rate, ch, n, m + at * BLOCK, m + (at + 1) * BLOCK);
    }
    for (&sy.bus, 0..) |*b, i| {
        if (sy.bus_used >> @intCast(i) & 1 != 0) fxb.output(b, m + (2 + 2 * i) * BLOCK, m + (3 + 2 * i) * BLOCK, n);
    }
    for (0..n) |t| {
        var l = m[t];
        var r = m[BLOCK + t];
        m[t] = 0;
        m[BLOCK + t] = 0;
        for (0..song.MAX_FX) |i| {
            if (sy.bus_used >> @intCast(i) & 1 == 0) continue;
            l +%= m[(2 + 2 * i) * BLOCK + t];
            r +%= m[(3 + 2 * i) * BLOCK + t];
            m[(2 + 2 * i) * BLOCK + t] = 0;
            m[(3 + 2 * i) * BLOCK + t] = 0;
        }
        out[2 * t] = clamp16(@divTrunc(l, 4));
        out[2 * t + 1] = clamp16(@divTrunc(r, 4));
    }
}

pub fn clamp16(v: i32) i16 {
    return @intCast(@min(32767, @max(-32768, v)));
}
