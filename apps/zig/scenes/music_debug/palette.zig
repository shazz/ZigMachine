// --------------------------------------------------------------------------
// The music screen's comptime colour tables: the scrolltext's raster gradient
// (COPPER) and the scope's electron-flow pulse (FLOWGRAD). Float here runs in
// the compiler only, never on the board.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const Color = zg.Color;
const trsi_pal = zg.convertU8ArraytoColors(@embedFile("../../assets/logo/trsi_pal.dat"));

pub const FLOW_N: usize = 48;

// The moving band's colour: a single black -> lava -> black pulse (no repeat).
pub const FLOWGRAD = blk: {
    @setEvalBranchQuota(20000);
    const lava = [_][3]u8{ .{ 0, 0, 0 }, .{ 120, 16, 4 }, .{ 210, 40, 6 }, .{ 235, 120, 30 }, .{ 255, 210, 90 }, .{ 255, 240, 180 } };
    var t: [FLOW_N]Color = undefined;
    for (&t, 0..) |*c, k| {
        const tt = @as(f32, @floatFromInt(k)) / @as(f32, FLOW_N - 1);
        c.* = ramp(&lava, @sin(tt * std.math.pi)); // brightness 0..1..0
    }
    break :blk t;
};

// Interpolate a colour ramp (dark..bright key colours) at t in 0..1.
fn ramp(keys: []const [3]u8, t: f32) Color {
    const maxf = @as(f32, @floatFromInt(keys.len - 1));
    var ft = t * maxf;
    if (ft < 0) ft = 0;
    if (ft > maxf) ft = maxf;
    const lo: usize = @intFromFloat(ft);
    const hi = @min(keys.len - 1, lo + 1);
    const f = ft - @as(f32, @floatFromInt(lo));
    const a = keys[lo];
    const b = keys[hi];
    return Color{
        .r = @intFromFloat(@as(f32, @floatFromInt(a[0])) * (1 - f) + @as(f32, @floatFromInt(b[0])) * f),
        .g = @intFromFloat(@as(f32, @floatFromInt(a[1])) * (1 - f) + @as(f32, @floatFromInt(b[1])) * f),
        .b = @intFromFloat(@as(f32, @floatFromInt(a[2])) * (1 - f) + @as(f32, @floatFromInt(b[2])) * f),
        .a = 255,
    };
}

// Scrolltext raster gradient matching the TRSI logo: alternating metallic
// (teal-chrome) and lava (fire) bars, each a dark->bright->dark raster bar.
pub const COPPER = blk: {
    @setEvalBranchQuota(40000);
    const metal = [_][3]u8{ .{ 12, 22, 22 }, .{ 57, 89, 90 }, .{ 146, 168, 166 }, .{ 250, 252, 251 } };
    const lava = [_][3]u8{ .{ 40, 6, 3 }, .{ 195, 26, 4 }, .{ 214, 93, 31 }, .{ 238, 187, 71 }, .{ 255, 233, 131 } };
    const PERIOD = 64; // 32 metal + 32 lava
    var t: [256]Color = undefined;
    for (&t, 0..) |*c, i| {
        const pos = i % PERIOD;
        if (pos < 32) {
            const b = @sin(@as(f32, @floatFromInt(pos)) / 31.0 * std.math.pi);
            c.* = ramp(&metal, b);
        } else {
            const b = @sin(@as(f32, @floatFromInt(pos - 32)) / 31.0 * std.math.pi);
            c.* = ramp(&lava, b);
        }
    }
    break :blk t;
};

// The logo's entries from `base`: the TRSI palette's 1..31 and three dimmed
// copies at +32/+64/+96 for the darkening trail frames. Init only.
pub fn logoPalette(fb: *zg.LogicalFB, base: u8) void {
    const trail_fac = [4]f32{ 1, 0.5, 0.28, 0.14 };
    for (trail_fac, 0..) |f, k| {
        var i: u8 = 1;
        while (i < 32) : (i += 1) {
            const c = trsi_pal[i];
            fb.setPaletteEntry(base + @as(u8, @intCast(k * 32)) + i, if (k == 0) c else Color{
                .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * f),
                .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * f),
                .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * f),
                .a = 255,
            });
        }
    }
}
