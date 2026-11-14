// --------------------------------------------------------------------------
// KESTREL BOOT: the dawn sky, on a 400x280 RGB565 true-colour plane (the Falcon's
// hi-colour; HW 1.15.0), drawn ONCE at init from a formula: a vertical gradient
// (indigo to ember), a glow on a low horizon, a few stars, dark land below it, and a
// 4x4 ordered dither so 565 does not band. It never changes: the fade in, the flash
// and the fade out are the plane's TC_FADE / TC_OFS registers (timeline.zig).
// colourAt() is integer-only; the wordmark's letters fade in from it (marks.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const W: u32 = 400;
pub const H: u32 = 280;
pub const HORIZON: u32 = 238; // physical row: the visible window ends at 239
const GLOW_X: i32 = 200;
const GLOW_R2: i32 = 190 * 190;

pub const Rgb = struct { r: u8, g: u8, b: u8 };

const Stop = struct { y: u32, c: Rgb };
const STOPS = [_]Stop{
    .{ .y = 0, .c = .{ .r = 6, .g = 8, .b = 28 } },
    .{ .y = 110, .c = .{ .r = 30, .g = 24, .b = 72 } },
    .{ .y = 175, .c = .{ .r = 112, .g = 50, .b = 82 } },
    .{ .y = 215, .c = .{ .r = 214, .g = 108, .b = 72 } },
    .{ .y = HORIZON, .c = .{ .r = 246, .g = 176, .b = 108 } },
};

fn lerp(a: u8, b: u8, t: u32, n: u32) u32 {
    return (@as(u32, a) * (n - t) + @as(u32, b) * t) / n;
}

fn gradient(y: u32) [3]u32 {
    var i: usize = 0;
    while (i + 2 < STOPS.len and y >= STOPS[i + 1].y) i += 1;
    const a = STOPS[i];
    const b = STOPS[i + 1];
    const t = @min(y - a.y, b.y - a.y);
    const n = b.y - a.y;
    return .{ lerp(a.c.r, b.c.r, t, n), lerp(a.c.g, b.c.g, t, n), lerp(a.c.b, b.c.b, t, n) };
}

fn star(x: u32, y: u32) u32 {
    if (y >= 130) return 0;
    const h = (x *% 73856093 ^ y *% 19349663) *% 2654435761;
    if (h >> 22 != 0) return 0;
    return (80 + ((h >> 8) & 63)) * (130 - y) / 130;
}

/// The sky's colour at physical pixel (x, y), before dither.
pub fn colourAt(x: u32, y: u32) Rgb {
    if (y > HORIZON) {
        const d = (y - HORIZON) * 8 / (H - HORIZON);
        return .{ .r = @intCast(18 - d), .g = @intCast(12 - d), .b = @intCast(22 - d) };
    }
    var c = gradient(y);
    const dx: i32 = @as(i32, @intCast(x)) - GLOW_X;
    const dy: i32 = @as(i32, @intCast(HORIZON)) - @as(i32, @intCast(y));
    const g: u32 = @intCast(@divTrunc(@max(0, GLOW_R2 - dx * dx - 9 * dy * dy) * 256, GLOW_R2)); // 0..256
    c[0] += g * 80 >> 8;
    c[1] += g * 46 >> 8;
    c[2] += g * 18 >> 8;
    const s = star(x, y);
    return .{ .r = sat(c[0] + s), .g = sat(c[1] + s), .b = sat(c[2] + s) };
}

fn sat(v: u32) u8 {
    return @intCast(@min(v, 255));
}

const BAYER = [16]u8{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };

/// The whole plane, once (init).
pub fn paint(fb: zg.tc.Fb) void {
    for (0..H) |y| {
        const row = fb.row(y);
        for (0..W) |x| {
            const c = colourAt(@intCast(x), @intCast(y));
            const d: u32 = BAYER[(y & 3) * 4 + (x & 3)];
            row[x] = zg.tc.rgb565(sat(c.r + d / 2), sat(c.g + d / 4), sat(c.b + d / 2));
        }
    }
}
