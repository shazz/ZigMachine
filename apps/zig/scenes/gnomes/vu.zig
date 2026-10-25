// --------------------------------------------------------------------------
// The three "boxes" under the logo are VU meters ($13998): one per YM channel
// (C, B, A from left to right: registers 10, 9, 8), 16 one-line bars two lines
// apart at ST lines 42..72, 64 px wide at x 48 / 128 / 208. A bar is lit (plane
// 0 set: colour 1, the doubled red-to-green ramp at $1460C) when 15 - bar <=
// the register's whole byte, so an envelope channel (bit 4) lights all 16; the
// lines between the bars are never written (colour 0, the rasters, shows).
// Only bars whose state changed since last frame are written.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

pub const Y = 42;
const X = [3]i32{ 48, 128, 208 };
const REG = [3]usize{ 10, 9, 8 };
const W = 64;

var lit: [3]u16 = undefined; // bit r: bar r lit, as last drawn

pub fn reset() void {
    @memset(&lit, 0);
}

pub fn bars(v: u8) u16 {
    var m: u16 = 0;
    for (0..16) |r| {
        if (15 - r <= v) m |= @as(u16, 1) << @intCast(r);
    }
    return m;
}

pub fn draw(d: blit.Dst, ym: []const u8) void {
    const screen = d.window(A.X0, A.Y0, 320, A.LINES);
    for (0..3) |b| {
        const m = bars(ym[REG[b]]);
        const diff = m ^ lit[b];
        if (diff == 0) continue;
        lit[b] = m;
        for (0..16) |r| {
            const bit = @as(u16, 1) << @intCast(r);
            if (diff & bit == 0) continue;
            screen.fill(X[b], @intCast(Y + 2 * r), W, 1, if (m & bit != 0) A.C1 else A.C0);
        }
    }
}
