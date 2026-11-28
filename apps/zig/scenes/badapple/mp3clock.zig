// --------------------------------------------------------------------------
// BAD APPLE!! the song's clock: what time an MP3 player's frame count stands for. zg.mp3Status(.frames) counts
// DECODED frames, whatever their size: 1152 samples for MPEG-1 Layer III, 576 for MPEG-2 / 2.5 (the local song
// is MPEG-2 at 22.05 kHz), and the status word's rate field only says "other" there. So the cart reads the
// rate and frame size off the file's first frame header itself. Integers only. Pure: native tests in
// mp3clock_test.zig.
// --------------------------------------------------------------------------

pub const Format = struct {
    rate: u32, // samples a second
    spf: u32, // samples a frame

    /// Microseconds of sound in `frames` decoded frames.
    pub fn us(self: Format, frames: u32) u64 {
        return @as(u64, frames) * self.spf * 1_000_000 / self.rate;
    }
};

const RATES = [3][3]u32{
    .{ 11025, 12000, 8000 }, // MPEG-2.5
    .{ 22050, 24000, 16000 }, // MPEG-2
    .{ 44100, 48000, 32000 }, // MPEG-1
};

/// The format of the first Layer III frame in `head` (the file's first bytes; an ID3v2 tag is skipped when the
/// whole tag fits in `head`... and its frame header after it). Null: no Layer III frame header where one must be.
pub fn parse(head: []const u8) ?Format {
    var p: usize = 0;
    if (head.len >= 10 and head[0] == 'I' and head[1] == 'D' and head[2] == '3') {
        for (head[6..10]) |b| if (b & 0x80 != 0) return null; // a synchsafe size has no high bits
        const size = (@as(usize, head[6]) << 21) | (@as(usize, head[7]) << 14) | (@as(usize, head[8]) << 7) | head[9];
        p = 10 + size;
    }
    if (p + 4 > head.len) return null;
    const h = head[p..][0..4];
    if (h[0] != 0xFF or h[1] & 0xE0 != 0xE0) return null; // the 11-bit sync
    const version = (h[1] >> 3) & 3; // 0 MPEG-2.5, 1 reserved, 2 MPEG-2, 3 MPEG-1
    const layer = (h[1] >> 1) & 3; // 1 = Layer III
    const rate_idx = (h[2] >> 2) & 3;
    if (version == 1 or layer != 1 or rate_idx == 3) return null;
    const row: usize = switch (version) {
        0 => 0,
        2 => 1,
        else => 2,
    };
    return .{ .rate = RATES[row][rate_idx], .spf = if (version == 3) 1152 else 576 };
}

/// The film's elapsed time pulled towards the song's: never more than `slack` us away from it. The song's
/// position moves in frame steps (26 ms here) and answers a frame or two late, so inside the slack the host
/// clock (smooth) is kept; outside it the song wins (A/V sync is the point).
pub fn pull(elapsed: u64, song_us: u64, slack: u64) u64 {
    if (elapsed > song_us + slack) return song_us + slack;
    if (elapsed + slack < song_us) return song_us - slack;
    return elapsed;
}
