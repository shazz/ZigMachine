// --------------------------------------------------------------------------
// cyd a block at a time: each channel's block in passes (kt_passes.zig: the
// modulator, oscillators and wavetable voices into the channel's source sums;
// then kt_envpass.zig: ring modulation, envelope, filter, panning), then the
// FX buses. The same arithmetic in the same order per channel as
// kt_synth.zig's sample loop, so the same bytes: channels only meet in the
// sums (wrapping adds, in any order the same), in ring modulation (it reads
// another channel's source sum at the same sample: every sum is written
// before any envelope pass runs) and in hard sync, which resets a channel's
// phases after a sample where its source wrapped (kt_syncpass.zig: the
// source's wraps worked out first). A source that is synced itself, or ring
// modulation or sync beside an envelope-overriding wavetable (its channel
// runs the one-loop form below, without the sums), runs kt_synth.zig's way.
// Why: on BARD the player is wasm2c'd demo-audio (rv32, ~27 free registers);
// a pass holds a few fields, where a whole channel spilled every sample.
// --------------------------------------------------------------------------
const c = @import("kt_cyd.zig");
const song = @import("kt_song.zig");
const syn = @import("kt_synth.zig");
const osc = @import("kt_osc.zig");
const fxb = @import("kt_fxblock.zig");
const passes = @import("kt_passes.zig");
const env = @import("kt_envpass.zig");
const syncp = @import("kt_syncpass.zig");

pub const BLOCK = 128;
/// The mix's words: the dry pair, then each bus's pair, BLOCK samples each; then each channel's
/// source sums.
pub const MIX_WORDS = (2 + 2 * song.MAX_FX) * BLOCK;
pub const WORDS = MIX_WORDS + song.MAX_CH * BLOCK;

/// Ring modulation into a gated channel or hard sync only when every channel runs in passes, and
/// sync only from a source that is not synced itself (its wraps then follow from its own phase).
pub fn eligible(sy: *const syn.Synth) bool {
    var coupled = false;
    var all_passes = true;
    for (sy.chn[0..sy.n], 0..) |*ch, i| {
        if (synced(sy, ch)) {
            if (ch.sync_source == i or synced(sy, &sy.chn[ch.sync_source])) return false;
            coupled = true;
        }
        if (ch.flags & (c.GATE | c.RING_MODULATION) == (c.GATE | c.RING_MODULATION)) coupled = true;
        if (!passes.fits(ch)) all_passes = false;
    }
    return !coupled or all_passes;
}

/// cyd_cycle resets `ch`'s phases when its source wraps (a source past the song's channels: never).
fn synced(sy: *const syn.Synth, ch: *const c.Channel) bool {
    return ch.flags & c.SYNC != 0 and ch.sync_source < sy.n;
}

