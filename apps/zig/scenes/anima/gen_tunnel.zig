// --------------------------------------------------------------------------
// The tunnel's tables: geometry shared with tunnel.zig, built by gen_anima.zig
// on the HOST at build time (f64 maths is fine there; the cart only indexes).
//
//   MAP   VW x VH/2 u16, the TOP HALF of the 200x140 texel screen (each texel
//         2x2 pixels): low byte = the angle around the axis (256 a turn), high
//         byte = the depth, 1/r. The bottom half is the top half turned by
//         180 degrees: same depth, angle + 128, and the texture repeats every
//         64 angle units, so the texel is the SAME -- tunnel.zig computes half
//         the screen and writes it twice.
//   TEX   64 x 64 texels, values 0..15: neon panels -- a grid of lit seams,
//         rivets, and a slow interference glow inside each panel
// --------------------------------------------------------------------------
const std = @import("std");

pub const VW = 200; // texels across the 400-pixel overscan width
pub const VH = 140; // texels down the 280 lines
pub const HALF = VH / 2;
pub const TEX_N = 64;

pub fn buildMap(out: *[VW * HALF]u16) void {
    for (0..HALF) |y| for (0..VW) |x| {
        const dx = @as(f64, @floatFromInt(x)) - VW / 2.0 + 0.5;
        const dy = @as(f64, @floatFromInt(y)) - VH / 2.0 + 0.5;
        const r = @sqrt(dx * dx + dy * dy);
        var a = std.math.atan2(dy, dx) / (2.0 * std.math.pi) * 256.0;
        if (a < 0) a += 256.0;
        const d = @min(255.0, 2600.0 / @max(r, 1.0));
        const ai: u16 = @as(u16, @intFromFloat(a)) & 255;
        const di: u16 = @intFromFloat(d);
        out[y * VW + x] = di << 8 | ai;
    };
}

pub fn buildTex(out: *[TEX_N * TEX_N]u8) void {
    for (0..TEX_N) |v| for (0..TEX_N) |u| {
        const pu = u % 16;
        const pv = v % 32;
        const fu = @as(f64, @floatFromInt(u)) / TEX_N * 2.0 * std.math.pi;
        const fv = @as(f64, @floatFromInt(v)) / TEX_N * 2.0 * std.math.pi;
        // the glow inside a panel: two sines beating against each other
        const glow = (@sin(fu * 2.0 + @sin(fv * 3.0)) + @sin(fv * 2.0 - fu)) * 0.25 + 0.5;
        var c: f64 = 2.0 + glow * 6.0;
        if (pu == 0 or pv == 0) c = 15.0 // the lit seams
        else if (pu == 1 or pv == 1) c = 11.0
        else if (pu == 15 or pv == 31) c = 1.0 // their shadow
        else if ((pu == 4 or pu == 12) and (pv == 4 or pv == 28)) c = 13.0; // rivets
        out[v * TEX_N + u] = @intFromFloat(@min(15.0, @max(0.0, c)));
    };
}
