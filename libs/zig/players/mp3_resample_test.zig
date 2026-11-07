const std = @import("std");
const rs = @import("mp3_resample.zig");

fn run(rate: u32, out_n: usize, src: []const [2]i16, out: [][2]i16) usize {
    var r = rs.Linear.init(rate);
    var k: usize = 0;
    r.push(src[k]);
    k += 1;
    r.push(src[k]);
    k += 1;
    for (0..out_n) |i| {
        out[i] = r.sample();
        var n = r.advance();
        while (n > 0) : (n -= 1) {
            r.push(if (k < src.len) src[k] else .{ 0, 0 });
            k += 1;
        }
    }
    return k;
}

test "48 kHz to 44.1: a ramp stays a ramp, and 4800 source samples make 4410" {
    var src: [4900][2]i16 = undefined;
    for (&src, 0..) |*s, i| s.* = .{ @intCast(i), -@as(i16, @intCast(i)) };
    var out: [4410][2]i16 = undefined;
    const used = run(48000, out.len, &src, &out);
    try std.testing.expect(used >= 4800 and used <= 4802);
    for (out, 0..) |o, i| {
        const want: i32 = @intCast((i * 48000) / 44100);
        try std.testing.expect(@abs(@as(i32, o[0]) - want) <= 1);
        try std.testing.expect(@abs(@as(i32, o[1]) + want) <= 1);
    }
}

test "32 kHz up to 44.1 interpolates between neighbours, extremes included" {
    const src = [_][2]i16{ .{ -32768, 32767 }, .{ 32767, -32768 }, .{ 0, 0 }, .{ 0, 0 } };
    var out: [3][2]i16 = undefined;
    _ = run(32000, out.len, &src, &out);
    try std.testing.expectEqual([2]i16{ -32768, 32767 }, out[0]);
    try std.testing.expect(out[1][0] > -32768 and out[1][0] < 32767);
}

test "48 kHz never drifts: 480000 source samples make exactly 441000" {
    var r = rs.Linear.init(48000);
    var used: u64 = 0;
    for (0..441000) |_| used += r.advance();
    try std.testing.expectEqual(@as(u64, 480000), used);
}
