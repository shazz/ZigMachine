// --------------------------------------------------------------------------
// OLDSCHOOL: the opening, an ST screen kept ST-honest. A handful of colours,
// the copper on entry 0 through borders opened by hand, a chrome logo, stars,
// a sine scroller and glenz vectors (bars.zig, logo.zig, scroller.zig,
// stars.zig, glenz.zig). Nothing clears the plane: each part of it erases only
// what it drew.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const P = @import("palette.zig");
const T = @import("timeline.zig");
const raster = @import("raster.zig");
const bars = @import("bars.zig");
const logo = @import("logo.zig");
const glenz = @import("glenz.zig");
const stars = @import("stars.zig");
const scroller = @import("scroller.zig");

pub fn enter(fb: *zg.LogicalFB, bl: *zg.Blitter) void {
    P.install(fb.palette);
    raster.use(&.{ P.BG, P.LOGO_BODY, P.FONT_BODY });
    raster.timing(fb, true);
    raster.reopen();
    bl.clear(fb, P.BG);
    logo.reset(fb, bl);
    glenz.reset();
    stars.reset();
    scroller.reset();
}

/// One frame at tick t. `fresh`: the plane was just cleared (nothing to erase);
/// `advance`: the tick moved since the last frame (the stars fly).
pub fn draw(fb: *zg.LogicalFB, bl: *zg.Blitter, t: u32, fresh: bool, advance: bool) void {
    if (!fresh) stars.erase(fb);
    raster.openAt(t);
    bars.build(t, logo.TOP, logo.BAND, scroller.TOP, scroller.BAND);
    logo.draw(fb, bl, t);
    glenz.draw(fb, bl, t);
    scroller.draw(fb, bl, t);
    if (t >= T.SCROLL) stars.draw(fb, @min(stars.N, (t - T.SCROLL) * 2), advance);
}
