// --------------------------------------------------------------------------
// The XM player's chip side: the voices mixed onto the Paula channels, two to a
// channel for a song of 8 or fewer channels (the original pairing, bit for bit)
// and three to a channel for 9..12 channels. The channel count fixes the group
// size and so the attenuation (xm_mix.zig's SCALE_*), once per song.
// Each block (a span of one tick, or part of it) the four channel buffers are
// rebuilt from the voices and each Paula channel plays its buffer
// ONCE at one source frame per output frame: a re-trigger every block, so the
// chip reads exactly the block just written. The channels' step and volume
// are set once at start (setup); only the trigger, which holds the pan, runs
// per block. The channel buffers are static, in the demo-audio module's memory,
// which the sealed chip shares.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const mod = @import("mod.zig");
const xmix = @import("xm_mix.zig");
const inst = @import("xm_instr.zig");
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

/// The four pair buffers sit at the top of song RAM, past the largest song that
/// fits beside them: a static buffer would be 16 KB of zeros in demo-audio's data
/// segment (zero_segments). A song longer than BUF_OFFSET is refused at load.
pub const BUF_OFFSET: usize = audio.SONG_CAP - audio.NUM_CHANNELS * audio.MAX_FRAMES;

fn pairBuf(pair: usize, block: u32) []i8 {
    const p: [*]i8 = @ptrFromInt(audio.SONG_BASE + BUF_OFFSET + pair * audio.MAX_FRAMES);
    return p[0..block];
}

/// The Paula channels for XM: one source frame per output frame (step 1.0), and
/// the volume mod.zig gives a full-scale channel (HEADROOM included).
pub fn setup() void {
    for (0..audio.NUM_CHANNELS) |ch| {
        audio.machinePaulaSetStep(@intCast(ch), 1 << 16);
        audio.machinePaulaSetVolume(@intCast(ch), mod.chipVolume(64));
    }
}

/// Mix `block` frames of every Paula channel's voices onto the bus at `off`.
pub fn mixBlock(p: *XmPlayer, off: u32, block: u32) void {
    const g = groupingOf(p.hdr.channels);
    for (0..audio.NUM_CHANNELS) |pair| {
        const buf = pairBuf(pair, block);
        @memset(buf, 0);
        mixPair(p, pair, g, buf);
        audio.machinePaulaTrigger(@intCast(pair), audio.songAddr(BUF_OFFSET + pair * audio.MAX_FRAMES), block, 0, 0, mod.pan(pair));
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
