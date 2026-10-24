// --------------------------------------------------------------------------
// LEVEL 16's two rasters (screen.js:53-54, 92-96, 121-122): raster.png at canvas
// x 340 moving up 1.8 px a frame, watergrad2.png at x 20 moving down 1.5. Both
// are one colour a row and show only through holes in the picture (the "16" in
// the logo, the water pouring into the funnel), so each is one palette entry of
// the plane, recoloured per physical row by zg.copper.
//
// A row's colour is Chrome's resample of the gradient at the fractional position
// (chrome_draw.zig), black where the image does not reach.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cd = zg.chrome_draw;
const A = @import("assets.zig");
const L = @import("lines.zig");

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
    // The gradients packed 0x00BBGGRR, one word a row: read at 3 bytes a row
    // every frame they were unaligned loads, which trap on the board.
    raster: [A.RASTER_ROWS]u32,
    water: [A.WATER_ROWS]u32,

    pub fn init(self: *Rasters) void {
        self.raster_y = RASTER_START;
        self.water_y = WATER_START;
    }

    /// Unpack the depacked gradients, once.
    pub fn bind(self: *Rasters, images: A.Images) void {
        pack(&self.raster, images.raster);
        pack(&self.water, images.water);
    }

    pub fn update(self: *Rasters) void {
        self.water_y += WATER_STEP;
        if (self.water_y > WATER_END) self.water_y = WATER_START;
        self.raster_y -= RASTER_STEP;
        if (self.raster_y < RASTER_WRAP) self.raster_y = RASTER_START;
    }

    /// This frame's colour for every physical row of both entries.
    pub fn fill(self: *const Rasters, raster: *zg.copper.Table, water: *zg.copper.Table) void {
        const raster_fy = cd.fyOf(self.raster_y); // the frame's float work: two conversions
        const water_fy = cd.fyOf(self.water_y);
        for (raster, water, 0..) |*r, *w, y| {
            const row = A.canvasRow(y);
            r.* = rowColour(&self.raster, row, raster_fy);
            w.* = rowColour(&self.water, row, water_fy);
        }
    }
};

fn pack(out: []u32, rgb: []const u8) void {
    for (out, 0..) |*c, i| c.* = @as(u32, rgb[3 * i]) | @as(u32, rgb[3 * i + 1]) << 8 | @as(u32, rgb[3 * i + 2]) << 16;
}

fn rowColour(gradient: []const u32, row: i32, y: cd.Fy) u32 {
    const t = cd.tapsFy(y, @intCast(gradient.len), row) orelse return OPAQUE; // maincanvas.fill('#000000')
    return OPAQUE | L.mixPacked(gradient[t.top], gradient[t.bottom], t.w);
}
