// --------------------------------------------------------------------------
// The oscilloscope of the editor's header: the C editor samples the SID's OSC3 12 times a frame and draws it.
// The SID is on BARD here, so voice 3's oscillator is modelled from the registers the player wrote (frequency,
// pulse width, waveform bits, gate): a 24-bit phase accumulator and a crude envelope. Integer only. It is a
// picture of the wave, not the chip's own OSC3.
// --------------------------------------------------------------------------
const FRAME_CYCLES: u32 = 19656;
const SAMPLE_STEP: u32 = 320; // 6502 cycles between the 12 samples (~5 raster lines: about a period of a mid note)

pub const Scope = struct {
    phase: u32 = 0, // the 24-bit oscillator
    env: u8 = 0,
    noise: u32 = 0x7FFFF8,

    fn freq(sid: *const [25]u8) u32 {
        return @as(u32, sid[15]) << 8 | sid[14];
    }

    /// One player frame: the phase runs on, the envelope rises with the gate and falls without it.
    pub fn advance(self: *Scope, sid: *const [25]u8) void {
        self.phase = (self.phase +% freq(sid) *% FRAME_CYCLES) & 0xFFFFFF;
        if (sid[18] & 1 != 0) self.env = self.env +| 128 else self.env -|= self.env / 8 + 1;
    }

    fn wave(self: *Scope, sid: *const [25]u8, ph: u32) u8 {
        const ctrl = sid[18];
        if (ctrl & 0xF0 == 0) return 0x80;
        var v: u8 = 0xFF;
        if (ctrl & 0x10 != 0) v &= tri(ph);
        if (ctrl & 0x20 != 0) v &= @truncate(ph >> 16);
        if (ctrl & 0x40 != 0) v &= if ((ph >> 12) >= (@as(u32, sid[17] & 15) << 8 | sid[16])) 0xFF else 0;
        if (ctrl & 0x80 != 0) {
            self.noise = (self.noise << 1 | ((self.noise >> 22) ^ (self.noise >> 17)) & 1) & 0x7FFFFF;
            v &= @truncate(self.noise >> 8);
        }
        return v;
    }

    /// The 12 pixel rows of this frame's trace (0 top .. 15): the wave centred and scaled by the envelope.
    pub fn trace(self: *Scope, sid: *const [25]u8, rows: *[12]u8) void {
        const f = freq(sid);
        for (rows, 0..) |*r, i| {
            const ph = (self.phase +% f *% SAMPLE_STEP *% @as(u32, @intCast(i))) & 0xFFFFFF;
            const w: i32 = @as(i32, self.wave(sid, ph)) - 128;
            const scaled = 128 + @divTrunc(w * @as(i32, self.env), 256);
            r.* = @intCast(15 - (@as(u32, @intCast(@max(0, @min(255, scaled)))) >> 4));
        }
    }
};

fn tri(ph: u32) u8 {
    const v: u8 = @truncate(ph >> 15);
    return if (ph & 0x800000 != 0) ~v else v;
}

const std = @import("std");

test "a silent SID draws the flat centre line, a sounding saw draws a slope with spread" {
    var s: Scope = .{};
    var sid = [_]u8{0} ** 25;
    var rows: [12]u8 = undefined;
    s.trace(&sid, &rows);
    try std.testing.expectEqualSlices(u8, &[_]u8{7} ** 12, &rows);
    sid[14] = 0xC1;
    sid[15] = 0x0B;
    sid[18] = 0x21; // saw + gate
    s.advance(&sid);
    s.advance(&sid);
    s.trace(&sid, &rows);
    var lo: u8 = 15;
    var hi: u8 = 0;
    for (rows) |r| {
        lo = @min(lo, r);
        hi = @max(hi, r);
    }
    try std.testing.expect(hi - lo >= 2 and hi <= 15);
}

test "the envelope falls when the gate is off" {
    var s: Scope = .{ .env = 200 };
    var sid = [_]u8{0} ** 25;
    sid[18] = 0x20;
    for (0..30) |_| s.advance(&sid);
    try std.testing.expect(s.env < 20);
}
