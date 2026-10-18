// --------------------------------------------------------------------------
// ST Replay — the replay itself, through either of the machine's two outputs
// (the panel's "Alt = ALTernate O/P", shown in the status strip):
//
//   INTERNAL  the cart CPU plays the sample: every frame it hands the speaker
//             the next slice of the sample, paced by the frame's real time, as
//             the real ST Replay's 68000 fed the sound hardware sample by sample.
//             zg.audioStreamStart / audioFeed: the 32 KiB stream ring.
//   EXTERNAL  the sample hardware plays it: the whole sample goes over once
//             (zg.samplePlay) and the audio side plays it on its own, looping or
//             to its end: the sound CPU (BARD) on the board, the audio thread in
//             the browser. The cart only follows it with the playhead.
//
// Both keep the playhead on the same clock, in integers: the cart CPU has no
// FPU, so no float in the per-frame path but dt's own conversion (the host
// hands it over as f32). The clock is the host's microseconds when it has one
// (env.hostMicros): the speaker plays in real time, and on the board dt is a
// constant 16.6 ms while ST Replay draws at ~15 fps, so a feed paced by dt
// would hand over a quarter of what the ring plays. A host without the clock
// answers 0 (scene_hash.mjs, the native host, the harnesses): dt paces it, and
// the frames stay deterministic. decisions.md 2026-10-17.
// --------------------------------------------------------------------------
const zg = @import("zigos");

extern fn hostMicros() u32;

pub const Output = enum { internal, external };

const RING: usize = 32768; // the audio ring (STREAM_RING in demo_audio_main.zig)
const US: u64 = 1_000_000;

pub const Replay = struct {
    out: Output = .internal,
    /// The output sounding now, if any: stop() silences that one, whatever
    /// `out` was switched to since.
    live: ?Output = null,
    playing: bool = false,
    pos: usize = 0, // how far into the sample the replay is (bytes)
    owed: u64 = 0, // rate x microseconds not yet a whole byte
    hz: u32 = 0,
    tail: usize = 0, // INTERNAL after a one-shot's end: silence still draining
    looped: bool = false, // the loop flag an EXTERNAL sample was started with
    last_us: u32 = 0, // hostMicros() at the last tick, 0 = no clock (dt paces)

    /// Start `pcm` at `hz` from its first byte. INTERNAL feeds an eighth of a
    /// second at once, so a late frame never starves the ring.
    pub fn start(self: *Replay, pcm: []const u8, hz: u32, loop: bool) void {
        self.stop();
        self.hz = hz;
        self.pos = 0;
        self.owed = 0;
        self.tail = 0;
        self.last_us = hostMicros();
        self.playing = true;
        self.live = self.out;
        switch (self.out) {
            .internal => {
                zg.audioStreamStart(@floatFromInt(hz));
                const pre = @min(hz / 8, pcm.len);
                zg.audioFeed(pcm[0..pre]);
                self.pos = pre;
            },
            .external => {
                self.looped = loop;
                _ = zg.samplePlay(pcm, hz, loop);
            },
        }
    }

    pub fn stop(self: *Replay) void {
        if (self.live) |o| switch (o) {
            .internal => zg.audioStreamStop(),
            .external => _ = zg.sampleStop(),
        };
        self.live = null;
        self.playing = false;
        self.tail = 0;
    }

    /// Whole bytes the time since the last tick is worth at the replay rate:
    /// the host's clock if it has one, else the frame's `dt` (ms).
    fn bytesFor(self: *Replay, dt: f32) usize {
        const now = hostMicros();
        const us: u64 = if (now != 0 and self.last_us != 0)
            now -% self.last_us
        else if (dt > 0)
            @intFromFloat(@min(dt, 600_000.0) * 1000.0)
        else
            0;
        self.last_us = now;
        self.owed += us * self.hz;
        const n = self.owed / US;
        self.owed %= US;
        return @intCast(n);
    }

    /// One frame. `buf` is the sample's whole buffer, `len` the sample in it:
    /// the bytes after it are silence, which INTERNAL drains its prefill with.
    pub fn tick(self: *Replay, buf: []const u8, len: usize, dt: f32, loop: bool) void {
        if (self.live == null) return;
        const n = self.bytesFor(dt);
        if (!self.playing) return self.drain(n);
        switch (self.live.?) {
            .internal => self.feed(buf[0..len], n, loop),
            .external => self.follow(buf[0..len], n, loop),
        }
        if (self.playing or self.live != .internal) return;
        // The one-shot is fed to its end: what is still in the ring plays, then silence.
        self.tail = @min(self.hz / 8 + self.hz / 15, buf.len - len);
        zg.audioFeed(buf[len .. len + self.tail]);
    }

    // INTERNAL: hand the speaker this frame's slice. Whole rings of backlog (a
    // hidden tab) would only lap the ring onto itself: skip them in the sample.
    fn feed(self: *Replay, pcm: []const u8, n: usize, loop: bool) void {
        var left = n % RING;
        self.advance(pcm.len, n - left, loop);
        while (left > 0 and self.playing) {
            const k = @min(left, pcm.len - self.pos);
            zg.audioFeed(pcm[self.pos .. self.pos + k]);
            left -= k;
            self.advance(pcm.len, k, loop);
        }
    }

    // EXTERNAL: the audio side plays; follow it. Loop mode switched on since the
    // start restarts it, looped, at its end; switched off, the end stops it (drain).
    fn follow(self: *Replay, pcm: []const u8, n: usize, loop: bool) void {
        self.advance(pcm.len, n, loop and self.looped);
        if (!self.playing and loop) self.start(pcm, self.hz, true);
    }

    // Move the playhead on by `n`: wrap when looping, else stop at the end.
    fn advance(self: *Replay, len: usize, n: usize, loop: bool) void {
        if (len == 0) return;
        if (self.pos + n < len) {
            self.pos += n;
        } else if (loop) {
            self.pos = (self.pos + n) % len;
        } else {
            self.pos = len;
            self.playing = false;
        }
    }

    // After an INTERNAL one-shot: the silence fed behind it plays out, then stop.
    // An EXTERNAL one ends by itself on the audio side.
    fn drain(self: *Replay, n: usize) void {
        if (self.live == .external or n >= self.tail) return self.stop();
        self.tail -= n;
    }
};
