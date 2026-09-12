// --------------------------------------------------------------------------
// TV analogue noise ("snow") — the picture between two channels.
//
// Pure: it knows nothing about planes or the machine, only a byte buffer of
// palette indices and a small grey ramp. The caller owns the plane (demo_main
// opens its borders so the snow covers the whole tube) and writes RAMP into the
// palette at `first`. That keeps this file testable natively and lets the same
// code run as a channel change or as a depack effect.
//
// Per frame: every pixel gets a 3-bit grey from a xorshift32 stream, a brighter
// band rolls down the screen (the vertical hold slipping), and a couple of dark
// tear lines jitter sideways. Deterministic for a given seed.
// --------------------------------------------------------------------------

pub const LEVELS = 8;

/// Grey levels written at palette entries first..first+7, darkest first.
pub const RAMP = [LEVELS]u8{ 0x00, 0x24, 0x49, 0x6d, 0x92, 0xb6, 0xdb, 0xff };

/// Band height, in rows, of the rolling bright bar.
const BAND_ROWS: u32 = 24;
/// How many grey levels the rolling bar adds (clamped to the ramp).
const BAND_BOOST: u8 = 3;

pub const Noise = struct {
    state: u32,
    roll: u32, // row the bright band starts on

    pub fn init(seed: u32) Noise {
        // xorshift32 has one fixed point: an all-zero state never leaves zero.
        return .{ .state = if (seed == 0) 0x9E37_79B9 else seed, .roll = 0 };
    }

    pub fn next(self: *Noise) u32 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        return x;
    }

    /// Fill `buf` (w*h indices, row stride `w`) with one frame of snow using
    /// palette entries first..first+LEVELS-1. `buf.len` must be at least w*h.
    pub fn fill(self: *Noise, buf: []u8, w: u32, h: u32, first: u8) void {
        if (w == 0 or h == 0 or buf.len < @as(usize, w) * h) return;
        const tear_a = self.next() % h;
        const tear_b = self.next() % h;
        for (0..h) |yi| {
            const y: u32 = @intCast(yi);
            const row = buf[yi * w ..][0..w];
            if (y == tear_a or y == tear_b) {
                // A dark tear, displaced sideways by a few pixels.
                const jitter = self.next() % 8;
                @memset(row, first);
                const lit = @min(jitter, w);
                @memset(row[0..lit], first + 2);
                continue;
            }
            const in_band = (y -% self.roll) % h < BAND_ROWS;
            var bits: u32 = 0;
            var left: u5 = 0;
            for (row) |*px| {
                if (left < 3) {
                    bits = self.next();
                    left = 30;
                }
                var lvl: u8 = @intCast(bits & 7);
                bits >>= 3;
                left -= 3;
                if (in_band) lvl = @min(lvl + BAND_BOOST, LEVELS - 1);
                px.* = first + lvl;
            }
        }
        self.roll = (self.roll + 3) % h;
    }
};

// --------------------------------------------------------------------------
const std = @import("std");

test "xorshift is deterministic for a seed" {
    var a = Noise.init(1234);
    var b = Noise.init(1234);
    for (0..1000) |_| try std.testing.expectEqual(a.next(), b.next());
}

test "zero seed does not lock the generator at zero" {
    var n = Noise.init(0);
    try std.testing.expect(n.next() != 0);
}

test "fill writes only the ramp's palette range" {
    var buf = [_]u8{0xAA} ** (400 * 280);
    var n = Noise.init(7);
    const first: u8 = 200;
    for (0..5) |_| n.fill(&buf, 400, 280, first);
    for (buf) |px| {
        try std.testing.expect(px >= first);
        try std.testing.expect(px < first + LEVELS);
    }
}

test "fill uses more than one level (it is noise, not a flat fill)" {
    var buf = [_]u8{0} ** (64 * 16);
    var n = Noise.init(99);
    n.fill(&buf, 64, 16, 0);
    var seen = [_]bool{false} ** LEVELS;
    for (buf) |px| seen[px] = true;
    var count: usize = 0;
    for (seen) |s| count += @intFromBool(s);
    try std.testing.expect(count >= 4);
}

test "fill refuses a buffer smaller than w*h instead of overrunning it" {
    var buf = [_]u8{0x55} ** 10;
    var n = Noise.init(3);
    n.fill(&buf, 4, 4, 0);
    for (buf) |px| try std.testing.expectEqual(@as(u8, 0x55), px);
}

test "last palette index stays in u8 range at the top of the palette" {
    var buf = [_]u8{0} ** (16 * 8);
    var n = Noise.init(5);
    n.fill(&buf, 16, 8, 256 - LEVELS);
    for (buf) |px| try std.testing.expect(px >= 256 - LEVELS);
}
