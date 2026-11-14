//! zigdemo clock: the demo's master time in ms (u32) and its 60 Hz frame index.
//!
//! The clock does not count frames. Each frame the cart passes the reading of
//! its source (the sound's sample position, the song's ms, or the VBL count) and
//! the clock follows the source's deltas. The music is the master, so the
//! picture cannot drift from the sound. TBL kept an RTC instead and nudged the
//! audio after each jump (prototypes/suicide_barbie_re/ANALYSIS.md §7 (1)).
//!
//! Sums wrap at 2^32: t = source +% offset, so a source that wraps (49.7 days
//! of ms, or a sample counter) keeps the time going.

const std = @import("std");

pub const Source = union(enum) {
    /// The sound's real position: samples fed to the ring minus what the ring
    /// still holds. Both counters wrap at 2^32 (27 hours at 44.1 kHz).
    samples: struct { rate: u32, fed: u32, fill: u32 },
    /// The song's position in ms (zigos.song_ms).
    song_ms: u32,
    /// The VBL count at `hz` (50 or 60), for a screen with no music.
    vbl: struct { count: u32, hz: u32 },
};

/// TBL's from/to keys: playback that reaches `b` goes back to `a`.
pub const Loop = struct { a: u32, b: u32 };

/// Sees every seek. The clock counts its discontinuities in `seq` rather than
/// holding a flag, so the audio side and the demo can each read every seek
/// (TBL's getDiscontinuity() was consumed by its one reader).
pub const Reader = struct {
    seen: u32 = 0,

    pub fn changed(self: *Reader, clk: *const Clock) bool {
        if (clk.seq == self.seen) return false;
        self.seen = clk.seq;
        return true;
    }
};

pub const Clock = struct {
    /// Now, in ms.
    t: u32 = 0,
    /// t - source ms, wrapping. Between updates this is what carries t forward.
    offset: u32 = 0,
    /// The last source reading, in ms.
    src: u32 = 0,
    paused: bool = false,
    loop: ?Loop = null,
    /// Discontinuities so far (a jump or a loop wrap). See Reader.
    seq: u32 = 0,
    tag: ?std.meta.Tag(Source) = null,
    /// Whether the previous update was paused. The frame that resumes
    /// re-anchors too, so the paused time is not counted as playback.
    held: bool = false,
    /// Set by a seek: the next update re-anchors, so the seek's time is shown
    /// on that frame. The cart re-seeks the sound first (see Reader), so the
    /// source reads the new time then; a source that was not re-seeked is
    /// still anchored at the seek's time, not counted twice.
    rebase: bool = false,

    pub fn update(self: *Clock, source: Source) void {
        const s = sourceMs(source);
        const tag = std.meta.activeTag(source);
        // Time stands still while paused, after a seek, and when the time base
        // changes: the offset is re-anchored there, so playback resumes from t.
        const hold = self.paused or self.held or self.rebase or self.tag != tag;
        self.tag = tag;
        self.held = self.paused;
        self.rebase = false;
        self.src = s;
        if (hold) {
            self.offset = self.t -% s;
            return;
        }
        const prev = self.t;
        self.t = s +% self.offset;
        if (self.loop) |lp| {
            if (crossed(prev, self.t, lp.b)) self.seekTo(lp.a);
        }
    }

    /// A seek: t goes to `ms` now, and playback follows the source from there.
    pub fn jump(self: *Clock, ms: u32) void {
        self.seekTo(ms);
    }

    pub fn setPaused(self: *Clock, flag: bool) void {
        self.paused = flag;
    }

    pub fn setLoop(self: *Clock, a: u32, b: u32) void {
        std.debug.assert(a < b);
        self.loop = .{ .a = a, .b = b };
    }

    pub fn clearLoop(self: *Clock) void {
        self.loop = null;
    }

    /// The 60 Hz frame index of t.
    pub fn frame(self: *const Clock) u32 {
        return @truncate(@as(u64, self.t) * 60 / 1000);
    }

    fn seekTo(self: *Clock, ms: u32) void {
        self.t = ms;
        self.offset = ms -% self.src;
        self.rebase = true;
        self.seq +%= 1;
    }
};

/// Did playback move forward past `b` (prev < b <= now)? Wrap-safe: a backward
/// move (a span of half the u32 range or more) never counts.
fn crossed(prev: u32, now: u32, b: u32) bool {
    const half: u32 = 1 << 31;
    const span = now -% prev;
    const to_b = b -% prev;
    return to_b != 0 and to_b <= span and span < half;
}

fn sourceMs(source: Source) u32 {
    return switch (source) {
        .samples => |p| blk: {
            std.debug.assert(p.rate != 0);
            const pos: u64 = p.fed -% p.fill;
            break :blk @truncate(pos * 1000 / p.rate);
        },
        .song_ms => |ms| ms,
        .vbl => |v| blk: {
            std.debug.assert(v.hz != 0);
            break :blk @truncate(@as(u64, v.count) * 1000 / v.hz);
        },
    };
}
