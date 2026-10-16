// --------------------------------------------------------------------------
// The XM player's chip side: the eight voices mixed two to a Paula channel.
// Each block (a span of one tick, or part of it) the four pair buffers are
// rebuilt from the voices (xm_mix.zig) and each Paula channel plays its buffer
// ONCE at one source frame per output frame: a re-trigger every block, so the
// chip reads exactly the block just written. The channels' step and volume
// are set once at start (setup); only the trigger, which holds the pan, runs
// per block. The pair buffers are static, in the demo-audio module's memory,
// which the sealed chip shares.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const mod = @import("mod.zig");
const xmix = @import("xm_mix.zig");
const inst = @import("xm_instr.zig");
const XmPlayer = @import("xm.zig").XmPlayer;

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

/// Mix `block` frames of every pair onto the bus at `off`.
pub fn mixBlock(p: *XmPlayer, off: u32, block: u32) void {
    for (0..audio.NUM_CHANNELS) |pair| {
        const buf = pairBuf(pair, block);
        @memset(buf, 0);
        mixPair(p, pair, buf);
        audio.machinePaulaTrigger(@intCast(pair), audio.songAddr(BUF_OFFSET + pair * audio.MAX_FRAMES), block, 0, 0, mod.pan(pair));
    }
    audio.machineMixPaula(off, block);
}

/// Voices 2*pair and 2*pair+1 (those the song has) added into `buf`.
fn mixPair(p: *XmPlayer, pair: usize, buf: []i8) void {
    for (0..2) |k| {
        const v = 2 * pair + k;
        if (v >= p.hdr.channels) break;
        const c = &p.chan[v];
        if (!c.mix.active) continue;
        const s = &p.tabs.samps[c.mix.sample];
        xmix.mixVoice(&c.mix, sampleFrames(p, s), s, buf);
    }
}

/// A sample's decoded frames, in the song image.
fn sampleFrames(p: *const XmPlayer, s: *const inst.Sample) []const i8 {
    const bytes = p.data[s.off..][0..s.len];
    return @as([*]const i8, @ptrCast(bytes.ptr))[0..s.len];
}
