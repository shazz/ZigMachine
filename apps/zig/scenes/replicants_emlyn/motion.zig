// --------------------------------------------------------------------------
// Everything on the screen that MOVES, in one cart's numbers: the bars, the
// logo, the scrolltext and the mode. `B` is fixed.zig or float.zig. app.zig
// keeps one of each and runs only the active one (F switches, swap.zig moves
// the state across), so the per-frame work is one number system's, never both.
// What does not move — assets, blitter, the ramp under it all — is app.zig's.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");
const Logo = @import("logo.zig").Logo;
const scroller = @import("scroller.zig");
const dirty = @import("dirty.zig");
const rasters = @import("rasters.zig");

pub fn Motion(comptime B: type) type {
    return struct {
        const Self = @This();

        logo: Logo(B.Bob),
        scroller: scroller.Scroller(B.Curve, B.Mode),
        bars: B.Bars, // the vectorball group and its raster table
        mode: B.Mode, // ORIGINAL or ZIG, and how far between (mode.zig)

        pub fn init(self: *Self) void {
            self.mode.init();
            self.logo.init();
            self.scroller.init();
            self.bars.init();
        }

        /// go()'s moves. `started`: go() has drawn once, so the logo may move.
        pub fn update(self: *Self, started: bool) void {
            self.bars.turn(); // go() turns the group before drawing
            self.scroller.update();
            if (started) self.logo.move(); // ... and moves the logo after
            self.mode.update();
        }

        pub fn render(self: *Self, bl: *zg.Blitter, ramp: *dirty.Ramp, fb: *zg.LogicalFB, images: *const A.Images) void {
            // my3d.draw(), split in two: the projection is still three.js's,
            // but what it feeds is the HBL's colour table, not a blit.
            self.bars.build(&self.mode);
            rasters.loadFirstLine(fb); // the VBL palette load: line 0 is set
            // Rasters, then the logo, then the scrolltext — the remake's order.
            // All three take the WHOLE raster now: nothing stops at an edge
            // this screen no longer has. The ramp is only put back where last
            // frame drew over it (dirty.zig).
            const logo = self.logo.rect(fb, images.logo);
            const opaque_logo = ramp.prepare(bl, fb, logo);
            self.logo.draw(bl, fb, images.logo, logo, if (opaque_logo) null else dirty.LOGO_KEY);
            self.scroller.draw(blit.Dst.plane(fb), images.font, &self.mode);
            ramp.drew(logo, scroller.band(self.mode.flat()));
        }
    };
}
