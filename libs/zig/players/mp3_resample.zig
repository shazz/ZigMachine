// --------------------------------------------------------------------------
// The MP3 player's rate converter: a 32 or 48 kHz stream to the chip's 44.1,
// linear between two source samples, integers only. The position counts in
// 1/44100ths of a source sample (+rate an output sample), so the rate is exact
// and the converter never drifts against the stream (a Q16 step would: 48000
// is no multiple of 44100, and 0.13/65536 a sample is a whole sample in 10 s).
// The weight is that position in Q15 through a reciprocal, not a divide (BARD
// has no divider). Cheap, and NOT bit-exact against any reference decode: a
// 44.1 kHz stream bypasses it and is (mp3.zig). Pure: mp3_resample_test.zig.
// --------------------------------------------------------------------------

pub const OUT_RATE: u32 = 44100;
const RECIP: u32 = 48696; // ceil(2^31 / 44100): pos x RECIP >> 16 is pos / 44100 in Q15, at most 1 low

pub const Linear = struct {
    rate: u32, // source samples a second
    pos: u32 = 0, // past `a`, in 1/44100ths of a source sample (< 44100)
    a: [2]i16 = .{ 0, 0 },
    b: [2]i16 = .{ 0, 0 },
    primed: bool = false, // a and b hold the first two source samples (the player's)

    pub fn init(rate: u32) Linear {
        return .{ .rate = rate };
    }

    /// The output sample at the current position.
    pub fn sample(self: *const Linear) [2]i16 {
        const w: i32 = @intCast(@min((self.pos * RECIP) >> 16, 32767)); // Q15
        var out: [2]i16 = undefined;
        for (0..2) |s| {
            const d: i32 = @as(i32, self.b[s]) - self.a[s]; // |d| < 2^16, w < 2^15: inside an i32
            out[s] = @intCast(self.a[s] + ((d * w) >> 15));
        }
        return out;
    }

    /// Move one output sample on; answers how many source samples to push() before the next sample().
    pub fn advance(self: *Linear) u32 {
        self.pos += self.rate;
        var n: u32 = 0;
        while (self.pos >= OUT_RATE) : (n += 1) self.pos -= OUT_RATE;
        return n;
    }

    pub fn push(self: *Linear, s: [2]i16) void {
        self.a = self.b;
        self.b = s;
    }
};
