//! zigdemo mp3 stream: one MP3 file fed to the host's player a chunk at a time, its position
//! read back as the clock's source, and a seek by byte offset. mp3.zig has the contract.

const std = @import("std");
const clock = @import("clock.zig");
const mp3 = @import("mp3.zig");

pub fn Music(comptime Host: type, comptime Input: type) type {
    return struct {
        const Self = @This();

        cfg: mp3.Config = .{},
        input: *const Input,
        buf: []u8, // one chunk of the file (<= cfg.feed_max is fed at a time)
        fmt: mp3.Format = undefined,
        first: u32 = 0, // the first frame's offset (after the ID3 tag)
        cur: u32 = 0, // the file offset of buf[0]
        have: u32 = 0, // bytes in buf
        sent: u32 = 0, // of them fed
        fed: u32 = 0, // bytes fed since the start (wraps)
        base: u32 = 0, // samples before the stream's first frame (a seek's)
        age: u32 = 0, // frames since the start
        zero: u32 = 0, // frames of a live stream with a zero state word
        live: bool = false,
        ended: bool = false,
        no_player: bool = false,
        paused: bool = false,

        /// Reads the file's first chunk and finds its format; false if it is no MP3.
        pub fn open(self: *Self) bool {
            self.have = self.input.read(0, self.buf);
            const head = self.buf[0..self.have];
            const s = mp3.syncFrom(head, mp3.id3Size(head)) orelse return false;
            self.fmt = s.fmt;
            self.first = s.at;
            return true;
        }

        /// Starts the stream at `ms` (0: the file's start, ID3 tag and all).
        pub fn seekMs(self: *Self, ms: u32) void {
            const at = if (ms == 0) @as(u32, 0) else self.frameAt(ms);
            if (self.live) Host.ctl(.stop, 0);
            self.cur = at;
            self.have = self.input.read(at, self.buf);
            self.sent = 0;
            self.fed = 0;
            self.age = 0;
            self.zero = 0;
            self.ended = false;
            self.live = true;
            self.base = if (at <= self.first) 0 else @intCast(@as(u64, at - self.first) * 8 * self.fmt.rate / (@as(u64, self.fmt.kbps) * 1000));
            self.base = self.base / self.fmt.spf * self.fmt.spf; // a whole frame
            Host.ctl(.start, 0);
            if (self.paused) Host.ctl(.pause, 1);
        }

        /// Stops the player (a mute): the source falls back to the VBL until the next seek.
        pub fn stop(self: *Self) void {
            if (self.live) Host.ctl(.stop, 0);
            self.live = false;
        }

        pub fn setPaused(self: *Self, on: bool) void {
            self.paused = on;
            if (self.live) Host.ctl(.pause, @intFromBool(on));
        }

        /// The byte offset of the frame `ms` falls in: the CBR estimate, then the next sync.
        fn frameAt(self: *Self, ms: u32) u32 {
            const est: u64 = self.first + @as(u64, ms) * self.fmt.kbps / 8;
            if (est >= self.input.len()) return self.input.len();
            const at: u32 = @intCast(est);
            const n = self.input.read(at, self.buf);
            const s = mp3.syncFrom(self.buf[0..n], 0) orelse return at;
            return at + s.at;
        }

        /// Once a frame: feed what fits in the player's ring, read the next chunk when spent.
        pub fn pump(self: *Self) void {
            if (!self.live) return;
            self.age +|= 1;
            self.watch();
            if (self.sent < self.have) {
                const n = @min(self.have - self.sent, self.room(), self.cfg.feed_max);
                if (n == 0) return;
                Host.feed(self.buf[self.sent .. self.sent + n]);
                self.sent += n;
                self.fed +%= n;
            } else if (self.have != 0) {
                self.cur += self.have;
                self.have = self.input.read(self.cur, self.buf);
                self.sent = 0;
            } else if (!self.ended) {
                Host.ctl(.end, 0); // all fed: the player plays out what it holds
                self.ended = true;
            }
        }

        /// A live stream whose state stays 0 has no player behind it (a harness's host).
        fn watch(self: *Self) void {
            if (self.age <= self.cfg.trust or self.no_player) return;
            if (Host.status(.word) & 3 != 0) {
                self.zero = 0;
                return;
            }
            self.zero += 1;
            if (self.zero >= self.cfg.no_player) self.no_player = true;
        }

        /// Bytes the ring can take now: what was fed minus what the player took.
        fn room(self: *const Self) u32 {
            const used: u32 = if (self.age <= self.cfg.trust) 0 else Host.status(.used);
            const fill = self.fed -% used;
            if (fill > self.cfg.ring) return self.cfg.ring - @min(self.fed, self.cfg.ring);
            return self.cfg.ring - fill;
        }

        /// The ring is full enough to start without an underrun (or the file is all fed).
        pub fn primed(self: *const Self) bool {
            return self.fed >= self.cfg.ring / 2 or (self.have == 0 and self.live);
        }

        /// Samples decoded since the file's start.
        pub fn position(self: *const Self) u32 {
            if (self.age <= self.cfg.trust) return self.base;
            return self.base +% Host.status(.frames) *% self.fmt.spf;
        }

        /// The music's position while a player plays it, else the VBL at 60 Hz.
        pub fn source(self: *const Self, vbl: u32) clock.Source {
            if (!self.live or self.no_player) return .{ .vbl = .{ .count = vbl, .hz = 60 } };
            return .{ .samples = .{ .rate = self.fmt.rate, .fed = self.position(), .fill = self.cfg.fill } };
        }

        /// The player ran out of input and played it all.
        pub fn done(self: *const Self) bool {
            return self.ended and self.age > self.cfg.trust and Host.status(.word) & 3 == 3;
        }

        /// The sound CPU's load, per mille (0 where none is measured).
        pub fn load(_: *const Self) u32 {
            return Host.status(.load);
        }
    };
}

comptime {
    std.debug.assert(@intFromEnum(mp3.Op.end) == 3 and @intFromEnum(mp3.Stat.load) == 3);
}
