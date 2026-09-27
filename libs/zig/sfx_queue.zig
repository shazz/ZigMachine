// --------------------------------------------------------------------------
// zg.sfxPlay / zg.sfxStop / zg.ymWrite -- a game's sound effects OVER a MOD.
//
// The audio module plays one song at a time. An SNDH carries its own effect
// code (zg.sndhCall), a MOD does not: so a cart playing a MOD hands the host
// its effects as commands, and the audio thread plays each one on the song's
// quietest Paula channel (libs/zig/players/sfx_voice.zig), or writes the YM,
// which a MOD leaves idle (an engine note under the music).
//
// The commands are QUEUED per host frame, in order, like zg.sndhCall's. The
// host drains them after the frame's song request (pollSfx / sfxEntriesPtr in
// apps/zig/demo_main.zig) and posts them to the worklet in that order, after
// the load of any song still being fetched: an effect never lands on the song
// it was not meant for. A play command carries a POINTER into the cart's
// memory: the host copies the bytes when it drains the queue, so they must
// stay put until then (an @embedFile does).
//
// Each entry is 16 bytes, little-endian (the host reads them with a DataView):
//   0 op    1 play, 2 stop, 3 ym
//   1 a     play: 1 = looped; stop: 1 = only a looped effect; ym: register
//   2 b     ym: the value
//   3 -     0
//   4 ptr   play: the PCM (signed 8-bit), a cart address
//   8 len   play: its length in bytes
//   12 rate play: the sample rate in Hz
//
// Generic over nothing: plain state, tested natively (sfx_queue_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

/// Commands one host frame can carry: an engine note is ~14 YM writes.
pub const CAP: usize = 32;
/// The largest effect the audio thread takes (sfx_voice.CAP).
pub const PCM_MAX: usize = 64 * 1024;
pub const RATE_MIN: u32 = 1000;
pub const RATE_MAX: u32 = 50066;

pub const Op = enum(u8) { play = 1, stop = 2, ym = 3 };

pub const Entry = extern struct {
    op: u8,
    a: u8 = 0,
    b: u8 = 0,
    pad: u8 = 0,
    ptr: u32 = 0,
    len: u32 = 0,
    rate: u32 = 0,
};
comptime {
    std.debug.assert(@sizeOf(Entry) == 16);
}

pub const Queue = struct {
    entries: [CAP]Entry = undefined,
    n: usize = 0,
    /// Commands refused since the cart started: the queue was full, or the
    /// PCM empty / too long, the rate or the register out of range.
    dropped: u32 = 0,

    pub fn play(self: *Queue, pcm: []const u8, rate: u32, loop: bool) bool {
        if (pcm.len == 0 or pcm.len > PCM_MAX or rate < RATE_MIN or rate > RATE_MAX) return self.refuse();
        return self.push(.{
            .op = @intFromEnum(Op.play),
            .a = @intFromBool(loop),
            .ptr = @truncate(@intFromPtr(pcm.ptr)), // wasm32: exact; native tests: low half
            .len = @intCast(pcm.len),
            .rate = rate,
        });
    }

    pub fn stop(self: *Queue, loop_only: bool) bool {
        return self.push(.{ .op = @intFromEnum(Op.stop), .a = @intFromBool(loop_only) });
    }

    pub fn ym(self: *Queue, reg: u8, val: u8) bool {
        if (reg > 13) return self.refuse();
        return self.push(.{ .op = @intFromEnum(Op.ym), .a = reg, .b = val });
    }

    /// The host takes the frame's commands: how many, then entries[0..n].
    pub fn take(self: *Queue) usize {
        const n = self.n;
        self.n = 0;
        return n;
    }

    fn push(self: *Queue, e: Entry) bool {
        if (self.n == CAP) return self.refuse();
        self.entries[self.n] = e;
        self.n += 1;
        return true;
    }

    fn refuse(self: *Queue) bool {
        self.dropped +%= 1;
        return false;
    }
};
