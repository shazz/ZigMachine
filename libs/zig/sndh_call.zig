// --------------------------------------------------------------------------
// zg.sndhCall -- run INIT again on the SNDH that is ALREADY playing.
//
// A song request (zg.requestSongTune) is a LOAD: the host fetches the file,
// the SNDH player zeroes the 68000's RAM around the image, silences the YM,
// resets the MFP and runs INIT. Right for a new tune, wrong for a game's sound
// effect: it cuts every voice, envelope and digi still sounding, where the
// original's driver lets them finish. A call instead runs INIT(d0) as a
// subroutine on the running image, nothing reloaded, nothing reset; the image
// decides what d0 means (Rick Dangerous's sound.s: bit 15 = "resident").
//
// Calls are QUEUED, in order, per host frame: a game that plays two sounds in
// one frame (Rick's shot: play(8,1) then play(8,0)) gets both. The host drains
// the queue once a frame (pollSndhCalls, apps/zig/demo_main.zig), AFTER the
// frame's song request, so the rule that keeps the two in order is here:
//   - a song request or a stop DISCARDS the queued calls: it reloads or stops
//     the image, which is exactly what those calls ran on;
//   - a call naming another image than the queued ones starts a new queue, for
//     the same reason (the host loads the new image before calling it).
// If `name` is not the image the host has playing, the host loads it and the
// call's d0 is its first INIT (unclamped), so the image must accept its own
// "resident" d0 on a fresh load (sound.s checks an `installed` flag).
//
// Generic over nothing: plain state, tested natively (sndh_call_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

/// Calls one host frame can carry. A game's frame makes a handful at most.
pub const CAP: usize = 16;
/// The song bridge's own name capacity (zigos.zig g_song_name).
pub const NAME_MAX: usize = 64;

pub const Queue = struct {
    name: [NAME_MAX]u8 = [_]u8{0} ** NAME_MAX,
    name_len: usize = 0,
    d0: [CAP]u32 = [_]u32{0} ** CAP,
    n: usize = 0,
    /// Calls refused since the cart started: the queue was full, or the name
    /// was empty or longer than NAME_MAX. Never absorbed silently.
    dropped: u32 = 0,

    /// Queue INIT(d0) on the running `name`. False (and counted) if refused.
    pub fn push(self: *Queue, name: []const u8, d0: u32) bool {
        if (name.len == 0 or name.len > NAME_MAX) return self.refuse();
        if (self.n != 0 and !std.mem.eql(u8, name, self.name[0..self.name_len])) self.n = 0;
        if (self.n == CAP) return self.refuse();
        if (self.n == 0) {
            @memcpy(self.name[0..name.len], name);
            self.name_len = name.len;
        }
        self.d0[self.n] = d0;
        self.n += 1;
        return true;
    }

    /// A song request or a stop superseded whatever was queued.
    pub fn clear(self: *Queue) void {
        self.n = 0;
    }

    /// The host takes the frame's calls: how many, then d0At(i) for each. The
    /// entries stay readable until the next push.
    pub fn take(self: *Queue) usize {
        const n = self.n;
        self.n = 0;
        return n;
    }

    pub fn d0At(self: *const Queue, i: usize) u32 {
        return if (i < CAP) self.d0[i] else 0;
    }

    fn refuse(self: *Queue) bool {
        self.dropped +%= 1;
        return false;
    }
};
