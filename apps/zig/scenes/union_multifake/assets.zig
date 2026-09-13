// --------------------------------------------------------------------------
// MULTIFAKE assets: the layout of multifake.bin, the one image this screen
// depacks (tools/private_tools/union_multifake_assets.py writes it from the
// remake's screens/multifake/*.png, every PNG halved on its measured 2x grid).
// Index 0 is transparent everywhere; 1 is opaque black.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_multifake/pal.dat"));
pub const BLACK: u8 = 1;

pub const MOUNTAINS_W = 512; // mountains2.png 1024x320: 32 rows of 10 (initTile(1024,10))
pub const MOUNTAINS_H = 160;
pub const LOGO_W = 303; // logo.png 606x50: 50 rows of 1 (initTile(606,1))
pub const LOGO_H = 25;
pub const THE_W = 80; // logo2.png 160x32
pub const THE_H = 16;
pub const FONT_W = 512; // font.png 1024x256: 64x64 tiles from ' ' (initTile(64,64,32))
pub const FONT_H = 128;
pub const RASTER_ROWS = 200; // rasters.png 640x400, one colour a row

pub const TOTAL = MOUNTAINS_W * MOUNTAINS_H + LOGO_W * LOGO_H + THE_W * THE_H + FONT_W * FONT_H + RASTER_ROWS;

pub const Images = struct {
    mountains: blit.Image,
    logo: blit.Image,
    the: blit.Image,
    font: blit.Image, // 0/1: only the shape reaches the screen
    rasters: []const u8,

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        var at: usize = 0;
        const take = struct {
            fn f(b: []const u8, pos: *usize, n: usize) []const u8 {
                defer pos.* += n;
                return b[pos.*..][0..n];
            }
        }.f;
        return .{
            .mountains = blit.Image.init(take(buf, &at, MOUNTAINS_W * MOUNTAINS_H), MOUNTAINS_W),
            .logo = blit.Image.init(take(buf, &at, LOGO_W * LOGO_H), LOGO_W),
            .the = blit.Image.init(take(buf, &at, THE_W * THE_H), THE_W),
            .font = blit.Image.init(take(buf, &at, FONT_W * FONT_H), FONT_W),
            .rasters = take(buf, &at, RASTER_ROWS),
        };
    }
};
