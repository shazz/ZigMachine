// --------------------------------------------------------------------------
// The full-redraw present this cart shipped with, kept as the reference model
// for present_test.zig: every plane byte from the shader's index math, every
// frame (background, then the six balls, then the text), one byte at a time.
// Native tests only; the cart draws through present.zig.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");
const Clock = @import("clock.zig").Clock;
const textmod = @import("text.zig");
const project = @import("present.zig").project;

const W: usize = 320;
const H: usize = 200;

fn drawBall(px: []u8, c: *const Clock, slot: usize) void {
    const p = c.history[slot * 11];
    const pr = project(p[0], p[1], p[2]);
    if (!pr.visible) return;
    const bbase = pr.image * 1024;
    for (0..32) |yy| {
        const sy: i32 = @as(i32, pr.y) + @as(i32, @intCast(yy));
        if (sy < 0 or sy >= H) continue;
        for (0..32) |xx| {
            const shade = assets.p2(assets.balls, bbase + yy * 32 + xx);
            if (shade == 0) continue;
            const sx: i32 = @as(i32, pr.x) + @as(i32, @intCast(xx));
            if (sx < 0 or sx >= W) continue;
            const o = @as(usize, @intCast(sy)) * W + @as(usize, @intCast(sx));
            px[o] = (px[o] & ~@as(u8, 3)) | shade; // i = (i/4)*4 + shade
        }
    }
}

fn drawGlyph(px: []u8, stream: *const textmod.Stream, slot: usize) void {
    const s = stream.slot(slot);
    if (s.glyph < 0) return;
    const g: usize = @intCast(s.glyph);
    const x0: usize = 16 + 8 * slot;
    for (0..16) |yy| {
        const gbase = g * 512 + yy * 32 + @as(usize, s.index) * 8;
        for (0..8) |k| {
            if (assets.bit(assets.font, gbase + k) != 0) {
                const o = yy * W + x0 + k;
                px[o] = (px[o] & 7) | 8; // text.a>0 -> i = i%8 + 8
            }
        }
    }
}

pub fn present(px: []u8, c: *const Clock, stream: *const textmod.Stream, live: bool) void {
    const frame: usize = (c.tick + (assets.BAND_FRAMES - 1)) % assets.BAND_FRAMES;
    for (0..H) |y| {
        const base = y * W;
        if (y < assets.BAND_TOP) {
            for (0..W) |x| px[base + x] = assets.p2(assets.bg_static, base + x) * 4;
        } else {
            const bbase = frame * (assets.BAND_ROWS * W) + (y - assets.BAND_TOP) * W;
            for (0..W) |x| px[base + x] = assets.p2(assets.bg_band, bbase + x) * 4;
        }
    }
    if (!live) return;
    for (0..6) |i| drawBall(px, c, i);
    for (0..textmod.CAP) |i| drawGlyph(px, stream, i);
}
