// --------------------------------------------------------------------------
// The starfield (cuddly_starwars.zig, go() step 2): 400 stars rotating
// (rotc -= 0.02) and approaching (z -= 1.5), plotted as 1x1 rects at sub-pixel
// positions, which the canvas spreads over 4 pixels by area. Greys live on a
// 128-level ramp (fixed.zig) so that blend is exact.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const fixed = @import("fixed.zig");

const W: usize = zg.WIDTH;
const H: usize = zg.HEIGHT;

// the flashing logo's colours (screen_pal.dat), which a star leaves unless it mostly covers them
const BG_ORANGE: u8 = 8;
const BG_GREY: u8 = 9;

const STARS: usize = 400;
// z runs in units of 25 milli (STAR_Z_SIZE = 130 = 5200 units, lattice spacing 0.325 = 13
// units, speed 1.5 per frame = 60 units); see fixed.zig for k = 128 / z.
const STAR_Z_UNITS: i32 = 5200;
const STAR_Z_PITCH: i32 = 13;
const STAR_Z_SPEED: i32 = 60;
const STAR_GREYS = [3]u32{ 0xff, 0xaa, 0x55 }; // near .. far
const ROT_START: f64 = 180;
const ROT_STEP_C = fixed.q30(@cos(0.02));
const ROT_STEP_S = fixed.q30(@sin(-0.02)); // rot -= 0.02

// From the cart RAM arena (zg.mem) in init(): as module-scope arrays they were
// zeros in the data segment (the cart imports its memory).
var star_x: *[STARS]i16 = undefined;
var star_y: *[STARS]i16 = undefined;

pub const Stars = struct {
    rot: fixed.Rotor, // cos/sin of rotc
    base: i32, // staraddz in z units, mod STAR_Z_UNITS

    /// Allocates the star positions and seeds them: call once, from Demo.init.
    pub fn init() Stars {
        star_x = zg.mem.mustAlloc(i16, STARS)[0..STARS];
        star_y = zg.mem.mustAlloc(i16, STARS)[0..STARS];
        // Math.random() in the original; any fixed sequence is as faithful.
        var seed: u32 = 12345;
        for (0..STARS) |i| {
            star_x[i] = @intCast((@as(u64, nextRandom(&seed)) * 320) >> 32);
            star_y[i] = @intCast((@as(u64, nextRandom(&seed)) * 200) >> 32);
        }
        return .{ .rot = fixed.Rotor.at(ROT_START), .base = 0 }; // init-time float
    }

    pub fn step(self: *Stars) void {
        self.base = @mod(self.base + STAR_Z_SPEED, STAR_Z_UNITS);
        self.rot.turn(ROT_STEP_C, ROT_STEP_S);
    }

    pub fn draw(self: *const Stars, screen: []u8) void {
        const cos: i64 = self.rot.c;
        const sin: i64 = self.rot.s;
        for (0..STARS) |i| {
            var z: i32 = @as(i32, @intCast(i)) * STAR_Z_PITCH - self.base;
            if (z < 0) z += STAR_Z_UNITS;
            if (z == 0) continue; // 128/0: the canvas ignores a non-finite rect
            const dx: i64 = @as(i64, star_x[i]) - 160;
            const dy: i64 = @as(i64, star_y[i]) - 100;
            const k: i64 = fixed.star_k[@intCast(z)];
            const rx = (dx * cos - dy * sin) >> 6; // Q24
            const ry = (dx * sin + dy * cos) >> 6;
            const sx = ((rx * k) >> 24) + (160 << 16); // Q16
            const sy = ((ry * k) >> 24) + (100 << 16);
            var grey = STAR_GREYS[0];
            for (1..STAR_GREYS.len) |c| {
                if (z * 3 > STAR_Z_UNITS * @as(i32, @intCast(c))) grey = STAR_GREYS[c];
            }
            plotStar(screen, sx, sy, grey);
        }
    }
};

fn nextRandom(seed: *u32) u32 {
    seed.* = seed.* *% 1664525 +% 1013904223;
    return seed.*;
}

/// fillRect(x, y, 1, 1) at a sub-pixel position (Q16): each of the four pixels it
/// touches takes the star's grey by the area it covers.
fn plotStar(screen: []u8, x: i64, y: i64, grey: u32) void {
    const one = fixed.ONE;
    if (!(x > -@as(i64, one) and x < @as(i64, W) * one and y > -@as(i64, one) and y < @as(i64, H) * one)) return;
    const xi: i32 = @intCast(x >> 16);
    const yi: i32 = @intCast(y >> 16);
    const fx: u32 = @intCast(x & 0xffff);
    const fy: u32 = @intCast(y & 0xffff);
    for (0..2) |dy| {
        for (0..2) |dx| {
            const px = xi + @as(i32, @intCast(dx));
            const py = yi + @as(i32, @intCast(dy));
            if (px < 0 or px >= W or py < 0 or py >= H) continue;
            const wx = if (dx == 0) one - fx else fx;
            const wy = if (dy == 0) one - fy else fy;
            const cover: u32 = @intCast((@as(u64, wx) * wy) >> 16);
            if (cover == 0) continue;
            const d = &screen[@as(usize, @intCast(py)) * W + @as(usize, @intCast(px))];
            // the flashing logo is not grey: a star keeps it unless it mostly covers it
            if (d.* == BG_ORANGE or d.* == BG_GREY) {
                if (cover >= one / 2) d.* = fixed.greyIndex(grey * cover);
                continue;
            }
            d.* = fixed.greyIndex(grey * cover + @as(u32, fixed.grey_lut[d.*]) * (one - cover));
        }
    }
}
