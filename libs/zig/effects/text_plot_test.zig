// Tests for effects/text_plot.zig: run-by-run plot against zg.Text's original
// per-byte loop, for font widths 1..12, glyph lengths around every run edge,
// keyed and not, at every destination alignment.
const std = @import("std");
const tp = @import("text_plot.zig");

fn oldPlot(dst: [*]u8, start: u32, row_step: u32, data: []const u8, fw: u16, key: ?u8) void {
    var pos = start;
    for (data, 0..) |pixel, idx| {
        if (key) |k| {
            if (pixel != k) dst[pos] = pixel;
        } else dst[pos] = pixel;
        if (idx > 0 and (idx % fw == 0)) pos += row_step else pos += 1;
    }
}

test "plot writes exactly what the per-byte loop wrote" {
    var prng = std.Random.DefaultPrng.init(11);
    const rng = prng.random();
    var glyph: [150]u8 = undefined;
    for (&glyph) |*p| p.* = if (rng.boolean()) 0 else rng.int(u8);
    var a: [4096]u8 = undefined;
    var b: [4096]u8 = undefined;
    for (1..13) |fw| for ([_]u32{ 0, 1, 2, 3 }) |start| {
        const step: u32 = @intCast(40 - fw + 1);
        var len: usize = 0;
        while (len <= fw * fw + 2) : (len += 1) for ([_]?u8{ null, 0 }) |key| {
            rng.bytes(&a);
            b = a;
            oldPlot(&a, start, step, glyph[0..len], @intCast(fw), key);
            tp.plot(&b, start, step, glyph[0..len], @intCast(fw), key);
            try std.testing.expectEqualSlices(u8, &a, &b);
        };
    };
}
