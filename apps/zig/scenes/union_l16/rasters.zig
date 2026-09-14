// --------------------------------------------------------------------------
// LEVEL 16's two rasters (screen.js:53-54, 92-96, 121-122): raster.png at canvas
// x 340 moving up 1.8 px a frame, watergrad2.png at x 20 moving down 1.5. Both
// are one colour a row and show only through holes in the picture (the "16" in
// the logo, the water pouring into the funnel), so each is one palette entry of
// the bottom plane, recoloured per physical row by zg.copper.
//
// A row's colour is Chrome's resample of the gradient at the fractional position
// (chrome_draw.zig), black where the image does not reach.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cd = zg.chrome_draw;
const A = @import("assets.zig");

pub const RASTER_X = 340; // canvas; 160 wide
pub const RASTER_W = 160;
pub const WATER_X = 20; // canvas; 80 wide
pub const WATER_W = 80;

const RASTER_START: f64 = 165; // this.rasterpos=165
const RASTER_STEP: f64 = 1.8;
const RASTER_WRAP: f64 = 165 - 304.0 / 2.0; // if (rasterpos < 165-(304/2)) rasterpos = 165
const WATER_START: f64 = 190 - 204; // this.waterrasterpos=190-204
const WATER_STEP: f64 = 1.5;
const WATER_END: f64 = 190; // if (waterrasterpos > 190) waterrasterpos = 190-204

const OPAQUE: u32 = 0xFF00_0000;

pub const Rasters = struct {
    raster_y: f64,
    water_y: f64,

    pub fn init(self: *Rasters) void {
        self.raster_y = RASTER_START;
        self.water_y = WATER_START;
    }

    pub fn update(self: *Rasters) void {
        self.water_y += WATER_STEP;
        if (self.water_y > WATER_END) self.water_y = WATER_START;
        self.raster_y -= RASTER_STEP;
        if (self.raster_y < RASTER_WRAP) self.raster_y = RASTER_START;
    }

    /// This frame's colour for every physical row of both entries.
    pub fn fill(self: *const Rasters, raster: *zg.copper.Table, water: *zg.copper.Table, images: A.Images) void {
        for (raster, water, 0..) |*r, *w, y| {
            const row = A.canvasRow(y);
            r.* = rowColour(images.raster, row, self.raster_y);
            w.* = rowColour(images.water, row, self.water_y);
        }
    }
};

fn rowColour(gradient: []const u8, row: i32, y: f64) u32 {
    const n = gradient.len / 3;
    const t = cd.taps(y, @intCast(n), row) orelse return OPAQUE; // maincanvas.fill('#000000')
    return OPAQUE | cd.mixRgb(gradient[@as(usize, t.top) * 3 ..][0..3].*, gradient[@as(usize, t.bottom) * 3 ..][0..3].*, t.w);
}
