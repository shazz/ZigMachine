// --------------------------------------------------------------------------
// RACER: the 256-colour palette: 0 black, 1 sky (rewritten per line by the copper), 2 HUD
// paper, 3 HUD ink, 4 the ground beyond the draw distance, 12-14 the backdrop, then each ramp the
// converter names: 16 + ramp * 8 + light (its RGB is the track file's palette block).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const carmodel = @import("carmodel.zig");
const trk = @import("trk.zig");

/// The AI cars' body colours (blue, yellow, green, white), ramps 15..18.
const LIVERY_RGB = [carmodel.LIVERIES][3]u8{ .{ 40, 90, 220 }, .{ 235, 200, 40 }, .{ 50, 170, 70 }, .{ 232, 232, 236 } };

pub const SKY: u8 = 1;
pub const PAPER: u8 = 2;
pub const INK: u8 = 3;
pub const GROUND: u8 = 4;

/// Light level l (0..7) of an 8-bit channel: 36% .. 99%.
fn lit(c: u8, l: u32) u8 {
    return @intCast((@as(u32, c) * (92 + l * 23)) >> 8);
}

fn put(fb: *zg.LogicalFB, i: usize, r: u8, g: u8, b: u8) void {
    fb.palette[i] = zg.linepal.rgb(r, g, b);
}

/// The track's palette and its mood (trk.Mood: the far ground's ramp, the backdrop's colours, the sky rows on the copper).
/// `ground_level`: the far ground's light (the mood's, or 4 under the debug shading: trackset.groundLevel).
pub fn install(fb: *zg.LogicalFB, t: *const trk.Track, ground_level: u32) void {
    for (0..256) |i| put(fb, i, 0, 0, 0);
    put(fb, SKY, 90, 140, 220);
    put(fb, PAPER, 0, 0, 0);
    put(fb, INK, 240, 240, 240);
    for (t.mood.hills, 12..) |c, i| put(fb, i, c[0], c[1], c[2]);
    for (t.palette, 0..) |rgb, k| {
        for (0..8) |l| put(fb, 16 + k * 8 + l, lit(rgb[0], l), lit(rgb[1], l), lit(rgb[2], l));
    }
    for (LIVERY_RGB, 0..) |rgb, k| {
        for (0..8) |l| put(fb, 16 + (carmodel.RAMP_LIVERY + k) * 8 + l, lit(rgb[0], l), lit(rgb[1], l), lit(rgb[2], l));
    }
    const g = t.palette[t.mood.ground_ramp];
    put(fb, GROUND, lit(g[0], ground_level), lit(g[1], ground_level), lit(g[2], ground_level));
    skyFill(zg.copper.visible(fb, 0), &t.mood);
}

/// The sky's colour on each visible row: the mood's top colour to its horizon colour at row 100 (the oval: dusk blue to pale).
pub fn skyFill(rows: []u32, m: *const trk.Mood) void {
    const a = m.sky[0];
    const h = m.sky[1];
    for (rows, 0..) |*o, y| {
        const t: u32 = @as(u32, @intCast(@min(y, 100))) * 256 / 100;
        const u: u32 = 256 - t;
        const r: u8 = @intCast((a[0] * u + h[0] * t) >> 8);
        const g: u8 = @intCast((a[1] * u + h[1] * t) >> 8);
        const b: u8 = @intCast((a[2] * u + h[2] * t) >> 8);
        o.* = zg.linepal.rgb(r, g, b);
    }
}
