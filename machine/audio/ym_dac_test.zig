// Tests for machine/audio/ym.zig's DAC (level -> amplitude) against a real ST.
//
// The reference: Paulo Simoes's 2012 measurement of a real Atari ST's YM2149
// output (published with Hatari as src/includes/ym2149_fixed_vol.h), one
// channel alone, each fixed volume 1..14 relative to volume 15, in dB rounded
// to 0.1 dB. These 14 figures are derived from the measurement; the
// measured table itself (GPL, in Hatari) is not copied here.
// Tolerance: 1.1 dB at every level (ym.zig's fitted curve is within 1.03 dB;
// the old table was up to 7.8 dB too quiet, jotego's jt49 is within 1.6 dB).
const std = @import("std");
const ym = @import("ym.zig");

const MEASURED_DB = [16]f32{
    -std.math.inf(f32), -49.2, -42.8, -39.0, -35.2, -32.3, -28.8, -26.0,
    -22.7,              -19.9, -16.5, -13.8, -10.4, -7.4,  -3.5,  0.0,
};
const TOLERANCE_DB: f32 = 1.1;

fn fixedDb(v: usize) f32 {
    return 20.0 * @log10(ym.VOL_TABLE[2 * v + 1] / ym.VOL_TABLE[31]);
}

test "fixed volumes 1..15 are within 1.1 dB of a measured ST" {
    var worst: f32 = 0;
    for (1..16) |v| {
        const err = fixedDb(v) - MEASURED_DB[v];
        worst = @max(worst, @abs(err));
        if (@abs(err) > TOLERANCE_DB) {
            std.debug.print("volume {d}: {d:.2} dB, measured {d:.1} dB\n", .{ v, fixedDb(v), MEASURED_DB[v] });
            return error.DacCurve;
        }
    }
    try std.testing.expect(worst > 0); // the comparison ran
}

test "volume 0 and envelope level 0 are silent; level 31 is full scale" {
    try std.testing.expectEqual(@as(f32, 0), ym.VOL_TABLE[0]);
    try std.testing.expectEqual(@as(f32, 0), ym.VOL_TABLE[1]);
    try std.testing.expectEqual(@as(f32, 1), ym.VOL_TABLE[31]);
}

test "the 32 envelope levels rise strictly from level 1, half a volume step each" {
    for (2..32) |l| try std.testing.expect(ym.VOL_TABLE[l] > ym.VOL_TABLE[l - 1]);
    // an envelope half-step sits between its two fixed-volume neighbours
    for (1..15) |v| {
        const lo = ym.VOL_TABLE[2 * v + 1];
        const hi = ym.VOL_TABLE[2 * v + 3];
        try std.testing.expect(ym.VOL_TABLE[2 * v + 2] > lo and ym.VOL_TABLE[2 * v + 2] < hi);
    }
}

test "one channel at volume 15 renders 0.33 of full scale (the RTL mix assumes it)" {
    var chip: ym.Ym2149 = .{};
    chip.init(44100.0);
    chip.writeReg(7, 0x3F); // tone and noise off: the channel's gate stays open
    chip.writeReg(8, 15);
    var l = [_]f32{0} ** 64;
    var r = [_]f32{0} ** 64;
    chip.render(&l, &r);
    try std.testing.expectApproxEqAbs(@as(f32, 0.33), l[0], 1e-6);
}
