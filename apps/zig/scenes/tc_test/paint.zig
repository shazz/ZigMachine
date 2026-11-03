// --------------------------------------------------------------------------
// TC TEST's still views, each a 400x280 RGB565 picture painted ONCE (init, into
// cart RAM; tc_test.zig copies one into the plane on a key). Integer maths only.
//   gamut     every 565 value: 32 tiles (R), G down, B across
//   compare   one hue x value gradient three ways: 565, the best 256-colour palette
//             (32 hues x 8 values), and 16 ST colours (8 x 2, 3 bits a channel)
//   ramps     R, G, B and grey ramps: G's 6 bits against R and B's 5
//   hues      hue x value, then hue x saturation
//   sky       a radial gradient between two close colours (the banding worst case),
//             plain or, right half, ordered-dithered 2x2
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const tc = zg.tc;

pub const W: usize = 400;
pub const H: usize = 280;
pub const WHITE: u16 = 0xFFFF;
pub const BAND_H: usize = 76; // compare: a band's rows, its label 12 rows above it
pub const BAND_STEP: usize = 92;
pub const RAMP_H: usize = 70;
pub const RAMP_LABEL: usize = 14; // ramps: rows at a band's top that carry its label

pub const Rgb = [3]u32;

/// Full-saturation hue, h in 0..1535 (six 256-step edges of the colour cube).
pub fn hue(h: u32) Rgb {
    const f = h % 256;
    return switch (h / 256 % 6) {
        0 => .{ 255, f, 0 },
        1 => .{ 255 - f, 255, 0 },
        2 => .{ 0, 255, f },
        3 => .{ 0, 255 - f, 255 },
        4 => .{ f, 0, 255 },
        else => .{ 255, 0, 255 - f },
    };
}

fn scale(c: Rgb, v: u32) Rgb {
    return .{ c[0] * v / 255, c[1] * v / 255, c[2] * v / 255 };
}

pub fn to565(c: Rgb) u16 {
    return tc.rgb565(@intCast(c[0]), @intCast(c[1]), @intCast(c[2]));
}

/// The 8x8 system font (zigos.system_font: glyph N is 64 bytes at N*64, 1 = ink), ink only.
pub fn text(fb: tc.Fb, font: []const u8, s: []const u8, x: usize, y: usize, ink: u16) void {
    for (s, 0..) |ch, i| {
        const g = font[@as(usize, ch) * 64 ..][0..64];
        for (0..8) |r| for (0..8) |c| {
            if (g[r * 8 + c] == 1) fb.put(x + i * 8 + c, y + r, ink);
        };
    }
}

pub fn gamut(fb: tc.Fb, font: []const u8) void {
    fb.fill(0);
    for (0..32) |r| {
        const x0 = 8 + (r % 12) * 32;
        const y0 = 40 + (r / 12) * 64;
        for (0..64) |g| for (0..32) |b| fb.put(x0 + b, y0 + g, @intCast(r << 11 | g << 5 | b));
    }
    text(fb, font, "RGB565: ALL 65536 COLOURS", 8, 16, WHITE);
    text(fb, font, "R A TILE, G DOWN, B ACROSS", 8, 252, WHITE);
}

// compare's gradient at (x, yy): hue across, value 255 -> 64 down the band.
fn field(x: usize, yy: usize) Rgb {
    return scale(hue(@intCast(x * 1536 / W)), @intCast(255 - yy * 191 / (BAND_H - 1)));
}

// The centre of (x, yy)'s cell when the band is cut into nx x ny cells: one colour a cell.
fn cell(x: usize, yy: usize, nx: usize, ny: usize) Rgb {
    return field((x * nx / W) * W / nx + W / nx / 2, (yy * ny / BAND_H) * BAND_H / ny + BAND_H / ny / 2);
}

