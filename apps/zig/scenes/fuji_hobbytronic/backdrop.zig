// --------------------------------------------------------------------------
// FUJI HOBBYTRONIC: everything behind and under the logo. A three-layer
// starfield drifting left (Q8 positions, integer only), the title line, and
// the credits scroller on the bottom band, whose ink is raster.SCROLL (the HBL
// gives it a gold ramp, line by line).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const raster = @import("raster.zig");

pub const BG: u8 = 0;
pub const STAR: u8 = 1; // STAR .. STAR + 2: far, mid, near
pub const TITLE: u8 = 15;
pub const DIM: u8 = 3; // the near stars' grey doubles as the title's second ink

const NSTARS = 56;
const W = 320;
const SKY_TOP = 14; // stars stay between the title and the scroller
const SKY_H = raster.SCROLL_Y - 4 - SKY_TOP;
const SPEED = [3]u32{ 64, 128, 256 }; // Q8 px a frame, per layer

const SCROLL_TEXT_Y = raster.SCROLL_Y; // glyph row k takes the ramp's colour k
const COLS = W / 8;

pub const CREDITS =
    "FUJI HOBBYTRONIC ....  MUSIC: HOBBYTRONIC '92 - 1 BY STEPHAN DUESTERHOEFT (BENJY), 1992 ....  " ++
    "THE TUNE COMES FROM ASMA, THE ATARI SAP MUSIC ARCHIVE - ASMA.ATARI.ORG - ALL CREDIT TO THE COMPOSER AND TO THE ASMA CREW ....  " ++
    "IT RUNS AS ITS OWN 6502 CODE ON THE ZIGMACHINE'S POKEY ....  " ++
    "THE FUJI IS A SOLID IN FIXED POINT, FILLED BY THE HARDWARE BLITTER ....  " ++
    "AND THE COLOURS RUNNING THROUGH IT ARE REAL RASTERS: ONE COLOUR REGISTER REWRITTEN EVERY SCANLINE FROM THE HBL ....  " ++
    "HELLO TO EVERY ATARIAN, 8-BIT AND 16-BIT ....        ";

pub const Stars = struct {
    x: [NSTARS]u32, // Q8
    y: [NSTARS]u8,
    layer: [NSTARS]u8,

    pub fn init(self: *Stars) void {
        var seed: u32 = 0x1992_0B3B;
        for (0..NSTARS) |i| {
            seed = seed *% 1664525 +% 1013904223; // an LCG: the field is the same every boot
            self.x[i] = (seed >> 8) % (W << 8);
            self.y[i] = @intCast(SKY_TOP + (seed >> 4) % SKY_H);
            self.layer[i] = @intCast(i % 3);
        }
    }

    pub fn update(self: *Stars) void {
        for (&self.x, self.layer) |*x, l| {
            const s = SPEED[l];
            x.* = if (x.* >= s) x.* - s else x.* + (W << 8) - s;
        }
    }

    pub fn draw(self: *const Stars, fb: *zg.LogicalFB) void {
        for (self.x, self.y, self.layer) |x, y, l| fb.setPixelValue(@intCast(x >> 8), y, STAR + l);
    }
};

pub fn title(zigos: *zg.ZigOS, fb: *zg.LogicalFB) void {
    zigos.printText(fb, "HOBBYTRONIC '92", 56, 3, TITLE, BG);
    zigos.printText(fb, "BENJY 1992", 184, 3, DIM, BG);
}

/// The scroller, moved `px` pixels: only the 41 glyphs on screen are printed.
pub fn scroller(zigos: *zg.ZigOS, fb: *zg.LogicalFB, px: u32) void {
    const span: u32 = (CREDITS.len + COLS) * 8;
    const x0: i32 = W - @as(i32, @intCast(px % span));
    const first: usize = if (x0 < 0) @intCast(@divTrunc(-x0, 8)) else 0;
    if (first >= CREDITS.len) return;
    const last = @min(CREDITS.len, first + COLS + 1);
    const x: i32 = x0 + @as(i32, @intCast(first * 8));
    zigos.printText(fb, CREDITS[first..last], @intCast(x), SCROLL_TEXT_Y, raster.SCROLL, BG);
}
