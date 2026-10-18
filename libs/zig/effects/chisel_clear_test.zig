// Tests for effects/chisel_clear.zig: the CHISEL fills a plane clear issues,
// run through the machine's FILL (machine/blitter.zig execute + doFill, the
// plain-colour path, kept verbatim below), leave a fake video region byte for
// byte as the @memset clearFrameBuffer used to do -- for random planes of the
// real shapes (320x200, 640x200 medium, 400x280 fullscreen, tall scroll
// buffers) and random ones, anywhere in the region.
const std = @import("std");
const c = @import("chisel_clear.zig");

// machine/sdk/memmap.zig (a test cannot import outside its directory).
const G = c.Geometry{ .vram = 0x1100, .region = 0x1100 + 1024 * 1024 + 896000, .full_stride = 400, .full_h = 280, .normal_h = 200 };

const Clip = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

fn dstHeight(stride: u16) u16 {
    return if (stride == 400) 280 else 200;
}

// machine/blitter.zig execute() for FILL, CON = CON2 = 0, no halftone.
fn machineFill(region: []u8, d_base: usize, ds: u16, x0: i16, y0: i16, w: u16, h: u16, fg: u8) void {
    const cl = Clip{ .x0 = 0, .y0 = 0, .x1 = ds, .y1 = dstHeight(ds) };
    const bx0 = @max(@as(i32, x0), cl.x0);
    const by0 = @max(@as(i32, y0), cl.y0);
    const bx1 = @min(@as(i32, x0) + w, cl.x1);
    const by1 = @min(@as(i32, y0) + h, cl.y1);
    if (bx1 > bx0 and by1 > by0) {
        const last: u64 = @as(u64, @intCast(by1 - 1)) * ds + @as(u64, @intCast(bx1));
        if (@as(u64, d_base) + last > G.region) return; // destInRegion refuses
    }
    var j: u16 = 0;
    while (j < h) : (j += 1) {
        var i: u16 = 0;
        while (i < w) : (i += 1) {
            const px = @as(i32, x0) + i;
            const py = @as(i32, y0) + j;
            if (px >= cl.x0 and px < cl.x1 and py >= cl.y0 and py < cl.y1)
                region[d_base + @as(usize, @intCast(py)) * ds + @as(usize, @intCast(px))] = fg;
        }
    }
}

fn check(region_a: []u8, region_b: []u8, rng: std.Random, off: usize, stride: u16, rows: u16) !void {
    rng.bytes(region_a);
    @memcpy(region_b, region_a);
    const v = rng.int(u8);
    const n = @as(usize, rows) * stride;
    if (!c.usable(G, off, stride, rows)) {
        // the driver falls back to the memset itself: nothing to compare
        try std.testing.expect(off < G.vram or off + n > G.region or n == 0);
        return;
    }
    @memset(region_a[off..][0..n], v); // the old clearFrameBuffer
    var i: usize = 0;
    var covered: usize = 0;
    while (c.fillAt(G, off, stride, rows, i)) |f| : (i += 1) {
        try std.testing.expect(f.h <= dstHeight(stride));
        try std.testing.expectEqual(off + covered, f.off);
        machineFill(region_b, f.off, stride, 0, 0, stride, f.h, v);
        covered += @as(usize, f.h) * stride;
    }
    try std.testing.expectEqual(n, covered);
    try std.testing.expectEqualSlices(u8, region_a, region_b);
}

test "CHISEL fills clear exactly what the memset cleared" {
    const a = try std.testing.allocator.alloc(u8, G.region);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u8, G.region);
    defer std.testing.allocator.free(b);
    var prng = std.Random.DefaultPrng.init(7);
    const rng = prng.random();
    const shapes = [_][2]u16{ .{ 320, 200 }, .{ 640, 200 }, .{ 400, 280 }, .{ 640, 400 }, .{ 320, 600 }, .{ 400, 200 }, .{ 1, 1 }, .{ 320, 1 } };
    for (shapes) |s| for (0..6) |_| {
        const n = @as(usize, s[0]) * s[1];
        const off = rng.intRangeAtMost(usize, G.vram, G.region - n);
        try check(a, b, rng, off, s[0], s[1]);
    };
    for (0..40) |_| {
        const stride = rng.intRangeAtMost(u16, 1, 800);
        const rows = rng.intRangeAtMost(u16, 1, 700);
        const off = rng.intRangeAtMost(usize, 0, G.region);
        try check(a, b, rng, off, stride, rows);
    }
}

test "outside VRAM or past the region is a memset, never a fill" {
    try std.testing.expect(!c.usable(G, G.vram - 1, 320, 200));
    try std.testing.expect(!c.usable(G, G.region - 320 * 200 + 1, 320, 200));
    try std.testing.expect(!c.usable(G, G.vram, 0, 200));
    try std.testing.expect(c.usable(G, G.region - 320 * 200, 320, 200));
}
