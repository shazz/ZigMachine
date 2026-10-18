// Tests for effects/chisel_clear.zig: the CHISEL fills a plane clear or a
// blit.Dst.fill box issues, run through the machine's FILL (machine/blitter.zig
// execute + doFill, the plain-colour path, kept verbatim below), leave a fake
// video region byte for byte as the memsets they replace -- for random planes
// of the real shapes (320x200, 640x200 medium, 400x280 fullscreen, tall scroll
// buffers), boxes inside them and random ones, anywhere in the region.
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

// The old fills: clearFrameBuffer's one memset (w = stride) and blit.Dst.fill's
// memset a row.
fn oldFill(region: []u8, off: usize, stride: u16, w: u16, rows: u16, v: u8) void {
    if (w == stride) return @memset(region[off..][0 .. @as(usize, rows) * stride], v);
    for (0..rows) |r| @memset(region[off + r * stride ..][0..w], v);
}

fn check(region_a: []u8, region_b: []u8, rng: std.Random, off: usize, stride: u16, w: u16, rows: u16) !void {
    rng.bytes(region_a);
    @memcpy(region_b, region_a);
    const v = rng.int(u8);
    if (!c.usable(G, off, stride, w, rows)) {
        // the driver writes nothing; its caller fills the old way
        const end = off + (@as(usize, rows) -| 1) * stride + w;
        try std.testing.expect(off < G.vram or end > G.region or w == 0 or w > stride or rows == 0);
        return;
    }
    oldFill(region_a, off, stride, w, rows, v);
    var i: usize = 0;
    var done: usize = 0;
    while (c.fillAt(G, off, stride, rows, i)) |f| : (i += 1) {
        try std.testing.expect(f.h <= dstHeight(stride));
        try std.testing.expectEqual(off + done * stride, f.off);
        machineFill(region_b, f.off, stride, 0, 0, w, f.h, v);
        done += f.h;
    }
    try std.testing.expectEqual(@as(usize, rows), done);
    try std.testing.expectEqualSlices(u8, region_a, region_b);
}

test "CHISEL fills write exactly what the memsets wrote" {
    const a = try std.testing.allocator.alloc(u8, G.region);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u8, G.region);
    defer std.testing.allocator.free(b);
    var prng = std.Random.DefaultPrng.init(7);
    const rng = prng.random();
    const shapes = [_][2]u16{ .{ 320, 200 }, .{ 640, 200 }, .{ 400, 280 }, .{ 640, 400 }, .{ 320, 600 }, .{ 400, 200 }, .{ 1, 1 }, .{ 320, 1 } };
    for (shapes) |s| for (0..6) |k| {
        const n = @as(usize, s[0]) * s[1];
        const off = rng.intRangeAtMost(usize, G.vram, G.region - n);
        // whole plane, then a box inside it
        const w = if (k % 2 == 0) s[0] else rng.intRangeAtMost(u16, 1, s[0]);
        try check(a, b, rng, off, s[0], w, s[1]);
    };
    for (0..60) |_| {
        const stride = rng.intRangeAtMost(u16, 1, 800);
        const w = rng.intRangeAtMost(u16, 0, 820);
        const rows = rng.intRangeAtMost(u16, 0, 700);
        const off = rng.intRangeAtMost(usize, 0, G.region);
        try check(a, b, rng, off, stride, w, rows);
    }
}

test "outside VRAM, past the region or wider than the stride: no fill" {
    try std.testing.expect(!c.usable(G, G.vram - 1, 320, 320, 200));
    try std.testing.expect(!c.usable(G, G.region - 320 * 200 + 1, 320, 320, 200));
    try std.testing.expect(!c.usable(G, G.vram, 0, 0, 200));
    try std.testing.expect(!c.usable(G, G.vram, 320, 321, 2));
    try std.testing.expect(c.usable(G, G.region - 320 * 200, 320, 320, 200));
    try std.testing.expect(c.usable(G, G.region - 320 * 199 - 16, 320, 16, 200));
}

// machine/blitter.zig doBlit, ascending, D = B (MT_B, USEB), KEY_EN when `key`.
fn machineCopy(region: []u8, d_base: usize, ds: u16, b: []const u8, bs: u16, w: u16, h: u16, key: ?u8) void {
    var j: u16 = 0;
    while (j < h) : (j += 1) {
        if (j >= dstHeight(ds)) continue; // py outside the clip
        var i: u16 = 0;
        while (i < w) : (i += 1) {
            if (i >= ds) continue;
            const p = b[@as(usize, j) * bs + i];
            if (key) |k| if (p == k) continue;
            region[d_base + @as(usize, j) * ds + i] = p;
        }
    }
}

test "CHISEL copies (runs with B moved down) write exactly what blit.blit's copy ink wrote" {
    const blit = @import("blit.zig");
    const a = try std.testing.allocator.alloc(u8, G.region);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u8, G.region);
    defer std.testing.allocator.free(b);
    const src = try std.testing.allocator.alloc(u8, 400 * 600);
    defer std.testing.allocator.free(src);
    var prng = std.Random.DefaultPrng.init(11);
    const rng = prng.random();
    const strides = [_]u16{ 320, 400, 640, 333 };
    for (0..48) |t| {
        const stride = strides[t % strides.len];
        const sw = rng.intRangeAtMost(u16, 1, 400);
        const sh = rng.intRangeAtMost(u16, 1, 600);
        for (src[0 .. @as(usize, sw) * sh]) |*p| p.* = if (rng.boolean()) 0 else rng.int(u8);
        const w = rng.intRangeAtMost(u16, 1, @min(sw, stride));
        const h = rng.intRangeAtMost(u16, 1, sh);
        const off = rng.intRangeAtMost(usize, G.vram, G.region - @as(usize, h) * stride);
        const key: ?u8 = if (t % 2 == 0) 0 else null;
        rng.bytes(a);
        @memcpy(b, a);
        const img = blit.Image.init(src[0 .. @as(usize, sw) * sh], sw);
        const dst = blit.Dst{ .buf = a[off..][0 .. (@as(usize, h) - 1) * stride + w], .stride = stride, .w = w, .h = h };
        blit.blit(dst, img, .{ .x = 0, .y = 0, .w = w, .h = h }, 0, 0, key, .copy);
        try std.testing.expect(c.usable(G, off, stride, w, h));
        var i: usize = 0;
        var first: usize = 0;
        while (c.fillAt(G, off, stride, h, i)) |f| : (i += 1) {
            machineCopy(b, f.off, stride, src[first * sw ..], sw, w, f.h, key);
            first += f.h;
        }
        try std.testing.expectEqual(@as(usize, h), first);
        try std.testing.expectEqualSlices(u8, a, b);
    }
}
