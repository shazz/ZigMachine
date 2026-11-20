// Key 5, GFA PUNCH, KESTREL: the same scene (gfa.zig) the way KESTREL draws it. The
// true-colour plane instead of 16 colours, no dither: the brightness goes through a
// continuous fire ramp (line 3's 16 ST colours, interpolated, at the MEAN of what the
// listing's dither gives: max(0, (v * 159 - 9) / 10)); and the 16-sample refinement of
// the other modes (work.zig, samples.zig's sub-pixel offsets), so the sphere's edge, the
// shadow disc and the floor's text converge smooth. The title is PRINTed in the plane
// and PTST still reads the floor's texture back from its pixels.
//
// The traced window is rows 40..199 (320 x 160, multiples of 8 for the coarse-to-fine
// preview); row 199 is the HUD's tap strip, so its samples are taken but not shown.
const zg = @import("zigos");
const gfa = @import("gfa.zig");
const colour = @import("colour.zig");
const samples = @import("samples.zig");
const work = @import("work.zig");

pub const TOP: u32 = 40;
pub const Work = work.WorkOf(320, 160);
const TAP_ROW: u32 = 199;

/// The screen as PTST sees it: a pixel not black.
pub const Screen = struct {
    fb: zg.tc.Fb,
    pub fn ptst(self: Screen, x: u32, y: u32) bool {
        return self.fb.row(y)[x] != 0;
    }
};

const JX: [samples.N]f32 = axis(0);
const JY: [samples.N]f32 = axis(1);

fn axis(comptime a: usize) [samples.N]f32 {
    var o: [samples.N]f32 = undefined;
    for (0..samples.N) |i| o[i] = @floatCast(samples.JIT[i][a]);
    return o;
}

/// Line 1 in the true-colour plane: the title in colour 15 on black.
pub fn printTitle(zigos: *zg.ZigOS, fb: zg.tc.Fb) void {
    const ink = rgb565(gfa.stRgb(gfa.PALETTE[15]));
    for (0..8) |r| {
        const row = fb.row(r);
        for (gfa.TITLE, 0..) |ch, k| {
            const g = zigos.system_font[@as(usize, ch) * 64 + r * 8 ..][0..8];
            inline for (0..8) |c| row[k * 8 + c] = if (g[c] == 1) ink else 0;
        }
    }
}

pub fn rgb565(c: [3]u8) u16 {
    return zg.tc.rgb565(c[0], c[1], c[2]);
}

/// Sample j of the window's pixel (wx, wy): the scene's brightness, through the ramp.
pub fn sample(scr: Screen, wx: u32, wy: u32, j: u32) colour.Rgb {
    const x = @as(f32, @floatFromInt(wx)) - 159 + JX[j];
    const y = 99 - @as(f32, @floatFromInt(wy + TOP)) - JY[j];
    const v = if (gfa.sphereZf(x, y)) |z|
        gfa.sphereV(x, y, z)
    else if (y < -0.05) // the horizon row stays black, as y% = 0 does
        gfa.floorV(x, y, scr)
    else if (y > 0 and y <= 24)
        gfa.skyV(y)
    else
        return .{ 0, 0, 0 };
    return ramp(v);
}

/// Brightness 0..1 -> the fire ramp at the dither's mean colour index.
pub fn ramp(v: f32) colour.Rgb {
    const p = @min(15, @max(0, (v * 159 - 9) / 10));
    const i: u32 = @intFromFloat(@floor(p));
    if (i >= 15) return gfa.stRgb(gfa.PALETTE[15]);
    const t = p - @as(f32, @floatFromInt(i));
    const a = gfa.stRgb(gfa.PALETTE[i]);
    const b = gfa.stRgb(gfa.PALETTE[i + 1]);
    var o: colour.Rgb = undefined;
    inline for (0..3) |c| {
        const av: f32 = @floatFromInt(a[c]);
        const bv: f32 = @floatFromInt(b[c]);
        o[c] = @intFromFloat(@round(av + (bv - av) * t));
    }
    return o;
}

/// Sums a sample into its pixel and shows the pixel's mean (pass 0: over its cell).
pub fn show(fb: zg.tc.Fb, acc: []colour.Acc, pass: u32, it: work.Item, c: colour.Rgb) void {
    const a = &acc[@as(u32, it.y) * 320 + it.x];
    if (pass == 0) a.* = colour.first(c) else colour.add(a, c);
    const l = colour.level(a.*, pass + 1);
    const y1 = @min(@as(u32, it.y) + it.size + TOP, TAP_ROW);
    var y: u32 = it.y + TOP;
    while (y < y1) : (y += 1) {
        const row = fb.row(y);
        var x: u32 = it.x;
        while (x < @as(u32, it.x) + it.size) : (x += 1) row[x] = colour.pixel(l, x, y);
    }
}
