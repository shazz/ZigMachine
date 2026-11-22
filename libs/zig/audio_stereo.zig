//! The stereo PCM stream and the stream's sample counter (system table 1.27, docs/project/DECISIONS.md
//! 2026-11-20, docs/guide/ZIGOS_API.md "Streaming audio"). zigos re-exports these as
//! zg.audioStreamStartStereo / zg.audioFeedStereo / zg.audioStreamPlayed.
//!
//! The mono stream (zg.audioStreamStart / audioFeed) loops ONE signed-8-bit ring on Paula channel
//! 0, centred. The stereo stream loops two rings of the same size (32 KiB a side) on channels 0
//! and 1, panned hard left and hard right, started on the same sample with the same step. The
//! cart feeds interleaved frames, L then R, signed 8-bit: the layout of a stereo WAV's data and of
//! a decoder's output, and one pointer, so the feed is one call that cannot leave a side behind.
//! zg.audioStreamStop stops either stream.

extern fn hostAudioStreamStartStereo(rate: u32) void; // two rings, channels 0 (left) and 1 (right)
extern fn hostAudioFeedStereo(ptr: u32, len: u32) void; // append interleaved L,R s8 frames
extern fn hostAudioStreamPlayed() u32; // samples the stream channel has read since its start

/// The bytes a ring holds a side (demo_audio_main.zig STREAM_RING): keep what was fed minus
/// audioStreamPlayed() under this, or the feed overwrites what has not played yet.
pub const RING: u32 = 32768;

/// Start the stereo stream at `rate` Hz (1000..50066; outside it nothing starts and
/// audioStreamPlayed() stays 0). It replaces a mono stream, a sample or a song playing.
pub fn startStereo(rate: u32) void {
    hostAudioStreamStartStereo(rate);
}

/// Append `frames` interleaved stereo frames: byte 2i is frame i's left sample, 2i + 1 its right.
/// An odd trailing byte (half a frame) is not fed.
pub fn feedStereo(frames: []const u8) void {
    const n = frames.len & ~@as(usize, 1);
    if (n == 0) return;
    hostAudioFeedStereo(@intCast(@intFromPtr(frames.ptr)), @intCast(n));
}

/// Samples (frames, for a stereo stream) the stream has played since its start, mono or stereo,
/// wrapping at 2^32; 0 when no stream plays or the host has no sound (a stub, a sim, the page
/// before its sound is on). The sound's own clock: what a demo's timeline follows
/// (libs/zig/zigdemo/clock.zig: .samples = .{ .rate, .fed = played, .fill = 0 }). Rendered, not heard: the
/// board renders a lead (about 67 ms) ahead of the speaker, the page one output buffer.
pub fn played() u32 {
    return hostAudioStreamPlayed();
}
