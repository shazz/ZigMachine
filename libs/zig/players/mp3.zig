// --------------------------------------------------------------------------
// The MP3 player (zg.mp3Ctl / mp3Feed / mp3Status, docs/ZIGOS_API.md): a
// cart streams an .mp3's bytes in, pvmp3 (libs/c/pvmp3, integer) decodes
// them, and the 16-bit PCM plays on the four Paula channels as kt.zig's:
// a high and a low byte a side. Two channels a side can only carry x >> 1
// exactly (a channel's gain tops out at half scale: fpga/tests/hilo_probe.py),
// so the hi byte plays at VOL 256 and the lo at VOL 2: 128 h + l = x >> 1,
// bit-exact on every host, 6 dB under full scale (no clean way to make it up:
// VOL is 9 bits, 512 does not exist). The four channels are the player's: no
// Paula sound effects while an MP3 plays.
//
// 44.1 kHz streams go out sample for sample (bit-exact against a host decode
// of the same bytes); 32 and 48 kHz are converted linearly (mp3_resample.zig),
// which is not. Song RAM: the input ring, the feed's staging, one frame, the
// decoded PCM, the decoder's state, then the Paula rings (xm_chip BUF_OFFSET).
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const ring = @import("xm_ring.zig");
const chip = @import("xm_chip.zig");
const in = @import("mp3_in.zig");
const rs = @import("mp3_resample.zig");
const out = @import("mp3_out.zig");

extern fn zm_mp3_state_size() u32;
extern fn zm_mp3_init(state: *anyopaque) void;
extern fn zm_mp3_decode(state: *anyopaque, src: [*]const u8, len: u32, pcm: [*]i16, info: *[2]u32) i32;

pub const IN_RING: u32 = 64 * 1024;
pub const STAGE_OFF: u32 = IN_RING; // a feed's bytes, before audioMp3Feed appends them
pub const STAGE: u32 = 32 * 1024;
const FRAME_OFF: u32 = STAGE_OFF + STAGE;
const PCM_OFF: u32 = FRAME_OFF + 2048;
const STATE_OFF: u32 = PCM_OFF + 2 * 1152 * 2 + 256;
const STATE_MAX: u32 = 48 * 1024;
comptime {
    if (STATE_OFF + STATE_MAX > chip.BUF_OFFSET) @compileError("the MP3 player's song RAM overlaps the Paula rings");
}

/// Ctl ops (zg.mp3Ctl).
pub const Op = enum(u32) { start = 0, stop = 1, pause = 2, end = 3 };
pub const State = enum(u32) { idle = 0, playing = 1, paused = 2, ended = 3 };

