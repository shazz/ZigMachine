// --------------------------------------------------------------------------
// demo-audio.wasm: the raw 8-bit sample players, the simplest on the Paula
// primitive -- a whole sample looped on channel 0, or a ring the host keeps
// refilling ahead of the read cursor. Split from demo_audio_main.zig, whose
// players and mode they share.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const m = @import("root");

// --- a whole sample, looped ---
export fn audioPlayRaw(len: u32, rate: f32, is_unsigned: bool) void {
    stopPlayers();
    stream_step = 0; // a whole sample is not a stream: no counter
    stream_stereo = false;

    const n: usize = @intCast(len);
    if (is_unsigned) {
        const buf: [*]u8 = @ptrFromInt(audio.SONG_BASE);
        for (buf[0..n]) |*b| b.* ^= 0x80; // unsigned -> signed
    }
    // Play on channel 0, looped, silence the rest.
    silenceAllBut0();
    audio.machinePaulaTrigger(0, audio.songAddr(0), len, 0, len, 0.0);
    audio.machinePaulaSetStep(0, @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE));
    audio.machinePaulaSetVolume(0, 0.9);
    m.current_mode = 3;
}

// Silence the stream. The ring is a LOOPING Paula channel, so it keeps replaying
// whatever it holds until the channel is switched off — draining is not something
// it does on its own.
export fn audioStreamStop() void {
    audio.machinePaulaSetActive(0, 0);
    audio.machinePaulaSetVolume(0, 0.0);
    if (stream_stereo) {
        audio.machinePaulaSetActive(1, 0);
        audio.machinePaulaSetVolume(1, 0.0);
    }
    @memset(rings(stream_stereo), 0);
    stream_step = 0;
    stream_stereo = false;
    audio.machinePaulaClearScopes();
    m.current_mode = 0;
}

// --- streaming raw sample (Amiga-style refill-ahead ring) ---
// A Paula channel loops forever over a fixed ring at the start of song RAM; the
// host keeps writing fresh signed-8-bit samples ahead of the read cursor, paced
// to the play rate, so samples far larger than SONG_CAP can play.
const STREAM_RING = m.STREAM_RING; // at SONG_BASE

export fn audioStreamStart(rate: f32) void {
    stopPlayers();
    // Zero the ring so an under-fed start is silence, not garbage (both, if a stereo stream ran).
    @memset(rings(stream_stereo), 0);
    stream_stereo = false;
    silenceAllBut0();
    const step: u32 = @intFromFloat(rate / audio.SAMPLE_RATE * audio.FRAC_ONE);
    loopRing(0, 0, step, 0.0); // centre: both sides
    startCounter(step);
}

// --- the stereo stream (system table 1.27, decisions.md 2026-11-20) ---
// Two rings of STREAM_RING bytes: the left at SONG_BASE on channel 0 panned hard left, the right
// right after it on channel 1 panned hard right, both triggered here with the same step, so the
// two channels read the same offset on every sample. The host deinterleaves a feed's L,R pairs
// into them at one cursor. A rate outside 1000..50066 Hz (samplePlay's range) starts nothing.
export fn audioStreamStartStereo(rate: u32) void {
    stopPlayers();
    @memset(rings(true), 0);
    for (2..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    if (rate < 1000 or rate > 50066) {
        stream_stereo = false;
        stream_step = 0;
        audio.machinePaulaSetActive(0, 0);
        audio.machinePaulaSetActive(1, 0);
        m.current_mode = 0;
        return;
    }
    stream_stereo = true;
    const step: u32 = @intCast((@as(u64, rate) << 16) / 44100);
    loopRing(0, 0, step, -1.0);
    loopRing(1, STREAM_RING, step, 1.0);
    startCounter(step);
}

/// Samples each stream channel has read since its start (wrapping u32), 0 with no stream: the
/// sound's own position for a cart's clock. Counted as the channel steps, rendered not heard
/// (the board renders a lead ahead of the speaker, the page an output buffer).
export fn audioStreamPlayed() u32 {
    if (stream_step == 0 or m.current_mode != 3) return 0;
    return @truncate(stream_pos >> 16);
}

/// audioRender's Paula path, after it mixed `n` samples.
pub fn streamAdvance(n: u32) void {
    if (stream_step != 0 and m.current_mode == 3) stream_pos +%= @as(u64, n) * stream_step;
}

var stream_step: u32 = 0; // the stream channel's 16.16 step, 0: no stream
var stream_pos: u64 = 0; // 16.16 samples read since the start
var stream_stereo: bool = false; // two rings (channels 0 and 1), else one

fn loopRing(ch: u32, off: u32, step: u32, pan: f32) void {
    audio.machinePaulaTrigger(ch, audio.songAddr(off), STREAM_RING, 0, STREAM_RING, pan); // loop the whole ring
    audio.machinePaulaSetStep(ch, step);
    audio.machinePaulaSetVolume(ch, 0.9);
}

fn startCounter(step: u32) void {
    stream_step = step;
    stream_pos = 0;
    m.current_mode = 3;
}

fn rings(stereo: bool) []u8 {
    const p: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    return p[0 .. if (stereo) 2 * STREAM_RING else STREAM_RING];
}

// Every sequencing player off before channel 0 takes over. The SNDH too: the sample was just
// staged over its 68000 image (song RAM), and left active it comes first in audioRender, so the
// sample never sounded while PLAY ran over the sample's bytes until RUNAWAY_CYCLES gave up (the
// Dyno scroller's 4 s whine, then silence, 2026-11-01). Abandoned, not stopped: EXIT would run
// over those bytes too. As the YM, MOD, XM, SAP and HIP loads do.
fn stopPlayers() void {
    if (m.sndh.active) m.sndh.abandon();
    m.mod.stop();
    m.xm.stop();
    m.kt_exports.kt.stop();
    m.mp3_exports.mp3.stop();
    m.sid_exports.sid.stop();
    m.vgm_exports.vgm.stop();
    m.ym.stop();
    m.sap_exports.sap.stop();
    m.hip_exports.hip.abandon();
    audio.machinePaulaClearScopes();
}

fn silenceAllBut0() void {
    for (1..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
}
