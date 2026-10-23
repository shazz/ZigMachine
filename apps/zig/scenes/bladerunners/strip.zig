// --------------------------------------------------------------------------
// The scroller strip as a RING in cart RAM, so a frame writes only the two
// columns the scroll reveals instead of clearing and re-plotting 11 letters.
//
// The strip is 320 x 32: the Scrolltext letters' pixels (ink 1, else 0), as
// Sprite.render left them in a cleared buffer. Every letter moves SPEED px a
// frame, and a letter that wraps leaves at x = -32 (fully hidden) and comes back
// at x >= 318 (only the two right columns can show), so frame f's strip is frame
// f-1's shifted left by SPEED plus the columns 320-SPEED..319, which are read
// from the letters' own positions after Scrolltext.update().
//
// Each column lives twice, at c and c + L (L = 320), so the 320 columns the
// screen shows from window start `base` are always contiguous in the 640-wide
// ring: CHISEL reads them straight from cart RAM (blitImage, stride 640).
// --------------------------------------------------------------------------
const W: u16 = 320;
pub const H: u16 = 32;
pub const L: u16 = W; // the ring's period
pub const STRIDE: u16 = 2 * L;
const LETTER_W: i32 = 32;

pub const Strip = struct {
    ring: [@as(usize, STRIDE) * H]u8 align(4) = undefined,
    base: u16 = 0,

    /// Paint all 320 columns from the scroller's state as it is now.
    pub fn fill(self: *Strip, scroller: anytype) void {
        self.base = 0;
        var x: u16 = 0;
        while (x < W) : (x += 1) self.column(scroller, x);
    }

    /// The scroller moved `speed` px: shift the window, paint the new columns.
    pub fn advance(self: *Strip, scroller: anytype, speed: u16) void {
        self.base = (self.base + speed) % L;
        var x: u16 = W - speed;
        while (x < W) : (x += 1) self.column(scroller, x);
    }

    /// The window's first pixel, row `sy`, for blitImage(src, STRIDE, sx, sy...).
    pub fn windowX(self: *const Strip) u16 {
        return self.base;
    }

    // Screen column x of the strip: each letter in render order, ink over the
    // previous ones (Sprite.render skips index 0), else 0.
    fn column(self: *Strip, scroller: anytype, x: u16) void {
        const c: usize = (self.base + x) % L;
        // the letters covering x, in render order (one, two where they overlap)
        var src: [scroller.fonts.len][]const u8 = undefined;
        var n: usize = 0;
        for (&scroller.fonts) |*font| {
            const gx = @as(i32, x) - font.sprite.x_position;
            if (gx < 0 or gx >= LETTER_W) continue;
            src[n] = font.sprite.data[@intCast(gx)..];
            n += 1;
        }
        var r: usize = 0;
        while (r < H) : (r += 1) {
            var px: u8 = 0;
            for (src[0..n]) |s| {
                const v = s[r * @as(usize, LETTER_W)];
                if (v != 0) px = v;
            }
            self.ring[r * STRIDE + c] = px;
            self.ring[r * STRIDE + c + L] = px;
        }
    }
};
