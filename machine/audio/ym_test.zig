// Tests for machine/audio/ym.zig's tone gate: a tone above the output's
// Nyquist frequency (periods 0-5 at 44.1 kHz) is its average, 0.5, never a
// point-sampled square that folds down to an audible whistle (period 0 ->
// 7300 Hz); every other tone is the square as before, 1 or 0.
const std = @import("std");
const Ym2149 = @import("ym.zig").Ym2149;
const expectEqual = std.testing.expectEqual;

const TONE_A_ONLY: u8 = 0x3E; // mixer: tone A on, B/C tone and all noise off

fn chip(period: u16) Ym2149 {
    var ym: Ym2149 = .{};
    ym.init(44100.0);
    ym.writeReg(0, @truncate(period));
    ym.writeReg(1, @truncate(period >> 8));
    ym.writeReg(7, TONE_A_ONLY);
    return ym;
}

test "periods 0-5 (25 kHz and up) gate at their average, 0.5" {
    var p: u16 = 0;
    while (p <= 5) : (p += 1) {
        var ym = chip(p);
        for (0..1000) |_| try expectEqual(@as(f32, 0.5), ym.toneGate(0, TONE_A_ONLY));
    }
}

test "period 6 (20.8 kHz, under Nyquist) and up stay a square: 1 or 0, both seen" {
    for ([_]u16{ 6, 7, 100, 0xFFF }) |p| {
        var ym = chip(p);
        var ones: usize = 0;
        var zeros: usize = 0;
        for (0..200_000) |_| {
            const g = ym.toneGate(0, TONE_A_ONLY);
            if (g == 1) ones += 1 else if (g == 0) zeros += 1 else return error.NotASquare;
        }
        try std.testing.expect(ones > 0 and zeros > 0);
    }
}

test "a tone the mixer turns off holds the gate open, whatever its period" {
    var ym = chip(0);
    for (0..100) |_| try expectEqual(@as(f32, 1), ym.toneGate(0, 0x3F));
}

test "period 0 at full volume renders a flat level, no 7300 Hz alias" {
    var ym = chip(0);
    ym.writeReg(8, 15);
    var l = [_]f32{0} ** 512;
    var r = [_]f32{0} ** 512;
    ym.render(&l, &r);
    for (l[1..]) |v| try expectEqual(l[0], v);
    try std.testing.expect(l[0] > 0);
}
