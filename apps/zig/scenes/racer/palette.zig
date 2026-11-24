// --------------------------------------------------------------------------
// RACER: the 256-colour palette: 0 black, 1 sky (rewritten per line by the copper), 2 HUD
// paper, 3 HUD ink, 4 the ground beyond the draw distance, 12-14 the backdrop, then each ramp the
// converter names: 16 + ramp * 8 + light (its RGB is the track file's palette block).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const trk = @import("trk.zig");

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

pub fn install(fb: *zg.LogicalFB, t: *const trk.Track, ground_ramp: usize) void {
    for (0..256) |i| put(fb, i, 0, 0, 0);
    put(fb, SKY, 90, 140, 220);
    put(fb, PAPER, 0, 0, 0);
    put(fb, INK, 240, 240, 240);
    put(fb, 12, 110, 130, 170);
    put(fb, 13, 70, 100, 90);
    put(fb, 14, 60, 60, 90);
    for (t.palette, 0..) |rgb, k| {
        for (0..8) |l| put(fb, 16 + k * 8 + l, lit(rgb[0], l), lit(rgb[1], l), lit(rgb[2], l));
    }
    const g = t.palette[ground_ramp];
    put(fb, GROUND, lit(g[0], 4), lit(g[1], 4), lit(g[2], 4));
}

/// The sky's colour on each visible row: dusk blue at the top to a pale horizon at row 100.
pub fn skyFill(rows: []u32) void {
    for (rows, 0..) |*o, y| {
        const t: u32 = @as(u32, @intCast(@min(y, 100))) * 256 / 100;
        const u: u32 = 256 - t;
        const r: u8 = @intCast((28 * u + 170 * t) >> 8);
        const g: u8 = @intCast((60 * u + 205 * t) >> 8);
        const b: u8 = @intCast((150 * u + 235 * t) >> 8);
        o.* = zg.linepal.rgb(r, g, b);
    }
}
