// Tests for effects/span_fill.zig: against @memset on every alignment and
// lengths 0..40, over random bytes and over bytes that mostly already hold the
// fill value (the case it is for).
const std = @import("std");
const span = @import("span_fill.zig");

test "fill leaves exactly what @memset leaves" {
    var prng = std.Random.DefaultPrng.init(3);
    const r = prng.random();
    var a: [64]u8 align(4) = undefined;
    var b: [64]u8 align(4) = undefined;
    for (0..4) |off| for (0..41) |len| for (0..4) |trial| {
        const v = r.int(u8);
        for (&a) |*p| p.* = if (trial % 2 == 0) r.int(u8) else if (r.uintLessThan(u8, 8) == 0) r.int(u8) else v;
        b = a;
        @memset(a[off..][0..len], v);
        span.fill(b[off..][0..len], v);
        try std.testing.expectEqualSlices(u8, &a, &b);
    };
}
