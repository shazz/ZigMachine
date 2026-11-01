// The host half of tests/test_zmx.py: zmx.c's vectors, in the same order, through
// libs/zig/zmx.zig (the spec), hashed the same way. Prints one hash per op, in zmx.c's
// OPS order; the test compares them with the core's REPORT lines.
const std = @import("std");
const zmx = @import("zmx");

const N_RANDOM: u32 = 2048;
const EDGES = [16]u32{
    0,          1,          0x7f,       0x80,       0xff,       0x7fffffff, 0x80000000, 0xffffffff,
    0x00ff00ff, 0xff00ff00, 0x01010101, 0xfefefefe, 0x00010000, 0xffff0000, 0x0000ffff, 0x12345678,
};

var rng: u32 = 0x2545f491;
fn next() u32 { // xorshift32, as zmx.c's
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

fn tex(d: u32, u: u32, v: u32) u32 {
    return switch (@as(u6, @intCast(d & 63))) {
        inline else => |dd| zmx.tex2d(@as(u4, dd & 7) + 3, @as(u4, dd >> 3) + 3, u, v),
    };
}

fn spec(op: u32, k: u32, a: u32, b: u32) u32 {
    const sa: i32 = @bitCast(a);
    const sb: i32 = @bitCast(b);
    return switch (op) {
        0 => @bitCast(zmx.mulsh16(sa, sb)),
        1 => @bitCast(zmx.mulsh15(sa, sb)),
        2 => zmx.funnel(1, a, b),
        3 => zmx.funnel(2, a, b),
        4 => zmx.funnel(3, a, b),
        5 => zmx.add8s(a, b),
        6 => zmx.sub8s(a, b),
        7 => zmx.avg8(a, b),
        8 => zmx.add8(a, b),
        else => tex(k, a, b),
    };
}

pub fn main() void {
    var op: u32 = 0;
    while (op < 10) : (op += 1) {
        var h: u32 = 2166136261;
        var i: u32 = 0;
        while (i < 256 + N_RANDOM) : (i += 1) {
            const a = if (i < 256) EDGES[i >> 4] else next();
            const b = if (i < 256) EDGES[i & 15] else next();
            h = (h ^ spec(op, i, a, b)) *% 16777619;
        }
        std.debug.print("HASH {d}\n", .{h});
    }
}
