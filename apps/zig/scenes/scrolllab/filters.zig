// --------------------------------------------------------------------------
// CODEF's three height-field filters (codef_fx.js siny/sinx/zoomy) over the
// lab's strip, split out of modes.zig. Each walks its sum of sines in integers
// (sines.zig) and stops at the destination's right edge: the walk is a local
// copy and `advance` only moves the params' own phase, so columns past the
// screen changed nothing but cost ~380 wasted steps a frame.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blit = zg.blit;
const sines = @import("sines.zig");
const Param = sines.Param;

pub const TILE = 32; // the strip's height: one letter of the ring
pub const W = 704; // the strip's width (modes.zig says why)
pub const Strip = [TILE][W]u8;

/// codef_fx.siny: column i goes to (i, sum + posy); `stride` columns share one
/// phase step — 1 per column, TILE per letter. One keyed column copy a column,
/// written out: a 1x32 blit() paid its clip and a row call per pixel, 704 times
/// a frame.
pub fn siny(dst: blit.Dst, strip: *const Strip, params: []Param, posy: i32, travel: f64, stride: usize, align_x: usize) void {
    var w = sines.begin(params);
    const h: i32 = @intCast(dst.h);
    for (0..@min(W, dst.w)) |i| {
        const y0 = posy + sines.roundQ38(sines.sumQ38(params, &w));
        // rows clipped once a column; the key (0) is left out as blit's was
        const r0: usize = @intCast(std.math.clamp(-y0, 0, TILE));
        const r1: usize = @intCast(std.math.clamp(h - y0, 0, TILE));
        var r = r0;
        while (r < r1) : (r += 1) {
            const p = strip[r][i];
            if (p != 0) dst.buf[@as(usize, @intCast(y0 + @as(i32, @intCast(r)))) * dst.stride + i] = p;
        }
        // the LAST column of each aligned block: every column of a letter
        // shares one phase, and the step lands on the boundary between letters
        if (i % stride == (align_x + stride - 1) % stride) sines.step(params, &w, stride != 1);
    }
    sines.advance(params, travel);
}

/// codef_fx.sinx: source ROW i goes to (sum + posx, i): 32 row blits (CHISEL).
pub fn sinx(dst: blit.Dst, src: blit.Image, params: []Param, posy: i32, travel: f64) void {
    var w = sines.begin(params);
    for (0..src.h) |i| {
        const cell = blit.Rect{ .x = 0, .y = i, .w = src.w, .h = 1 };
        blit.blit(dst, src, cell, sines.roundQ38(sines.sumQ38(params, &w)), posy + @as(i32, @intCast(i)), 0, .copy);
        sines.step(params, &w, false);
    }
    sines.advance(params, travel);
}

/// codef_fx.zoomy: the sum is a vertical SCALE, the column growing downward
/// from posy. Written out: nothing here scales a single column. The source row
/// of output row r is round(r / zoom), walked as r * (1 / zoom) in Q24: one f32
/// divide a column, none a pixel.
pub fn zoomy(dst: blit.Dst, strip: *const Strip, params: []Param, posy: i32, travel: f64) void {
    var w = sines.begin(params);
    const h: i32 = TILE;
    for (0..@min(W, dst.w)) |i| {
        const zoom_q16: i32 = 65536 + @as(i32, @intCast((sines.sumQ38(params, &w) + (1 << 21)) >> 22));
        sines.step(params, &w, false);
        if (zoom_q16 <= 0) continue;
        const rows = (h * zoom_q16 + 32768) >> 16; // round(src.h * zoom)
        const inv = 65536.0 / @as(f32, @floatFromInt(zoom_q16)); // 1 / zoom
        const inv_q24: i32 = @intFromFloat(inv * 16777216.0);
        var acc: i32 = 0;
        var r: i32 = 0;
        while (r < rows) : ({
            r += 1;
            acc += inv_q24;
        }) {
            const sr = (acc + (1 << 23)) >> 24;
            const y = posy + r;
            if (sr < 0 or sr >= h or y < 0 or y >= dst.h) continue;
            const p = strip[@intCast(sr)][i];
            if (p != 0) dst.buf[@as(usize, @intCast(y)) * dst.stride + i] = p;
        }
    }
    sines.advance(params, travel);
}
