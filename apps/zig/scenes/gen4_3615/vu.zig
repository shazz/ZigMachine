// --------------------------------------------------------------------------
// The VU meters' levels (screen.js 351-365, sc68_vumeter.js getVolumeVoiceN)
// in integers: no float per frame on ZIGGY.
//
// A voice's level is max(vol * 100 / 15, last * 0.9) and its bar the trunc
// of 1.8x that. A fresh volume's bar, trunc(f64(vol * 100 / 15) * 1.8), is a
// compile-time table of the JS's own doubles (12 * vol, give or take the
// rounding the JS lands on); a decaying one is Q24 and may be 1 off the JS
// where 1.8x it crosses an integer within ~2^-20.
// --------------------------------------------------------------------------
const NONE: u8 = 0xFF;
const NINE_TENTHS: u64 = 3_865_470_566; // 0.9 * 2^32, rounded down

/// vol * 100 / 15 in Q24, and the bar it makes, by the JS's f64 maths.
const FRESH: [16]u32 = blk: {
    var t: [16]u32 = undefined;
    for (&t, 0..) |*v, i| v.* = @intFromFloat(@round(@as(f64, @floatFromInt(i)) * 100 / 0xf * (1 << 24)));
    break :blk t;
};
const FRESH_BAR: [16]i32 = blk: {
    var t: [16]i32 = undefined;
    for (&t, 0..) |*v, i| v.* = @intFromFloat(@trunc(@as(f64, @floatFromInt(i)) * 100 / 0xf * 1.8));
    break :blk t;
};

pub const Meter = struct {
    last: [3]u32, // _lastVol1..3, Q24
    fresh: [3]u8, // the volume `last` was set from this frame, NONE when it decayed

    pub fn init(self: *Meter) void {
        self.last = @splat(0);
        self.fresh = @splat(NONE);
    }

    /// One frame: the volume registers' low nibbles in, then each bar (voice
    /// `voices[id]`) rises to its level or falls 6.
    pub fn step(self: *Meter, regs: *const [16]u8, voices: [3]usize, levels: *[3]i32) void {
        for (&self.last, &self.fresh, regs[8..11]) |*last, *fresh, reg| {
            const v = reg & 0xf;
            const decayed: u32 = @intCast((@as(u64, last.*) * NINE_TENTHS) >> 32);
            if (FRESH[v] >= decayed) {
                last.* = FRESH[v];
                fresh.* = v;
            } else {
                last.* = decayed;
                fresh.* = NONE;
            }
        }
        for (levels, voices) |*level, voice| {
            const f = self.fresh[voice];
            const v: i32 = if (f != NONE) FRESH_BAR[f] else @intCast((@as(u64, self.last[voice]) * 9 / 5) >> 24);
            level.* = if (level.* < v) v else @max(level.* - 6, 0);
        }
    }
};
