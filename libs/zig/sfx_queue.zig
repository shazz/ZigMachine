// --------------------------------------------------------------------------
// zg.sfxPlay / zg.sfxStop / zg.ymWrite -- a game's sound effects OVER a MOD,
// and zg.requestModVolume, the MOD's own level under them; and
// zg.requestSndhMode, how the SNDH playing is played (players/sndh_native.zig).
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
//   0 op    1 play, 2 stop, 3 ym, 4 gain, 5 sndh mode, 6 sample, 7 sample stop, 8 song
//   1 a     play, sample: 1 = looped; stop: 1 = only a looped effect; ym: register;
//           sndh mode: 1 the 68000 on Musashi, 2 native, 3 native with PCM samples;
//           song: the image's kind (SongKind: 1 SNDH, 2 SAP)
//   2 b     ym: the value; song: the subtune (from 1; 0 = the image's default)
//   3 -     0
//   4 ptr   play, sample: the PCM (signed 8-bit); song: the image; a cart address
//   8 len   play, sample, song: its length in bytes; gain: the MOD's gain x 65536 (0..65536)
//   12 rate play, sample: the sample rate in Hz
//
// A SAMPLE (zg.samplePlay) is not an effect over a song: it is the whole PCM
// handed to the audio side, which plays it on its own (the stream ring, looping
// or to its end) with no cart in the loop: the sound CPU on the board, the audio
// thread in the browser. Unlike a play, its bytes are READ WHILE IT PLAYS, so
// they must stay put until zg.sampleStop or its end.
//
// A SONG (zg.requestSongBytes) is a song image the cart holds in its own RAM,
// e.g. read off its disk through the drive: the host copies the bytes when it
// drains the queue and loads them as it loads a file the song bridge fetched by
// name. It is a song LOAD, not an effect: it replaces whatever plays.
//
// Generic over nothing: plain state, tested natively (sfx_queue_test.zig).
// --------------------------------------------------------------------------

/// Commands one host frame can carry: an engine note is ~14 YM writes.
pub const CAP: usize = 32;
/// The largest effect the audio thread takes (sfx_voice.CAP).
pub const PCM_MAX: usize = 64 * 1024;
pub const RATE_MIN: u32 = 1000;
pub const RATE_MAX: u32 = 50066;

/// The largest sample (zg.samplePlay): the cart's whole RAM window.
pub const SAMPLE_MAX: usize = 2 * 1024 * 1024;

pub const Op = enum(u8) { play = 1, stop = 2, ym = 3, gain = 4, sndh_mode = 5, sample = 6, sample_stop = 7, song = 8 };
/// What a song image is (entry.a of a song): the player the host loads it into.
pub const SongKind = enum(u8) { sndh = 1, sap = 2 };
/// The largest song image the queue takes (a big SNDH is ~100 KB).
pub const SONG_MAX: usize = 256 * 1024;
pub const SNDH_MODES: u8 = 3; // sndh_native.zig Mode: 1..3
/// A gain of 1.0 on the wire (entry.len).
pub const GAIN_ONE: u32 = 65536;

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
    if (@sizeOf(Entry) != 16) @compileError("the host reads 16-byte entries");
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

    /// The MOD's own channels at `g` (0..1) of their volume, from the song
    /// requested before it (zg.requestModVolume). NaN or outside 0..1 is
    /// refused, never clamped: a gain of 2 is a bug, not a loud song.
    pub fn gain(self: *Queue, g: f32) bool {
        if (!(g >= 0.0 and g <= 1.0)) return self.refuse();
        const q: u32 = @intFromFloat(@round(g * @as(f32, @floatFromInt(GAIN_ONE))));
        return self.push(.{ .op = @intFromEnum(Op.gain), .len = q });
    }

    /// How the SNDH playing is played (zg.requestSndhMode). A mode that does
    /// not exist is refused here; a tune with no native driver plays 1 whatever
    /// is asked, and the audio thread says so.
    pub fn sndhMode(self: *Queue, mode: u8) bool {
        if (mode < 1 or mode > SNDH_MODES) return self.refuse();
        return self.push(.{ .op = @intFromEnum(Op.sndh_mode), .a = mode });
    }

    /// Play all of `pcm` on the audio side, from its first byte (zg.samplePlay).
    pub fn sample(self: *Queue, pcm: []const u8, rate: u32, loop: bool) bool {
        if (pcm.len == 0 or pcm.len > SAMPLE_MAX or rate < RATE_MIN or rate > RATE_MAX) return self.refuse();
        return self.push(.{
            .op = @intFromEnum(Op.sample),
            .a = @intFromBool(loop),
            .ptr = @truncate(@intFromPtr(pcm.ptr)),
            .len = @intCast(pcm.len),
            .rate = rate,
        });
    }

    /// Load the song image `bytes` (zg.requestSongBytes); `tune` counts from 1.
    pub fn song(self: *Queue, bytes: []const u8, kind: SongKind, tune: u8) bool {
        if (bytes.len == 0 or bytes.len > SONG_MAX) return self.refuse();
        return self.push(.{
            .op = @intFromEnum(Op.song),
            .a = @intFromEnum(kind),
            .b = tune,
            .ptr = @truncate(@intFromPtr(bytes.ptr)),
            .len = @intCast(bytes.len),
        });
    }

    pub fn sampleStop(self: *Queue) bool {
        return self.push(.{ .op = @intFromEnum(Op.sample_stop) });
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
