//! MOCK: the music stream and its sample counter. The real one (ANALYSIS.md §7
//! (3), audio.zig) streams ADPCM or 8-bit PCM from the disk into audioFeed,
//! reads the ring's fill from the host, and re-seeks the stream on a clock
//! discontinuity (TBL's streamWaveNudge).
//!
//! This mock plays no sound. A frame advances the sample position by exactly
//! rate/60 on average, so the clock can be tested to the millisecond, and seekMs
//! moves the position as the real re-seek would.

const clock = @import("clock.zig");

pub const Music = struct {
    rate: u32 = 44100,
    /// 60 Hz frames played so far.
    frames: u32 = 0,

    /// One 60 Hz frame of playback.
    pub fn frame(self: *Music) void {
        self.frames +%= 1;
    }

    /// The sample position: floor(frames * rate / 60).
    pub fn position(self: *const Music) u32 {
        return @truncate(@as(u64, self.frames) * self.rate / 60);
    }

    /// Re-seeks the stream to `ms`, the mock's version of the real re-seek.
    pub fn seekMs(self: *Music, ms: u32) void {
        self.frames = @truncate(@as(u64, ms) * 60 / 1000);
    }

    /// The clock's source for this stream: the sound's real position, with no ring fill.
    pub fn source(self: *const Music) clock.Source {
        return .{ .samples = .{ .rate = self.rate, .fed = self.position(), .fill = 0 } };
    }
};
