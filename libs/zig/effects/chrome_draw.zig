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

/// Canvas row `row` of image rows part_y .. part_y+part_h (drawImage's source
/// rectangle) of an image `image_h` rows tall, drawn with its top at y; null
/// when Chrome does not draw that row.
pub fn partTaps(y: f64, part_y: u16, part_h: u16, image_h: u16, row: i32) ?Taps {
    if (part_h == 0 or image_h == 0) return null;
    const fy: f64 = @as(f32, @floatCast(y));
    const r: f64 = @floatFromInt(row);
    if (!(fy < r + 0.5 and r + 0.5 <= fy + @as(f64, @floatFromInt(part_h)))) return null;
    const v = r - fy;
    const top = @floor(v);
    const first = @as(f64, @floatFromInt(part_y)) + top;
    return .{
        .top = clampRow(first, image_h),
        .bottom = clampRow(first + 1, image_h),
        .w = @intFromFloat(@floor((v - top) * 16)),
    };
}

fn clampRow(r: f64, h: u16) u16 {
    return @intFromFloat(std.math.clamp(r, 0, @as(f64, @floatFromInt(h - 1))));
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