pub const Mp3Player = struct {
    active: bool = false,
    state: State = .idle,
    eof: bool = false,
    synced: bool = false,
    id3: u32 = 0, // tag bytes still to skip
    input: in.Ring = .{ .buf = &.{} },
    pcm: [*]i16 = undefined,
    pcm_n: u32 = 0, // samples a channel in pcm
    pcm_at: u32 = 0,
    rate: u32 = 0,
    stereo: bool = true,
    conv: ?rs.Linear = null,
    frames: u32 = 0, // decoded with PCM
    errors: u32 = 0,
    underruns: u32 = 0,
    ring_pos: u32 = 0,

    pub fn start(self: *Mp3Player) bool {
        self.* = .{};
        if (zm_mp3_state_size() > STATE_MAX) return false;
        const base: [*]u8 = @ptrFromInt(audio.SONG_BASE);
        self.input = .{ .buf = base[0..IN_RING] };
        self.pcm = @ptrFromInt(audio.SONG_BASE + PCM_OFF);
        zm_mp3_init(@ptrFromInt(audio.SONG_BASE + STATE_OFF));
        out.setup();
        self.active = true;
        self.state = .playing;
        return true;
    }

    pub fn stop(self: *Mp3Player) void {
        if (!self.active) return;
        self.active = false;
        self.state = .idle;
        for (0..audio.NUM_CHANNELS) |ch| audio.machinePaulaSetActive(@intCast(ch), 0);
    }

    pub fn ctl(self: *Mp3Player, op: u32, arg: u32) void {
        switch (op) {
            @intFromEnum(Op.start) => _ = self.start(),
            @intFromEnum(Op.stop) => self.stop(),
            @intFromEnum(Op.pause) => if (self.active and self.state != .ended) {
                self.state = if (arg != 0) .paused else .playing;
            },
            @intFromEnum(Op.end) => self.eof = true,
            else => {},
        }
    }

    /// Append the `len` bytes staged at STAGE_OFF.
    pub fn feed(self: *Mp3Player, len: u32) void {
        if (!self.active) return;
        const p: [*]const u8 = @ptrFromInt(audio.SONG_BASE + STAGE_OFF);
        self.input.write(p[0..@min(len, STAGE)]);
    }

    /// zg.mp3Status(which): 0 the state word, 1 bytes used (total), 2 frames decoded.
    pub fn status(self: *const Mp3Player, which: u32) u32 {
        return switch (which) {
            0 => out.word(@intFromEnum(self.state), self.eof, self.rate, self.stereo, self.errors, self.underruns),
            1 => self.input.r,
            2 => self.frames,
            else => 0,
        };
    }

    pub fn renderStereo(self: *Mp3Player, frames: usize) void {
        const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
        audio.machineClear(n);
        if (n == 0) return;
        const at0 = ring.place(self.ring_pos, n);
        self.ring_pos = at0 + n;
        const bufs = out.buffers(at0);
        for (0..n) |f| out.put(bufs, @intCast(f), out.bytes(self.next()));
        out.trigger(at0, n);
        audio.machineMixPaula(0, n);
        audio.machineClamp(n);
    }

    /// The next 44.1 kHz output sample: silence while paused, starved or done.
    fn next(self: *Mp3Player) [2]i16 {
        if (self.state != .playing) return .{ 0, 0 };
        if (self.frames == 0 and !self.decode()) return .{ 0, 0 }; // the first frame tells the rate
        if (self.conv) |*c| {
            if (!c.primed) { // no delay: the first output sample is the first source sample
                c.push(self.source() orelse .{ 0, 0 });
                c.push(self.source() orelse c.b);
                c.primed = true;
            }
            const s = c.sample();
            var k = c.advance();
            while (k > 0) : (k -= 1) c.push(self.source() orelse c.b);
            return s;
        }
        return self.source() orelse .{ 0, 0 };
    }

    /// The next decoded sample at the stream's own rate, decoding a frame when the last is spent.
    fn source(self: *Mp3Player) ?[2]i16 {
        if (self.pcm_at >= self.pcm_n and !self.decode()) {
            if (self.eof) { // decode() drained what a frame could not use
                self.state = .ended;
            } else if (self.frames > 0) {
                self.underruns +|= 1;
            }
            return null;
        }
        const i = self.pcm_at;
        self.pcm_at += 1;
        if (!self.stereo) return .{ self.pcm[i], self.pcm[i] };
        return .{ self.pcm[2 * i], self.pcm[2 * i + 1] };
    }

    /// Decode frames until one makes PCM, a few at a time (a bad stream must not stall the render).
    fn decode(self: *Mp3Player) bool {
        var tries: u32 = 0;
        while (tries < 64) : (tries += 1) {
            switch (in.cut(&self.input, self.synced, self.eof, &self.id3)) {
                .wait => return false,
                .skipped => self.synced = false,
                .frame => |len| if (self.one(len)) return true,
            }
        }
        return false;
    }

    fn one(self: *Mp3Player, len: u32) bool {
        const f: [*]u8 = @ptrFromInt(audio.SONG_BASE + FRAME_OFF);
        self.input.copyOut(f[0..len]);
        self.input.skip(len);
        self.synced = true;
        var info: [2]u32 = .{ 0, 0 };
        const r = zm_mp3_decode(@ptrFromInt(audio.SONG_BASE + STATE_OFF), f, len, self.pcm, &info);
        if (r < 0) self.errors +|= 1;
        if (r <= 0) return false;
        if (info[0] != self.rate) {
            self.rate = info[0];
            self.conv = if (self.rate == rs.OUT_RATE) null else rs.Linear.init(self.rate);
        }
        self.stereo = info[1] == 2;
        self.pcm_n = @intCast(r);
        self.pcm_at = 0;
        self.frames +%= 1;
        return true;
    }
};