pub fn compare(fb: tc.Fb, font: []const u8) void {
    fb.fill(0);
    const labels = [_][]const u8{ "RGB565: EACH PIXEL ITS OWN COLOUR", "256 COLOURS: ONE 8-BIT PALETTE", "16 COLOURS: ST, 4 BITPLANES" };
    for (labels, 0..) |l, k| {
        text(fb, font, l, 8, k * BAND_STEP + 4, WHITE);
        const y0 = k * BAND_STEP + 16;
        for (0..BAND_H) |yy| for (0..W) |x| {
            const c = switch (k) {
                0 => field(x, yy),
                1 => cell(x, yy, 32, 8),
                else => blk: {
                    const q = cell(x, yy, 8, 2);
                    break :blk Rgb{ q[0] & 0xE0, q[1] & 0xE0, q[2] & 0xE0 }; // ST: 3 bits a channel
                },
            };
            fb.put(x, y0 + yy, to565(c));
        };
    }
}

pub fn ramps(fb: tc.Fb, font: []const u8) void {
    const labels = [_][]const u8{ "R: 5 BITS, 32 STEPS", "G: 6 BITS, 64 STEPS", "B: 5 BITS, 32 STEPS", "GREY: R B 32, G 64 STEPS" };
    for (0..4) |k| for (0..RAMP_H) |yy| for (0..W) |x| {
        const r5: u16 = @intCast(x * 32 / W);
        const g6: u16 = @intCast(x * 64 / W);
        const px: u16 = switch (k) {
            0 => r5 << 11,
            1 => g6 << 5,
            2 => r5,
            else => r5 << 11 | g6 << 5 | r5,
        };
        fb.put(x, k * RAMP_H + yy, px);
    };
    for (labels, 0..) |l, k| text(fb, font, l, 4, k * RAMP_H + 3, WHITE);
}

pub fn hues(fb: tc.Fb) void {
    for (0..H) |y| for (0..W) |x| {
        const c = hue(@intCast(x * 1536 / W));
        const px = if (y < H / 2)
            scale(c, @intCast(255 - y * 235 / (H / 2)))
        else blk: { // towards white
            const s: u32 = @intCast((y - H / 2) * 255 / (H / 2 - 1));
            break :blk Rgb{ c[0] + (255 - c[0]) * s / 255, c[1] + (255 - c[1]) * s / 255, c[2] + (255 - c[2]) * s / 255 };
        };
        fb.put(x, y, to565(px));
    };
}

const SKY0 = Rgb{ 40, 80, 150 };
const SKY1 = Rgb{ 70, 112, 184 };
const BAYER = [4]u32{ 32, 160, 224, 96 }; // 2x2 ordered thresholds, in 1/256 of a 565 step

// Channel k at (x, y) in 1/256 units: radial from below the bottom centre, SKY0 -> SKY1.
fn sky16(k: usize, x: usize, y: usize) u32 {
    const dx = @as(i32, @intCast(x)) - 200;
    const dy = @as(i32, @intCast(y)) - 380;
    const d16: u32 = std.math.sqrt(@as(u32, @intCast(dx * dx + dy * dy)) << 8); // distance x 16
    const t = @min(d16, 430 * 16);
    return SKY0[k] * 256 + (SKY1[k] - SKY0[k]) * 256 * t / (430 * 16);
}

// 565 of the 16-bit channels: their top bits, or rounded up where the 2x2 threshold says.
fn skyPixel(x: usize, y: usize, dither: bool) u16 {
    const bits = [3]u5{ 5, 6, 5 };
    var px: u32 = 0;
    for (0..3) |k| {
        const shift: u5 = 16 - bits[k];
        const c = sky16(k, x, y);
        var level = c >> shift;
        const rem = (c >> (shift - 8)) & 255;
        if (dither and rem > BAYER[(y & 1) * 2 + (x & 1)] and level + 1 < (@as(u32, 1) << bits[k])) level += 1;
        px = px << bits[k] | level;
    }
    return @intCast(px);
}

pub fn sky(fb: tc.Fb, font: []const u8, split: bool) void {
    for (0..H) |y| for (0..W) |x| fb.put(x, y, skyPixel(x, y, split and x >= W / 2));
    if (!split) return;
    text(fb, font, "PLAIN 565", 8, 8, WHITE);
    text(fb, font, "2X2 DITHER", W / 2 + 8, 8, WHITE);
}
