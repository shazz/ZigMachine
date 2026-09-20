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
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;
const A = @import("assets.zig");

const HANDLE_X = A.LOGO_W / 2; // in canvas pixels: A.LOGO_W, A.LOGO_H
const HANDLE_Y = A.LOGO_H / 2;
const CX = 320; // draw(mycanvas, 320 + posx, 300 + sin(posy) * 300)
const CY = 300.0;
const AMP = 300.0;
const STEP = 32; // posx -= / += 32 ...
const LIMIT = 1900; // ... until it passes -1900 / +1900, so it turns at -+1920
const POSY_STEP = 0.02; // a float accumulator: NOT exactly periodic

pub const Logo = struct {
    posx: i32, // canvas pixels
    posy: f64,
    sweeping_left: bool, // go()'s `sens`

    pub fn init(self: *Logo) void {
        self.posx = 0;
        self.posy = 0;
        self.sweeping_left = true; // var sens = 1
    }

    /// The tail of go(), which runs AFTER the logo is drawn.
    pub fn move(self: *Logo) void {
        if (self.sweeping_left) {
            self.posx -= STEP;
            if (self.posx < -LIMIT) self.sweeping_left = false;
        } else {
            self.posx += STEP;
            if (self.posx > LIMIT) self.sweeping_left = true;
        }
        self.posy += POSY_STEP;
    }

    pub fn draw(self: *const Logo, screen: blit.Dst, image: blit.Image) void {
        const x = @divExact(CX + self.posx - HANDLE_X * 2, 2);
        const y = (CY + @sin(self.posy) * AMP - HANDLE_Y * 2) / 2;
        blit.blit(screen, image, null, x, @intFromFloat(@round(y)), A.TRANSPARENT, .copy);
    }
};
