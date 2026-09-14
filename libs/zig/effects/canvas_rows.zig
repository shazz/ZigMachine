// --------------------------------------------------------------------------
// Canvas row resampling: what Chrome's 2D canvas does with an UNSCALED
// drawImage at a FRACTIONAL y, which CODEF screens do every frame (a scroller
// moving 1.8 px, a raster moving 1.5).
//
// Measured against Chrome (a 4-row test image at y = 10, 10.2, 10.5, 10.8, then
// the Union Demo remake's L16 screen over its whole 832x572 canvas, 0 pixels
// wrong at 12 frames):
//   - the destination rectangle snaps: rows round(y) .. round(y)+h-1 are drawn;
//   - destination row r samples the image at v = r - y (pixel centre minus the
//     texel centre), linearly between floor(v) and floor(v)+1;
//   - the fraction is truncated to sixteenths, and a channel is
//     (a*(16-w) + b*w) >> 4 on premultiplied values;
//   - the two source rows clamp to the whole IMAGE, not to a drawn sub-rectangle:
//     a glyph's edge rows pick up the neighbouring glyph in its sheet.
// Horizontally nothing happens when x is an integer, which is the only case
// handled here.
//
// No ZigOS import: tests natively (canvas_rows_test.zig).
// --------------------------------------------------------------------------
const std = @import("std");

/// The two source rows a destination row blends, and the weight of `b` in 16ths.
pub const Tap = struct { a: usize, b: usize, w16: u8 };

/// Rows `part_y .. part_y+part_h` of an image `image_h` rows tall, drawn with their
/// top at canvas `y`: the tap for canvas row `row`, or null when the snapped
/// rectangle does not cover it.
pub fn tap(row: i32, y: f64, part_y: usize, part_h: usize, image_h: usize) ?Tap {
    const r: f64 = @floatFromInt(row);
    const top = @floor(y + 0.5); // JavaScript Math.round
    if (r < top or r >= top + @as(f64, @floatFromInt(part_h))) return null;
    const v = r - y;
    const v0 = @floor(v);
    const w16: u8 = @intFromFloat(@floor((v - v0) * 16));
    const base: i64 = @as(i64, @intCast(part_y)) + @as(i64, @intFromFloat(v0));
    const last: i64 = @intCast(image_h - 1);
    return .{
        .a = @intCast(std.math.clamp(base, 0, last)),
        .b = @intCast(std.math.clamp(base + 1, 0, last)),
        .w16 = w16,
    };
}

/// One channel of the blend.
pub fn mix(a: u8, b: u8, w16: u8) u8 {
    return @intCast((@as(u16, a) * (16 - @as(u16, w16)) + @as(u16, b) * w16) >> 4);
}

/// An opaque-or-clear colour (alpha 0 contributes black, as premultiplied) blended
/// over black, packed 0x00BBGGRR.
pub fn mixRgb(a: [3]u8, b: [3]u8, w16: u8) u32 {
    var out: u32 = 0;
    for (0..3) |k| out |= @as(u32, mix(a[k], b[k], w16)) << @intCast(8 * k);
    return out;
}
