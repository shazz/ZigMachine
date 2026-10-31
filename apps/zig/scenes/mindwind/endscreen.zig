// --------------------------------------------------------------------------
// The end ($1AA): the borders closed, Sh3's "reservoir gods" logo as a plain
// 320x200 picture, faded in from white: every third frame the palette moves a
// sixteenth of the way ($33C: c + (t - c) * step / 16 per 3-bit channel,
// steps 0..16). On KESTREL the closed borders are blank lines and the logo's
// own colour 0 left and right of it.
// --------------------------------------------------------------------------
const data = @import("data.zig");
const lines = @import("lines.zig");
const vram = @import("vram.zig");

pub var pal: [16]u16 = [_]u16{0x777} ** 16;
var step: i16 = 0; // $27C
var wait: i16 = 0; // $27A

pub fn start() void {
    vram.initEnd();
    pal = [_]u16{0x777} ** 16;
    step = 0;
    wait = 0;
}

fn mix(a: u16, b: u16, s: i16) u16 {
    var out: u16 = 0;
    for ([3]u4{ 8, 4, 0 }) |sh| {
        const c0: i16 = @intCast((a >> sh) & 7);
        const c1: i16 = @intCast((b >> sh) & 7);
        const v = std.math.clamp(c0 + ((c1 - c0) * s >> 4), 0, 7);
        out |= @as(u16, @intCast(v)) << sh;
    }
    return out;
}
const std = @import("std");

pub fn tick() void {
    wait -= 1;
    if (wait < 0) {
        wait = 2;
        if (step <= 16) {
            const target = data.palette(data.rg_end_pal);
            for (&pal, target) |*c, t| c.* = mix(0x777, t, step);
            step += 1;
        }
    }
    const c0 = pal[0];
    lines.fill(0, 40, vram.blank, c0);
    for (0..200) |r| {
        lines.table[40 + r] = .{ .src = vram.end_pic + @as(u32, @intCast(r * vram.END_W)) - lines.CROP, .colour = c0 };
    }
    lines.fill(240, 40, vram.blank, c0);
}
