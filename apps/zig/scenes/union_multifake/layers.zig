// --------------------------------------------------------------------------
// MULTIFAKE's fake parallax and its two logos (screen.js:98-124), halved from
// the 640-wide canvas to 320x200.
//
// Canvas coordinates that land between ST pixels are rounded the way the
// headless harness replays them: halve(c) = floor(round(c) / 2).
// --------------------------------------------------------------------------
const blit = @import("zigos").blit;

pub fn halve(c: f64) i32 {
    const r: i32 = @intFromFloat(@floor(c + 0.5)); // JS Math.round
    return @divFloor(r, 2);
}

/// bgspeed (screen.js:26), canvas pixels a frame, tile row 0 to 31.
const BG_SPEED = [_]f32{ 8, 7.5, 7, 6.5, 6, 5.5, 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8 };
const BANDS = BG_SPEED.len;
const TOP_BANDS = 16; // rows 0..15 at y = i*10, rows 16..31 at i*10+84 (screen.js:99-110)
const BAND_H = 5; // mountains.initTile(1024,10), halved
const BOTTOM_GAP = 42; // the 84 above, halved
const WRAP_HALF = 512; // bgpos % 256, in half canvas pixels

/// bgspeed in half canvas pixels: every entry is a multiple of 0.5, so bgpos is
/// kept exactly as an integer.
const SPEED_HALF: [BANDS]i32 = blk: {
    var s: [BANDS]i32 = undefined;
    for (BG_SPEED, 0..) |v, i| s[i] = @intFromFloat(v * 2);
    break :blk s;
};

pub const Mountains = struct {
    pos: [BANDS]i32, // bgpos in half canvas pixels, in (-512, 0]

    /// The rows between the two halves, which the mountains never cover: the
    /// only part of the black fill that survives their opaque rows.
    pub const GAP_TOP = TOP_BANDS * BAND_H;
    pub const GAP_BOTTOM = TOP_BANDS * BAND_H + BOTTOM_GAP;

    pub fn init(self: *Mountains) void {
        self.pos = @splat(0);
    }

    /// bgpos = (bgpos - bgspeed) % 256; JS % keeps the dividend's sign.
    pub fn update(self: *Mountains) void {
        for (&self.pos, SPEED_HALF) |*p, s| p.* = @rem(p.* - s, WRAP_HALF);
    }

    /// Tile row i drawn at x = bgpos: ST column X shows mountain column
    /// X - bgpos/2, rounded half up (bgpos/2 moves in quarter ST pixels).
    pub fn draw(self: *const Mountains, dst: blit.Dst, img: blit.Image) void {
        for (self.pos, 0..) |p, i| {
            const shift: usize = @intCast((2 - p) >> 2);
            const gap: usize = if (i < TOP_BANDS) 0 else BOTTOM_GAP;
            const top = i * BAND_H + gap;
            blit.blit(dst, img, .{ .x = shift, .y = i * BAND_H, .w = dst.w, .h = BAND_H }, 0, @intCast(top), null, .copy);
        }
    }
};

/// The "THE" logo, mid-handled at (300,176) and stretched vertically by
/// sin(the), the += 0.1 a frame (screen.js:113-115).
pub const The = struct {
    phase: f64, // the
    drawn: f64, // the value this frame is drawn with

    const LEFT = (300 - 160 / 2) / 2;
    const CENTRE_Y: f64 = 176.0 / 2.0;
    const STEP: f64 = 0.1;

    pub fn init(self: *The) void {
        self.phase = 0;
        self.drawn = 0;
    }

    pub fn update(self: *The) void {
        self.drawn = self.phase;
        self.phase += STEP;
    }

    pub fn draw(self: *const The, dst: blit.Dst, img: blit.Image) void {
        blit.stretchY(dst, img, LEFT, CENTRE_Y, @sin(self.drawn), 0, .copy);
    }
};

/// The CAREBEARS logo, one 1-pixel tile per canvas row (initTile(606,1)), row i
/// at x = 16 + sin(logosinx + 0.1 i) * 20, y = 194 + i; logosinx += 0.1 a frame
/// (screen.js:117-124). An ST row is the even canvas row of its pair.
pub const Carebears = struct {
    phase: f64, // logosinx
    drawn: f64, // oldlogosinx: this frame's first row

    const X: f64 = 16;
    const AMP: f64 = 20;
    const STEP: f64 = 0.1;
    const TOP = 194 / 2;
    const CANVAS_ROWS = 50;

    pub fn init(self: *Carebears) void {
        self.phase = 0;
        self.drawn = 0;
    }

    pub fn update(self: *Carebears) void {
        self.drawn = self.phase;
        self.phase = self.drawn + STEP; // logosinx = oldlogosinx + 0.1
    }

    pub fn draw(self: *const Carebears, dst: blit.Dst, img: blit.Image) void {
        var s = self.drawn; // accumulated row by row, as the JS loop does
        for (0..CANVAS_ROWS) |i| {
            if (i % 2 == 0) {
                const row = i / 2;
                blit.blit(dst, img, .{ .x = 0, .y = row, .w = img.w, .h = 1 }, halve(X + @sin(s) * AMP), @intCast(TOP + row), 0, .copy);
            }
            s += STEP;
        }
    }
};