/// A channel's source passes, built for whether it has oscillators and whether sub-oscillators 1
/// and 2 are idle (a voice playing one note, the common case); FM and wavetable chosen at run time.
fn sources(rate: u32, chp: *c.Channel, src: []i32, heard: bool) void {
    switch (@as(u2, @intFromBool(chp.flags & c.WAVEFORMS & ~c.WAVE != 0)) | @as(u2, @intFromBool(idle(chp, 1) and idle(chp, 2))) << 1) {
        inline else => |v| passes.sources(rate, chp, src, heard, .{ .osc = v & 1 != 0, .subs = if (v & 2 != 0) 0b001 else 0b111 }),
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

/// An envelope-overriding wavetable's block in one loop (its voices are added after the envelope),
/// built for what the channel uses this block (kt_synth.zig Kind), 16 of them.
fn oneLoop(rate: u32, chp: *c.Channel, n: usize, dl: [*]i32, dr: [*]i32) void {
    const f = chp.flags;
    switch (@as(u4, @intFromBool(f & c.WAVEFORMS & ~c.WAVE != 0)) | @as(u4, @intFromBool(f & c.FM != 0)) << 1 |
        @as(u4, @intFromBool(f & c.WAVE != 0)) << 2 | @as(u4, @intFromBool(f & c.FILTER != 0)) << 3) {
        inline else => |v| channelK(rate, chp, n, dl, dr, .{ .osc = v & 1 != 0, .fm = v & 2 != 0, .wave = v & 4 != 0, .filter = v & 8 != 0 }),
    }
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

/// Ring modulation or sync in effect (eligible: every channel in passes): every channel's sums
/// first, then the envelope passes, which may read another channel's sums.
fn renderCoupled(sy: *syn.Synth, m: [*]i32, n: usize, ring_src: u32) void {
    const sums = m + MIX_WORDS;
    var wraps: [song.MAX_CH][BLOCK]u8 = undefined; // a sync source's wraps, from its phase before the passes
    for (sy.chn[0..sy.n]) |*ch| {
        if (synced(sy, ch)) osc.syncBits(&sy.chn[ch.sync_source], n, &wraps[ch.sync_source]);
    }
    for (sy.chn[0..sy.n], 0..) |*ch, i| {
        const heard = ch.flags & c.GATE != 0 or ring_src >> @intCast(i) & 1 != 0;
        const src = sums[i * BLOCK ..][0..n];
        if (synced(sy, ch)) syncp.sources(sy.rate, ch, src, heard, &wraps[ch.sync_source]) else sources(sy.rate, ch, src, heard);
    }
    for (sy.chn[0..sy.n], 0..) |*ch, i| {
        const d = pair(sy, m, ch);
        const ring: env.Ring = if (ch.flags & c.RING_MODULATION == 0) .none else if (ch.ring_mod < sy.n) .{ .src = sums + @as(usize, ch.ring_mod) * BLOCK } else .zero;
        env.output(sy.rate, ch, sums[i * BLOCK ..][0..n], ring, d[0], d[1], ch.flags & c.FILTER != 0);
    }
}

/// The mix pair `ch` adds into: its FX bus's, or the dry one.
fn pair(sy: *const syn.Synth, m: [*]i32, ch: *const c.Channel) [2][*]i32 {
    var at: usize = 0;
    if (ch.flags & c.FX != 0 and sy.bus_used >> @intCast(ch.fx_bus) & 1 != 0) at = 2 + 2 * @as(usize, ch.fx_bus);
    return .{ m + at * BLOCK, m + (at + 1) * BLOCK };
}

/// `out.len / 2` (<= BLOCK) stereo samples, s16, with no sequencer tick inside them.
pub fn render(sy: *syn.Synth, mix: []i32, out: []i16) void {
    const n = out.len / 2;
    const m = mix.ptr;
    const sums = m + MIX_WORDS;
    var ring_src: u32 = 0; // the channels a gated channel ring-modulates from: their sums are heard
    var any_sync = false;
    for (sy.chn[0..sy.n]) |*ch| {
        if (ch.flags & (c.GATE | c.RING_MODULATION) == (c.GATE | c.RING_MODULATION)) ring_src |= @as(u32, 1) << @intCast(ch.ring_mod & 31);
        if (synced(sy, ch)) any_sync = true;
    }
    if (ring_src == 0 and !any_sync) { // channels apart: each one's passes back to back, one sums buffer
        for (sy.chn[0..sy.n]) |*ch| {
            const d = pair(sy, m, ch);
            if (!passes.fits(ch)) {
                oneLoop(sy.rate, ch, n, d[0], d[1]);
                continue;
            }
            sources(sy.rate, ch, sums[0..n], ch.flags & c.GATE != 0);
            env.output(sy.rate, ch, sums[0..n], .none, d[0], d[1], ch.flags & c.FILTER != 0);
        }
    } else renderCoupled(sy, m, n, ring_src);
    for (&sy.bus, 0..) |*b, i| {
        if (sy.bus_used >> @intCast(i) & 1 != 0) fxb.output(b, m + (2 + 2 * i) * BLOCK, m + (3 + 2 * i) * BLOCK, n);
    }
    var used: [song.MAX_FX][*]i32 = undefined; // the buses with an effect: only they are summed
    var nb: usize = 0;
    for (0..song.MAX_FX) |i| if (sy.bus_used >> @intCast(i) & 1 != 0) {
        used[nb] = m + (2 + 2 * i) * BLOCK;
        nb += 1;
    };
    for (0..n) |t| {
        var l = m[t];
        var r = m[BLOCK + t];
        m[t] = 0;
        m[BLOCK + t] = 0;
        for (used[0..nb]) |p| {
            l +%= p[t];
            r +%= p[BLOCK + t];
            p[t] = 0;
            p[BLOCK + t] = 0;
        }
        out[2 * t] = clamp16(@divTrunc(l, 4));
        out[2 * t + 1] = clamp16(@divTrunc(r, 4));
    }
}

pub fn clamp16(v: i32) i16 {
    return @intCast(@min(32767, @max(-32768, v)));
}
