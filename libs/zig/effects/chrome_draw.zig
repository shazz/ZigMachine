// --------------------------------------------------------------------------
// Chrome draw: how Chrome's canvas drawImage() puts an image at a FRACTIONAL y.
//
// CODEF and melonJS remakes move layers by fractional pixels (3.35 a frame on
// the Union Demo's TCB2 scroller) and never round. The browser does not snap
// them: it filters. Measured against Chrome running the remake (0 px off on 29
// frames, scenes/union_superscroller), the legacy Skia raster path does this,
// for an image drawn at an integer x:
//
//   - the translate is an SkScalar, so y is a float32 first;
//   - canvas row `row` is drawn only when its pixel centre is inside the
//     destination, fy < row + 0.5 <= fy + h (top edge exclusive);
//   - it samples image rows floor(row - fy) and the next, both clamped to the
//     image, weighted by the TOP 4 BITS of the fraction: (a*(16-w) + b*w) >> 4
//     on premultiplied colour and alpha;
//   - then src-over as s + (d * (256 - sa)) >> 8.
//
// A fraction under 1/16 is therefore a snap, and everything else a blend.
// No ZigOS import: it tests natively (chrome_draw_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

/// The image rows a canvas row samples: `top` weighted 16 - w, `bottom` w.
pub const Taps = struct { top: u16, bottom: u16, w: u8 };

/// Canvas row `row` of an image `h` rows tall drawn with its top at canvas y
/// `y`, or null when Chrome does not draw that row.
pub fn taps(y: f64, h: u16, row: u16) ?Taps {
    if (h == 0) return null;
    const fy: f64 = @as(f32, @floatCast(y));
    const r: f64 = @floatFromInt(row);
    if (!(fy < r + 0.5 and r + 0.5 <= fy + @as(f64, @floatFromInt(h)))) return null;
    const v = r - fy;
    const top = @floor(v);
    return .{
        .top = clampRow(top, h),
        .bottom = clampRow(top + 1, h),
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

/// One premultiplied channel `s` with alpha `sa` over an opaque channel `d`.
pub fn srcOver(s: u8, sa: u8, d: u8) u8 {
    const v = @as(u16, s) + ((@as(u16, d) * (256 - @as(u16, sa))) >> 8);
    return @intCast(@min(v, 255));
}
