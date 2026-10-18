// Tests for effects/glyph_line.zig: the row-span text drawer against ZigOS's
// original per-pixel blitGlyphs, for 8x8 and 6x6 fonts, strings starting off
// every edge, clips inside the target and past it, on a strided target.
const std = @import("std");
const gl = @import("glyph_line.zig");

const STRIDE = 70;
const TW = 64;
const TH = 20;

// blitGlyphs as it was (i16 coordinates, a byte per pixel).
fn oldBlitGlyphs(fb: [*]u8, fb_w: i16, fb_h: i16, text: []const u8, x: i16, y: i16, ink: u8, paper: u8, font: []const u8, fw: i16, fh: i16, clip: gl.Clip) void {
    const w = @min(fb_w, @as(i16, @intCast(clip.x1)));
    const h = @min(fb_h, @as(i16, @intCast(clip.y1)));
    const x_lo = @max(0, @as(i16, @intCast(clip.x0)));
    const y_lo = @max(0, @as(i16, @intCast(clip.y0)));
    const cell: usize = @intCast(fw * fh);
    for (text, 0..) |char, nb| {
        const gx = x + @as(i16, @intCast(nb)) * fw;
        if (gx >= w) return;
        if (gx + fw <= x_lo) continue;
        const g0 = @as(usize, char) * cell;
        var r: i16 = 0;
        while (r < fh) : (r += 1) {
            const py = y + r;
            if (py < y_lo or py >= h) continue;
            const row = @as(u32, @intCast(py)) * STRIDE;
            var c: i16 = 0;
            while (c < fw) : (c += 1) {
                const px = gx + c;
                if (px < x_lo or px >= w) continue;
                const on = font[g0 + @as(usize, @intCast(r * fw + c))] == 1;
                fb[row + @as(u32, @intCast(px))] = if (on) ink else paper;
            }
        }
    }
}

test "draw writes exactly what the per-pixel blitGlyphs wrote" {
    var prng = std.Random.DefaultPrng.init(9);
    const rng = prng.random();
    var font: [128 * 64]u8 = undefined;
    for (&font) |*p| p.* = rng.uintLessThan(u8, 2);
    const text = "Hi, ZIGGY! 0123";
    const clips = [_]gl.Clip{ .{ .x0 = 0, .y0 = 0, .x1 = 32767, .y1 = 32767 }, .{ .x0 = 5, .y0 = 3, .x1 = 41, .y1 = 12 }, .{ .x0 = -4, .y0 = -4, .x1 = 30, .y1 = 30 } };
    var a: [STRIDE * TH]u8 = undefined;
    var b: [STRIDE * TH]u8 = undefined;
    for ([_]i16{ 8, 6 }) |f| for (clips) |clip| {
        var y: i16 = -9;
        while (y <= TH) : (y += 2) {
            var x: i16 = -50;
            while (x <= TW) : (x += 3) for ([_]usize{ 0, 1, 4, text.len }) |len| {
                rng.bytes(&a);
                b = a;
                oldBlitGlyphs(&a, TW, TH, text[0..len], x, y, 7, 2, &font, f, f, clip);
                gl.draw(.{ .fb = &b, .stride = STRIDE, .w = TW, .h = TH }, text[0..len], x, y, 7, 2, &font, f, f, clip);
                try std.testing.expectEqualSlices(u8, &a, &b);
            };
        }
    };
}
