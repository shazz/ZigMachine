// --------------------------------------------------------------------------
// A blitter FILL anywhere on a screen taller than a plane. The machine clips a
// destination narrower than the raster at the plane height, 200 rows
// (machine/blitter_regs.zig dstHeight, CHISEL fpga/rtl/blitter/zm_blit_clip.v: it knows a
// buffer only by its stride),
// and the desk mode (HW 1.17.0) is 640x480: a fill at y 300 drew nothing, so the
// desktop's colour stopped at row 200. Below a 200-row screen it is one blit, as
// before; on a taller one each 200-row band the rectangle crosses is one blit
// whose destination starts at that band, clipped HERE to the band and to the
// buffer's own height (the machine would clip the last band at 600 rows, past
// the end of a 480-row buffer).
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;

/// The rows the blitter covers below a destination's base (memmap.HEIGHT).
pub const BAND: i32 = 200;

pub fn fill(blit: *Blitter, fb: *LogicalFB, x: i16, y: i16, w: u16, h: u16, color: u8) void {
    if (fb.fb_h <= BAND) return blit.fill(fb, x, y, w, h, color); // every plane mode
    const top: i32 = @max(y, 0);
    const bottom: i32 = @min(@as(i32, y) + h, @as(i32, @intCast(fb.fb_h)));
    var band = @divFloor(top, BAND) * BAND;
    while (band < bottom) : (band += BAND) {
        const r0 = @max(top, band);
        const r1 = @min(bottom, band + BAND);
        var sub = fb.*;
        sub.fb = fb.fb + @as(usize, @intCast(band)) * fb.stride;
        blit.fill(&sub, x, @intCast(r0 - band), w, @intCast(r1 - r0), color);
    }
}
