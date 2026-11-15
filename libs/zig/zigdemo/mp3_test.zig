//! Tests for mp3.zig: the header table, the ID3 skip and the sync search, then the stream
//! against a fake player (it decodes one frame a tick from what it was fed): the ring is never
//! overfed, the clock follows the decoded samples, a seek lands on a frame at its time, and a
//! host with no player falls back to the VBL.
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const mp3 = @import("mp3.zig");
const clock = @import("clock.zig");

/// MPEG-2 layer III, 22,050 Hz, 64 kbps, mono: 208 or 209 bytes, 576 samples a frame.
fn hdr22k(pad: bool) [4]u8 {
    return .{ 0xFF, 0xF3, 0x80 | (if (pad) @as(u8, 2) else 0), 0xC0 };
}

/// A CBR file: an ID3 tag of `tag` bytes, then `n` frames (every third one padded), each
/// frame's body filled with its index (the fake player reads it back).
fn file(buf: []u8, tag: u32, n: u32) []u8 {
    var o: usize = 0;
    if (tag > 0) {
        @memset(buf[0..tag], 0);
        @memcpy(buf[0..3], "ID3");
        const body = tag - 10;
        buf[6] = @intCast((body >> 21) & 0x7F);
        buf[7] = @intCast((body >> 14) & 0x7F);
        buf[8] = @intCast((body >> 7) & 0x7F);
        buf[9] = @intCast(body & 0x7F);
        o = tag;
    }
    for (0..n) |i| {
        const h = hdr22k(i % 3 == 2);
        const len = mp3.header(std.mem.readInt(u32, &h, .big)).?.bytes;
        @memcpy(buf[o..][0..4], &h);
        @memset(buf[o + 4 .. o + len], @intCast(i & 0x7F)); // never 0xFF: no false sync
        o += len;
    }
    return buf[0..o];
}

/// The fake player: what was fed, what it took, the frames it decoded, its state.
const Fake = struct {
    var fed: u32 = 0;
    var used: u32 = 0;
    var frames: u32 = 0;
    var word: u32 = 0;
    var starts: u32 = 0;
    var alive = true;
    var max_fill: u32 = 0;

    fn reset(player: bool) void {
        fed = 0;
        used = 0;
        frames = 0;
        word = 0;
        starts = 0;
        alive = player;
        max_fill = 0;
    }
    pub fn ctl(op: mp3.Op, _: u32) void {
        if (op == .start) {
            fed = 0;
            used = 0;
            frames = 0;
            starts += 1;
            word = if (alive) 1 else 0;
        }
    }
    pub fn feed(b: []const u8) void {
        fed += @intCast(b.len);
        max_fill = @max(max_fill, fed - used);
    }
    pub fn status(s: mp3.Stat) u32 {
        return switch (s) {
            .word => word,
            .used => used,
            .frames => frames,
            .load => 150,
        };
    }
    /// One tick of decoding: a frame's bytes, if they were fed.
    fn tick() void {
        if (!alive or fed - used < 209) return;
        used += 209;
        frames += 1;
    }
};

const Music = mp3.Music(Fake, mp3.SliceInput);
var big: [1 << 20]u8 = undefined;
var chunk: [32 * 1024]u8 = undefined;

test "a layer III header gives its rate, samples and frame bytes" {
    const f = mp3.header(0xFFF380C0).?;
    try expectEqual(@as(u32, 22050), f.rate);
    try expectEqual(@as(u32, 576), f.spf);
    try expectEqual(@as(u32, 64), f.kbps);
    try expectEqual(@as(u32, 208), f.bytes);
    const g = mp3.header(0xFFFB9064).?; // MPEG-1, 128 kbps, 44.1 kHz
    try expectEqual(@as(u32, 44100), g.rate);
    try expectEqual(@as(u32, 1152), g.spf);
    try expectEqual(@as(u32, 417), g.bytes);
    try expect(mp3.header(0xFFFD9064) == null); // layer II
    try expect(mp3.header(0x12345678) == null);
}

test "the sync search skips the ID3 tag and needs the next header to follow" {
    const f = file(&big, 300, 10);
    try expectEqual(@as(u32, 300), mp3.id3Size(f));
    const s = mp3.syncFrom(f, mp3.id3Size(f)).?;
    try expectEqual(@as(u32, 300), s.at);
    big[400] = 0xFF; // a false sync in a frame's body: refused, the next real frame is found
    big[401] = 0xF3;
    big[402] = 0x80;
    big[403] = 0xC0;
    try expectEqual(@as(u32, 300 + 208), mp3.syncFrom(f, 301).?.at);
}

test "the ring is never overfed, and the clock follows the decoded samples" {
    Fake.reset(true);
    const f = file(&big, 0, 4000);
    const in = mp3.SliceInput{ .bytes = f };
    var m = Music{ .input = &in, .buf = &chunk };
    try expect(m.open());
    m.seekMs(0);
    var c = clock.Clock{};
    var vbl: u32 = 0;
    for (0..600) |_| {
        m.pump();
        Fake.tick();
        vbl += 1;
        c.update(m.source(vbl));
    }
    try expect(Fake.max_fill <= 64 * 1024);
    try expect(m.primed());
    // the clock moved with the frames decoded after the first `trust` frames (576 / 22,050 s each)
    const want: u32 = @intCast(@as(u64, Fake.frames) * 576 * 1000 / 22050);
    try expect(c.t + 200 >= want and c.t <= want);
    try expectEqual(@as(u32, 150), m.load());
}

test "a seek restarts the stream on the frame its time falls in" {
    Fake.reset(true);
    const f = file(&big, 120, 4000);
    const in = mp3.SliceInput{ .bytes = f };
    var m = Music{ .input = &in, .buf = &chunk };
    try expect(m.open());
    m.seekMs(10_000);
    try expectEqual(@as(u32, 1), Fake.starts);
    const frame_ms = @as(u64, m.base) * 1000 / 22050;
    try expect(frame_ms <= 10_000 and frame_ms + 27 >= 10_000); // within a frame (26 ms)
    try expectEqual(@as(u32, 0), m.base % 576);
    const at = m.cur; // the stream starts on a header
    try expect(mp3.header(std.mem.readInt(u32, f[at..][0..4], .big)) != null);
    try expectEqual(m.base, m.position()); // held while the status may be the last stream's
}

test "no player behind the host: the source falls back to the VBL" {
    Fake.reset(false);
    const f = file(&big, 0, 500);
    const in = mp3.SliceInput{ .bytes = f };
    var m = Music{ .input = &in, .buf = &chunk };
    try expect(m.open());
    m.seekMs(0);
    try expect(m.source(7) == .samples);
    for (0..40) |_| m.pump();
    try expect(m.no_player);
    const s = m.source(7);
    try expectEqual(@as(u32, 7), s.vbl.count);
}

test "not an MP3: open says so" {
    Fake.reset(true);
    @memset(big[0..4096], 0x55);
    const in = mp3.SliceInput{ .bytes = big[0..4096] };
    var m = Music{ .input = &in, .buf = &chunk };
    try expect(!m.open());
}
