// Tests for effects/parallax.zig: drawLayer (row runs, @memcpy / keyed word
// stores) against the original column-by-column setPixelValue loop, over every
// scroll position, layer rows above, inside and below the plane, columns clipped
// on both sides, opaque and transparent.
const std = @import("std");
const px = @import("parallax.zig");

// The plane surface drawLayer and the old loop's setPixelValue need.
const FakeFB = struct {
    fb: [*]u8,
    fb_w: u16,
    fb_h: u16,
    stride: u16,

    fn setPixelValue(self: *FakeFB, x: u16, y: u16, v: u8) void {
        if (x < self.fb_w and y < self.fb_h) self.fb[@as(u32, y) * self.stride + x] = v;
    }
};

// The loop drawLayer replaced (negative rows are skipped where the old cast of a
// negative i16 to u16 landed past fb_h).
fn oldDraw(l: *const px.Layer, fb: *FakeFB, x0: i16, dst_w: u16) void {
    const posi: usize = @intFromFloat(l.pos);
    var dx: u16 = 0;
    while (dx < dst_w) : (dx += 1) {
        const p: i16 = x0 + @as(i16, @intCast(dx));
        if (p < 0) continue;
        const srcx: usize = (@as(usize, dx) + posi) % l.w;
        var ry: u16 = 0;
        while (ry < l.h) : (ry += 1) {
            const idx = l.raw[@as(usize, ry) * l.w + srcx];
            if (l.transparent and idx == 0) continue;
            const y = l.y + @as(i16, @intCast(ry));
            if (y < 0) continue;
            fb.setPixelValue(@intCast(p), @intCast(y), idx);
        }
    }
}

test "drawLayer draws exactly what the column loop drew" {
    var prng = std.Random.DefaultPrng.init(3);
    const rng = prng.random();
    var raw: [37 * 6]u8 = undefined;
    for (&raw) |*p| p.* = if (rng.boolean()) 0 else rng.int(u8);
    var a: [44 * 9]u8 = undefined;
    var b: [44 * 9]u8 = undefined;
    var fa = FakeFB{ .fb = &a, .fb_w = 40, .fb_h = 9, .stride = 44 };
    var fbb = FakeFB{ .fb = &b, .fb_w = 40, .fb_h = 9, .stride = 44 };
    const P = px.Parallax(1);
    for ([_]i16{ -3, 0, 6 }) |ly| for ([_]i16{ -50, -5, 0, 7, 39, 45 }) |x0| for ([_]u16{ 0, 3, 40, 90 }) |dst_w| {
        for (0..37) |pos| for ([_]bool{ false, true }) |tr| {
            const l = px.Layer{ .raw = &raw, .w = 37, .h = 6, .y = ly, .speed = 0, .transparent = tr, .pos = @floatFromInt(pos) };
            rng.bytes(&a);
            b = a;
            oldDraw(&l, &fa, x0, dst_w);
            P.drawLayer(&l, &fbb, x0, dst_w);
            try std.testing.expectEqualSlices(u8, &a, &b);
        };
    };
}
