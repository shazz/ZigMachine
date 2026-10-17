// --------------------------------------------------------------------------
// The XM player's chip side: the voices mixed onto the Paula channels, two to a
// channel for a song of 8 or fewer channels (the original pairing, bit for bit)
// and three to a channel for 9..12 channels. The channel count fixes the group
// size and so the attenuation (xm_mix.zig's SCALE_*), once per song.
// Each block (a span of one tick, or part of it) is mixed from the voices into
// the next span of each Paula channel's ring (xm_ring.zig: on the board the
// chip plays a block up to four frames after it was written, so a block's bytes
// must outlive that), and each channel plays that span ONCE at one source frame
// per output frame: a re-trigger every block. The channels' step and volume are
// set once at start (setup); only the trigger, which holds the pan, runs per
// block. The rings are in song RAM, in the demo-audio module's memory, which
// the sealed chip shares.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const mod = @import("mod.zig");
const xmix = @import("xm_mix.zig");
const inst = @import("xm_instr.zig");
const ring = @import("xm_ring.zig");
const XmPlayer = @import("xm.zig").XmPlayer;

/// Songs of up to this many channels mix two voices to a Paula channel.
pub const PAIR_MAX_CH: u8 = 8;

/// The voices on each Paula channel, and the attenuation that keeps their sum in i8.
pub const Grouping = struct { per: usize, scale: i32 };

pub fn groupingOf(channels: u8) Grouping {
    return if (channels > PAIR_MAX_CH)
        .{ .per = 3, .scale = xmix.SCALE_TRIPLE }
    else
        .{ .per = 2, .scale = xmix.SCALE_PAIR };
}

/// The four channel rings sit at the top of song RAM, past the largest song that
/// fits beside them: a static ring would be 64 KB of zeros in demo-audio's data
/// segment (zero_segments). A song longer than BUF_OFFSET is refused at load.
pub const BUF_OFFSET: usize = audio.SONG_CAP - audio.NUM_CHANNELS * ring.FRAMES;

/// Channel `pair`'s ring, from its start: the offset in song RAM.
fn ringOffset(pair: usize, start: u32) usize {
    return BUF_OFFSET + pair * ring.FRAMES + start;
}

/// Every XM Paula channel's volume: 240/256, louder than a MOD's full-scale
/// channel (mod.chipVolume(64) = 1/1.4) by x1.3125, +2.4 dB. The voices already
/// share a channel attenuated (xm_mix.zig's SCALE_*), so MOD's 1/1.4 headroom left
/// XMs quiet (Matt, on the board). Measured over whole songs through demo-audio,
/// L and R: Keygen 9000 peaks 0.754 at 1/1.4, so x1.4 (volume 1.0) would clip at
/// 1.056; here it peaks 0.990. Poppy Flower Girls 0.504 -> 0.662. A multiple of
/// 1/256, the audio core's VOLUME grid (fpga/host/audio_regs.h), so the board
/// plays the browser's level exactly.
pub const VOLUME: f32 = 240.0 / 256.0;

/// The Paula channels for XM: one source frame per output frame (step 1.0), at VOLUME.
pub fn setup() void {
    for (0..audio.NUM_CHANNELS) |ch| {
        audio.machinePaulaSetStep(@intCast(ch), 1 << 16);
        audio.machinePaulaSetVolume(@intCast(ch), VOLUME);
    }
}

/// Mix `block` frames of every Paula channel's voices onto the bus at `off`.
pub fn mixBlock(p: *XmPlayer, off: u32, block: u32) void {
    const g = groupingOf(p.hdr.channels);
    const start = ring.place(p.ring_pos, block);
    p.ring_pos = start + block;
    for (0..audio.NUM_CHANNELS) |pair| {
        const at = ringOffset(pair, start);
        const buf = @as([*]i8, @ptrFromInt(audio.SONG_BASE + at))[0..block];
        @memset(buf, 0);
        mixPair(p, pair, g, buf);
        audio.machinePaulaTrigger(@intCast(pair), audio.songAddr(at), block, 0, 0, mod.pan(pair));
    }
    audio.machineMixPaula(off, block);
}

/// The voices of Paula channel `pair` (voices pair*per .. pair*per+per-1, those
/// the song has) added into `buf`.
fn mixPair(p: *XmPlayer, pair: usize, g: Grouping, buf: []i8) void {
    for (0..g.per) |k| {
        const v = pair * g.per + k;
        if (v >= p.hdr.channels) break;
        const c = &p.chan[v];
        if (!c.mix.active) continue;
        const s = &p.tabs.samps[c.mix.sample];
        xmix.mixVoice(&c.mix, sampleFrames(p, s), s, buf, g.scale);
    }
}

/// A sample's decoded frames, in the song image.
fn sampleFrames(p: *const XmPlayer, s: *const inst.Sample) []const i8 {
    const bytes = p.data[s.off..][0..s.len];
    return @as([*]const i8, @ptrCast(bytes.ptr))[0..s.len];
}
