//! zigdemo mp3: a REAL music backend. An MP3 file fed to the host's MP3 player (on KESTREL:
//! zg.mp3Ctl / mp3Feed / mp3Status, pvmp3 on BARD or the page's AudioWorklet), and the clock
//! source read back from what the player decoded. It replaces audio.zig's mock for a cart
//! whose music is an MP3; audio.zig stays as the mock for the tests and a cart with none.
//!
//! zigdemo imports nothing, so the cart hands in two comptime types:
//!   Host   ctl(Op, arg), feed(bytes), status(Stat) -> u32: the player (the numbering is
//!          zigos's Mp3Op / Mp3Stat, so the cart's Host is three one-line forwards)
//!   Input  len() -> u32, read(off, dst) -> u32 bytes read: the file, random access (a
//!          SliceInput below for a file in memory; the cart wraps KOS GEMDOS Fseek/Fread)
//!
//! Position: the player counts decoded frames; samples = base + frames x samples a frame,
//! where `base` is where the stream started (0, or the seek's frame). The player's status
//! answers a frame or two late, so for `trust` frames after a start the position holds at
//! `base` (it may still be the last stream's count). Decoded is not heard: the output's own
//! buffering is a small constant lag, `fill` in the clock's source.
//!
//! Seek: the players have no seek, so seekMs restarts the stream at a byte offset, the frame
//! the time falls in, found by its sync word and checked by the next header. Exact for a
//! constant-bitrate file (the offset is linear in time); a VBR file lands where its first
//! frame's bitrate says. The first frame after a seek may lack its bit reservoir (a click).
//!
//! No player (a harness's host answers 0 to everything): after `no_player` frames of a live
//! stream with a zero state, source() gives the VBL so the demo still runs.

const std = @import("std");
const clock = @import("clock.zig");

pub const Op = enum(u32) { start = 0, stop = 1, pause = 2, end = 3 };
pub const Stat = enum(u32) { word = 0, used = 1, frames = 2, load = 3 };

/// One MPEG audio layer III frame's format, from its 4-byte header.
pub const Format = struct { rate: u32, spf: u32, kbps: u32, bytes: u32 };

const RATES = [3][3]u32{ .{ 44100, 48000, 32000 }, .{ 22050, 24000, 16000 }, .{ 11025, 12000, 8000 } };
const KBPS_V1 = [15]u32{ 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 };
const KBPS_V2 = [15]u32{ 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160 };

/// A layer III header (big-endian u32), or null: MPEG 1, 2 and 2.5, no free format.
pub fn header(h: u32) ?Format {
    if (h >> 21 != 0x7FF) return null;
    const ver: u32 = (h >> 19) & 3; // 3 MPEG-1, 2 MPEG-2, 0 MPEG-2.5
    if (ver == 1 or (h >> 17) & 3 != 1) return null; // reserved, or not layer III
    const bi: u32 = (h >> 12) & 15;
    const ri: u32 = (h >> 10) & 3;
    if (bi == 0 or bi == 15 or ri == 3) return null;
    const v: usize = switch (ver) {
        3 => 0,
        2 => 1,
        else => 2,
    };
    const kbps = if (v == 0) KBPS_V1[bi] else KBPS_V2[bi];
    const rate = RATES[v][ri];
    const spf: u32 = if (v == 0) 1152 else 576;
    const pad: u32 = (h >> 9) & 1;
    return .{ .rate = rate, .spf = spf, .kbps = kbps, .bytes = spf / 8 * kbps * 1000 / rate + pad };
}

fn be32(b: []const u8, i: usize) u32 {
    return std.mem.readInt(u32, b[i..][0..4], .big);
}

/// The first frame at or after `from` in `b` whose next frame's header follows it: (offset, format).
pub fn syncFrom(b: []const u8, from: usize) ?struct { at: u32, fmt: Format } {
    var i = from;
    while (i + 4 <= b.len) : (i += 1) {
        const f = header(be32(b, i)) orelse continue;
        const next = i + f.bytes;
        if (next + 4 <= b.len and header(be32(b, next)) == null) continue;
        return .{ .at = @intCast(i), .fmt = f };
    }
    return null;
}

/// The size of an ID3v2 tag at the start of `b` (0 when none): ten bytes and a syncsafe length.
pub fn id3Size(b: []const u8) u32 {
    if (b.len < 10 or !std.mem.eql(u8, b[0..3], "ID3")) return 0;
    const n = (@as(u32, b[6] & 0x7F) << 21) | (@as(u32, b[7] & 0x7F) << 14) | (@as(u32, b[8] & 0x7F) << 7) | (b[9] & 0x7F);
    return 10 + n + (if (b[5] & 0x10 != 0) @as(u32, 10) else 0);
}

/// A file already in memory (a cart's own data, a test).
pub const SliceInput = struct {
    bytes: []const u8,

    pub fn len(self: *const SliceInput) u32 {
        return @intCast(self.bytes.len);
    }
    pub fn read(self: *const SliceInput, off: u32, dst: []u8) u32 {
        if (off >= self.bytes.len) return 0;
        const n = @min(dst.len, self.bytes.len - off);
        @memcpy(dst[0..n], self.bytes[off..][0..n]);
        return @intCast(n);
    }
};

pub const Config = struct {
    ring: u32 = 64 * 1024, // the player's input ring (zigos MP3_RING)
    feed_max: u32 = 32 * 1024, // one feed's most (zigos MP3_FEED_MAX)
    trust: u32 = 4, // frames after a start the status may still be the last stream's
    no_player: u32 = 30, // frames of a zero state before the source falls back to the VBL
    fill: u32 = 0, // samples decoded but not heard yet (the output's buffering)
};

/// The stream: Music(Host, Input) (mp3_music.zig).
pub const Music = @import("mp3_music.zig").Music;
