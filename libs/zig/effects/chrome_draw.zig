// --------------------------------------------------------------------------
// Chrome draw: how Chrome's canvas drawImage() puts an image, or a part of one,
// at a FRACTIONAL y.
//
// CODEF and melonJS remakes move layers by fractional pixels (3.35 a frame on
// the Union Demo's TCB2 scroller, 1.8 on L16's letters and raster) and never
// round. The browser does not snap them: it filters. Measured against Chrome
// running the remakes (tools/chrome_capture.mjs; 0 px off on superscroller's 29
// frames and L16's 36), the legacy Skia raster path does this, for an unscaled
// image drawn at an integer x:
//
//   - the translate is an SkScalar, so y is a float32 first (with double
//     precision L16 is 945 px off at frame 339, superscroller 32,583 at 200);
//   - canvas row `row` is drawn only when its pixel centre is inside the drawn
//     rows, fy < row + 0.5 <= fy + h (top edge exclusive);
//   - it samples image rows floor(row - fy) and the next, counted from the
//     part's first row and clamped to the WHOLE image, not to the part: a
//     glyph's edge rows pick up the neighbouring glyph in its sheet;
//   - they are weighted by the TOP 4 BITS of the fraction, (a*(16-w) + b*w) >> 4
//     on premultiplied colour and alpha;
//   - then src-over as s + (d * (256 - sa)) >> 8.
//
// A fraction under 1/16 is therefore a snap, and everything else a blend.
// No ZigOS import: it tests natively (chrome_draw_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

/// The image rows a canvas row samples: `top` weighted 16 - w, `bottom` w.
pub const Taps = struct { top: u16, bottom: u16, w: u8 };

/// Canvas row `row` of a whole image `h` rows tall drawn with its top at y, or
/// null when Chrome does not draw that row.
pub fn taps(y: f64, h: u16, row: i32) ?Taps {
    return partTaps(y, 0, h, h, row);
}

/// A float32 y (what Skia's translate holds) in Q32. Exact whenever the f32's
/// ulp is a multiple of 2^-32 (|y| >= 2^-8); finer values are floored, which
/// cannot cross a half or a sixteenth (the only boundaries taps tests).
pub const Fy = i64;

const FY_LIMIT: f32 = 1073741824.0; // 2^30 rows: far off any image, kept clear of i64 overflow

/// y as Skia holds it, in Q32. The only float work: callers take it once per
/// layer per frame, not once per row, and it is single precision.
pub fn fyOf(y: f64) Fy {
    const f: f32 = std.math.clamp(@as(f32, @floatCast(y)), -FY_LIMIT, FY_LIMIT);
    return @intFromFloat(@floor(f * 4294967296.0));
}

/// Canvas row `row` of image rows part_y .. part_y+part_h (drawImage's source
/// rectangle) of an image `image_h` rows tall, drawn with its top at y; null
/// when Chrome does not draw that row.
pub fn partTaps(y: f64, part_y: u16, part_h: u16, image_h: u16, row: i32) ?Taps {
    return partTapsFy(fyOf(y), part_y, part_h, image_h, row);
}

/// partTaps for a y already in Q32: two compares, a shift and a mask, no float.
pub fn partTapsFy(fy: Fy, part_y: u16, part_h: u16, image_h: u16, row: i32) ?Taps {
    if (part_h == 0 or image_h == 0) return null;
    const centre: i64 = (@as(i64, row) << 32) + (1 << 31); // row + 0.5
    if (!(fy < centre and centre <= fy + (@as(i64, part_h) << 32))) return null;
    const v = (@as(i64, row) << 32) - fy; // > -0.5 here
    const first = @as(i64, part_y) + (v >> 32);
    return .{
        .top = clampRow(first, image_h),
        .bottom = clampRow(first + 1, image_h),
        .w = @intCast((v & 0xFFFF_FFFF) >> 28), // floor(frac * 16)
    };
}

/// taps() for a y already in Q32.
pub fn tapsFy(fy: Fy, h: u16, row: i32) ?Taps {
    return partTapsFy(fy, 0, h, h, row);
}

fn clampRow(r: i64, h: u16) u16 {
    return @intCast(std.math.clamp(r, 0, @as(i64, h) - 1));
}

/// One channel (or alpha) between the two taps.
pub fn mix(a: u8, b: u8, w: u8) u8 {
    return @intCast((@as(u16, a) * (16 - @as(u16, w)) + @as(u16, b) * w) >> 4);
}

/// Two opaque-or-clear colours (a clear one mixes in as black, premultiplied)
/// between the taps and over black, packed 0x00BBGGRR.
pub fn mixRgb(a: [3]u8, b: [3]u8, w: u8) u32 {
    var out: u32 = 0;
    for (0..3) |k| out |= @as(u32, mix(a[k], b[k], w)) << @intCast(8 * k);
    return out;
}

/// One premultiplied channel `s` with alpha `sa` over an opaque channel `d`.
pub fn srcOver(s: u8, sa: u8, d: u8) u8 {
    const v = @as(u16, s) + ((@as(u16, d) * (256 - @as(u16, sa))) >> 8);
    return @intCast(@min(v, 255));
}
