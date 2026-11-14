// A Shade's colour, RGB 8:8:8, and the per-pixel sums that average them.
//
// The colours are the old 256-entry palette's ramps (sky horizon -> zenith, two floor
// tones dimmed by light and fogged toward the horizon, five sphere ramps black ->
// colour -> white-hot) made CONTINUOUS: the same end points and the same piecewise
// mixes, evaluated at the sample's own intensity instead of at the nearest of 8..40
// levels. So a running average of samples is itself a colour, and anti-aliasing and
// soft shadows show (the palette could not hold the colours between its ramps).
// Integers only (every engine, mode 1 included, goes through here). Pure: colour_test.zig.
const S = @import("shade.zig");

pub const Rgb = [3]u8;

const HORIZON: Rgb = .{ 255, 168, 112 };
const MIDSKY: Rgb = .{ 168, 92, 150 };
const ZENITH: Rgb = .{ 36, 56, 170 };
const BLACK: Rgb = .{ 0, 0, 0 };
const WHITE: Rgb = .{ 255, 255, 255 };
const TONES = [2]Rgb{ .{ 236, 226, 204 }, .{ 128, 28, 48 } };
const MATS = [5]Rgb{ .{ 200, 208, 226 }, .{ 226, 36, 36 }, .{ 240, 178, 36 }, .{ 40, 96, 240 }, .{ 40, 200, 90 } };

/// a + (b - a) * num / den per channel, 0 <= num <= den.
fn mix(a: Rgb, b: Rgb, num: u32, den: u32) Rgb {
    var o: Rgb = undefined;
    inline for (0..3) |i| {
        const av: i32 = a[i];
        const d: i32 = @as(i32, b[i]) - av;
        o[i] = @intCast(av + @divTrunc(d * @as(i32, @intCast(num)), @as(i32, @intCast(den))));
    }
    return o;
}

pub fn of(s: S.Shade) Rgb {
    const q: u32 = @min(s.q, 256);
    if (s.cls == S.CLS_SKY) return sky(q);
    if (s.cls < S.CLS_MAT) return mix(mix(BLACK, TONES[s.cls - S.CLS_FLOOR], q, 256), HORIZON, @min(s.fog, 256), 256);
    return sphere(MATS[s.cls - S.CLS_MAT], q);
}

/// The sky: the palette's 40 levels (horizon -> mid-sky over the first 20, then -> zenith),
/// at position q * 39 / 256 levels, kept in 1/256 of a level.
fn sky(q: u32) Rgb {
    const pos = q * 39;
    const half: u32 = 20 * 256;
    if (pos < half) return mix(HORIZON, MIDSKY, pos, half);
    return mix(MIDSKY, ZENITH, pos - half, half);
}

/// A lit sphere: black -> its colour by 78 % of full light, then toward white (the highlight).
fn sphere(c: Rgb, q: u32) Rgb {
    const pct = q * 100; // percent of full light, x256
    if (pct <= 78 * 256) return mix(BLACK, c, pct, 78 * 256);
    return mix(c, WHITE, pct - 78 * 256, 22 * 256);
}

/// A pixel's summed samples: R | G << 16 in one word, B in the other (two aligned word
/// stores: a misaligned access traps on the board). 16 samples x 255 fit 16 bits.
pub const Acc = [2]u32;

pub fn first(c: Rgb) Acc {
    return .{ @as(u32, c[0]) | @as(u32, c[1]) << 16, c[2] };
}

pub fn add(a: *Acc, c: Rgb) void {
    a[0] += @as(u32, c[0]) | @as(u32, c[1]) << 16;
    a[1] += c[2];
}

/// The mean of `n` samples per channel, as 565 levels in 1/16 of a level (R, G, B).
pub const Lev = [3]u16;

pub fn level(a: Acc, n: u32) Lev {
    return .{ lev(a[0] & 0xFFFF, n, 31), lev(a[0] >> 16, n, 63), lev(a[1], n, 31) };
}

fn lev(sum: u32, n: u32, comptime top: u32) u16 {
    return @intCast(sum * (top * 16) / (255 * n));
}

/// The 565 pixel at (x, y) of a mean: each channel rounds up by its fraction against the
/// position's 4x4 Bayer threshold, so the steps RGB565 drops (8 levels of the 8-bit sky a
/// band, ~2 rows) become a fine ordered dither instead of bands. Position-only: the picture
/// does not depend on the order it was drawn in.
pub fn pixel(l: Lev, x: u32, y: u32) u16 {
    const t: u16 = BAYER[(y & 3) * 4 + (x & 3)];
    const r: u16 = @min((l[0] + t) >> 4, 31);
    const g: u16 = @min((l[1] + t) >> 4, 63);
    const b: u16 = @min((l[2] + t) >> 4, 31);
    return r << 11 | g << 5 | b;
}

const BAYER = [16]u16{ 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };

/// The 4x4 Bayer rank 0..15 of a position (samples.zig rotates the refinement order by it).
pub fn rank(x: u32, y: u32) u32 {
    return BAYER[(y & 3) * 4 + (x & 3)];
}
