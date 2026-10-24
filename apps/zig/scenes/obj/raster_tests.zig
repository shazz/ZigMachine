// Native tests of the OBJ demo's CPU rasterisers against CHISEL's own rules.
const std = @import("std");
const raster = @import("raster.zig");
const T = std.testing;

// The machine's own triangle (machine/blitter.zig doTriangle + crossSpan).
fn chiselTri(px: []u8, xs: [3]i32, ys: [3]i32, color: u8) void {
    var y = @max(@min(ys[0], @min(ys[1], ys[2])), 0);
    const ymax = @min(@max(ys[0], @max(ys[1], ys[2])), 199);
    while (y <= ymax) : (y += 1) {
        var xl: i32 = std.math.maxInt(i32);
        var xr: i32 = std.math.minInt(i32);
        for (0..3) |e| {
            var ay = ys[e];
            var ax = xs[e];
            var by = ys[(e + 1) % 3];
            var bx = xs[(e + 1) % 3];
            if (ay == by) continue;
            if (ay > by) {
                std.mem.swap(i32, &ay, &by);
                std.mem.swap(i32, &ax, &bx);
            }
            if (y < ay or y >= by) continue;
            const x = ax + @divFloor((bx - ax) * (y - ay), (by - ay));
            xl = @min(xl, x);
            xr = @max(xr, x);
        }
        if (xr < xl) continue;
        var x = @max(xl, 0);
        while (x <= @min(xr, 319)) : (x += 1) px[@intCast(y * 320 + x)] = color;
    }
}

var pa: [320 * 200]u8 = undefined;
var pb: [320 * 200]u8 = undefined;

test "the CPU triangle covers exactly CHISEL's pixels (clipped ones too)" {
    var rng = std.Random.DefaultPrng.init(1234);
    const r = rng.random();
    const t = raster.Target{ .px = &pb, .stride = 320, .w = 320, .h = 200 };
    for (0..3000) |i| {
        var v: [3]raster.P = undefined;
        const span: i16 = if (i % 3 == 0) 400 else 40;
        for (&v) |*p| p.* = .{ r.intRangeAtMost(i16, -40, span), r.intRangeAtMost(i16, -30, @divTrunc(span, 2)) };
        @memset(&pa, 0);
        @memset(&pb, 0);
        chiselTri(&pa, .{ v[0][0], v[1][0], v[2][0] }, .{ v[0][1], v[1][1], v[2][1] }, 7);
        raster.flat(t, v, 7);
        try T.expectEqualSlices(u8, &pa, &pb);
        @memset(&pb, 0);
        raster.gouraud(t, v, .{ 3 << 12, 3 << 12, 3 << 12 }, 4, 31); // a flat level: the same pixels
        try T.expectEqualSlices(u8, &pa, &pb);
    }
}

test "Gouraud spans the levels between its vertices, clamped" {
    @memset(&pb, 0);
    const t = raster.Target{ .px = &pb, .stride = 320, .w = 320, .h = 200 };
    raster.gouraud(t, .{ .{ 10, 10 }, .{ 200, 10 }, .{ 10, 150 } }, .{ 0, 31 << 12, 0 }, 1, 31);
    try T.expectEqual(@as(u8, 1), pb[20 * 320 + 10]);
    try T.expect(pb[11 * 320 + 190] >= 28);
}
