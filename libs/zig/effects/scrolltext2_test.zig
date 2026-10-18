// Tests for effects/scrolltext2.zig: the word-store glyph drawer against the
// original per-pixel loop (kept here), clipped on both edges, with a
// raster whose size divides nothing, on a strided destination.
const std = @import("std");
const st2 = @import("scrolltext2.zig");

const GW = 12;
const GH = 9;
const COLS = 4;
const SHEET_W = GW * COLS;
const ROWS = 3;
const STRIDE = 70;
const DST_W = 61;

// The per-pixel loop drawGlyph replaced, verbatim but for taking the scroller.
fn oldDrawGlyph(self: anytype, dst: []u8, stride: usize, dst_w: u16, x: i32, ch: u8) void {
    const cfg = self.cfg;
    const idx: u16 = @as(u16, ch - cfg.ascii_base);
    const gcol: u16 = idx % cfg.cols;
    const grow: u16 = idx / cfg.cols;
    const sheet_w: usize = cfg.font_out_sheet_w;
    var gy: u16 = 0;
    while (gy < cfg.glyph_h) : (gy += 1) {
        const bit_row = @as(usize, grow) * cfg.glyph_h + gy;
        var gx: u16 = 0;
        while (gx < cfg.glyph_w) : (gx += 1) {
            const px = x + @as(i32, gx);
            if (px < 0 or px >= dst_w) continue;
            const bit_col = @as(usize, gcol) * cfg.glyph_w + gx;
            const sheet_off = bit_row * sheet_w + bit_col;
            const dpx: usize = @intCast(px);
            const doff = @as(usize, gy) * stride + dpx;
            const byte = cfg.font_in_bits[sheet_off / 8];
            const bit = (byte >> @intCast(7 - (sheet_off % 8))) & 1;
            if (bit == 1) {
                const rx = dpx % cfg.raster_w;
                const ry = @as(usize, gy) % cfg.raster_h;
                dst[doff] = cfg.raster[ry * @as(usize, cfg.raster_w) + rx];
            }
            const outline = cfg.font_out[sheet_off];
            if (outline != 0) dst[doff] = outline;
        }
    }
}

test "drawGlyph writes exactly what the per-pixel loop wrote" {
    var prng = std.Random.DefaultPrng.init(7);
    const rng = prng.random();
    var out: [SHEET_W * GH * ROWS]u8 = undefined;
    for (&out) |*p| p.* = if (rng.uintLessThan(u8, 3) == 0) rng.int(u8) else 0;
    var bits: [SHEET_W * GH * ROWS / 8]u8 = undefined;
    rng.bytes(&bits);
    var raster: [5 * 7]u8 = undefined;
    rng.bytes(&raster);
    var s: st2.Scroller(4) = .{};
    s.cfg = .{ .glyph_w = GW, .glyph_h = GH, .cols = COLS, .ascii_base = 32, .font_out_sheet_w = SHEET_W, .font_out = &out, .font_in_bits = &bits, .raster = &raster, .raster_w = 5, .raster_h = 7 };
    var a: [STRIDE * GH]u8 = undefined;
    var b: [STRIDE * GH]u8 = undefined;
    var x: i32 = -GW - 2;
    while (x < DST_W + 2) : (x += 1) {
        for (32..32 + COLS * ROWS) |ch| {
            rng.bytes(&a);
            b = a;
            oldDrawGlyph(&s, &a, STRIDE, DST_W, x, @intCast(ch));
            s.drawGlyph(&b, STRIDE, DST_W, x, @intCast(ch));
            try std.testing.expectEqualSlices(u8, &a, &b);
        }
    }
}
