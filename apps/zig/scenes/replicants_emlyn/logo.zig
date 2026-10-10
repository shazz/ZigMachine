// --------------------------------------------------------------------------
// The big REPLICANTS logo by -PULSAR- of NEXT: 2190x314 ST pixels, seven
// screens wide, sweeping back and forth while it bobs on a sine.
//
//   mylogo.setmidhandle()                                        screen.js:68
//   mylogo.draw(mycanvas, 320 + posx, 300 + Math.sin(posy) * 300)     :100
//   if (sens) { if ((posx -= 32) < -1900) sens = 0; }                 :104
//   else      { if ((posx += 32) >  1900) sens = 1; }
//   posy += 0.02                                                      :112
//
// image.draw with three arguments is a plain drawImage at (x - handlex,
// y - handley) — no rotation, no zoom — and setmidhandle put the handle at
// parseInt(4380/2), parseInt(628/2). posx is always a multiple of 32, so the
// canvas x halves exactly; the canvas y is fractional and lands on the nearest
// ST row, which is what the hardware could do and what the browser turns out
// to do too (measured: no blend at the logo's edges).
//
// The bob is the only float in here, so it is the cart's choice: BobFixed (the
// default cart: an integer angle and the fixtrig table) or BobF32 (the f32
// cart: the remake's own accumulator and Math.sin).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const trig = zg.fixtrig;
const A = @import("assets.zig");

// Plane column X is content x + CONTENT_X, plane row Y is content y + CONTENT_Y
// — the same canvas-to-raster mapping rasters.zig uses for the ramp.
const ORIGIN_X: i32 = @intCast(A.CONTENT_X);
const ORIGIN_Y: i32 = @intCast(A.CONTENT_Y);

const HANDLE_X = A.LOGO_W / 2; // in canvas pixels: A.LOGO_W, A.LOGO_H
const HANDLE_Y = A.LOGO_H / 2;
const CX = 320; // draw(mycanvas, 320 + posx, 300 + sin(posy) * 300)
const CY = 300;
const AMP = 300;
const STEP = 32; // posx -= / += 32 ...
const LIMIT = 1900; // ... until it passes -1900 / +1900, so it turns at -+1920
const POSY_STEP = 0.02;

/// posy as an integer angle; the row from the sine table.
pub const BobFixed = struct {
    posy: trig.Angle,

    pub fn init(self: *BobFixed) void {
        self.posy = 0;
    }
    pub fn step(self: *BobFixed) void {
        self.posy +%= trig.angle(POSY_STEP);
    }
    /// (CY + sin(posy) * AMP - HANDLE_Y * 2) / 2, rounded: Q16, halved, rounded.
    pub fn row(self: *const BobFixed) i32 {
        const y = (CY - HANDLE_Y * 2) * trig.ONE + AMP * trig.sin(self.posy);
        return (y + trig.ONE) >> 17;
    }
};

/// posy as the remake has it: a float accumulator (NOT exactly periodic).
pub const BobF32 = struct {
    posy: f32,

    pub fn init(self: *BobF32) void {
        self.posy = 0;
    }
    pub fn step(self: *BobF32) void {
        self.posy += POSY_STEP;
    }
    pub fn row(self: *const BobF32) i32 {
        const y = (CY + @sin(self.posy) * AMP - HANDLE_Y * 2) / 2;
        return @intFromFloat(@round(y));
    }
};

pub fn Logo(comptime Bob: type) type {
    return struct {
        const Self = @This();
        posx: i32, // canvas pixels
        bob: Bob,
        sweeping_left: bool, // go()'s `sens`

        pub fn init(self: *Self) void {
            self.posx = 0;
            self.bob.init();
            self.sweeping_left = true; // var sens = 1
        }

        /// The tail of go(), which runs AFTER the logo is drawn.
        pub fn move(self: *Self) void {
            if (self.sweeping_left) {
                self.posx -= STEP;
                if (self.posx < -LIMIT) self.sweeping_left = false;
            } else {
                self.posx += STEP;
                if (self.posx > LIMIT) self.sweeping_left = true;
            }
            self.bob.step();
        }

        /// Drawn to the WHOLE 400x280 raster, not the content window: on a
        /// fullscreen ST screen every column is drawable, so the logo sweeps
        /// through the side borders the rasters already run into, instead of
        /// stopping at an edge that is no longer there. Only the CLIPPING
        /// changes — the position arithmetic is still the remake's.
        ///
        /// By the BLITTER, cookie-cut on the transparent index: up to 112,000
        /// keyed pixels a frame were 1.8 Mc of the cart CPU's 3.3 (measured on
        /// the board's core). The CPU only clips the 2190x314 image to the
        /// raster, so the blitter walks the visible part and nothing else.
        pub fn draw(self: *const Self, bl: *zg.Blitter, fb: *zg.LogicalFB, image: blit.Image) void {
            const x = @divExact(CX + self.posx - HANDLE_X * 2, 2) + ORIGIN_X;
            const y = self.bob.row() + ORIGIN_Y;
            const x0 = @max(0, x);
            const y0 = @max(0, y);
            const x1 = @min(@as(i32, @intCast(fb.fb_w)), x + @as(i32, @intCast(image.w)));
            const y1 = @min(@as(i32, @intCast(fb.fb_h)), y + @as(i32, @intCast(image.h)));
            if (x0 >= x1 or y0 >= y1) return;
            bl.blitImage(fb, @intCast(x0), @intCast(y0), image.data, @intCast(image.w), @intCast(x0 - x), @intCast(y0 - y), @intCast(x1 - x0), @intCast(y1 - y0), A.TRANSPARENT);
        }
    };
}
