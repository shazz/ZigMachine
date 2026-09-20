// --------------------------------------------------------------------------
// Emlyn Hughes assets: the layout of emlyn.bin and the one shared palette
// (tools/private_tools/replicants_emlyn_assets.py).
//
// All three PNGs are 2x art on a clean (0,0) grid, so an ST pixel is canvas
// pixel (2X, 2Y) exactly. 107 of 256 palette entries hold every colour of every
// asset: nothing is quantized. The raster buckets take 27 more above them.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const LOGO_W = 2190; // logo.png 4380x628, halved
pub const LOGO_H = 314;
pub const FONT_W = 320; // font.png 640x512, halved: 10x8 tiles of 32x32
pub const FONT_H = 256;
pub const TOTAL = LOGO_W * LOGO_H + FONT_W * FONT_H;

// The 320x240 content window inside the 400x280 overscan buffer, centred:
// (280 - 240) / 2 = 20 rows of the top AND bottom borders.
pub const CONTENT_X: usize = 40;
pub const CONTENT_Y: usize = 20;
pub const CONTENT_W: usize = 320;
pub const CONTENT_H: usize = 240;

pub const TRANSPARENT: u8 = 0;
pub const BLACK: u8 = 1; // canvas.fill('#000000'), and the closed borders
pub const BLACK_RGBA: u32 = 0xFF00_0000;
/// The art ends at 106; the raster buckets own everything from here up.
pub const FIRST_BUCKET: u8 = 107;

pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/replicants_emlyn/palette.dat"));

/// bar.png's 64 rows are each one solid colour, so halved it is 32 palette
/// indices. Those colours are the RASTER table now, never pixels: the indices
/// 2..17 they name stay in the palette but nothing is drawn in them.
const bar_rows: *const [32]u8 = @embedFile("../../assets/screens/replicants_emlyn/bar_rows.dat");
pub const bar_rgba: [32]u32 = blk: {
    var t: [32]u32 = undefined;
    for (&t, bar_rows) |*c, i| c.* = palette[i].toRGBA();
    break :blk t;
};

pub const Images = struct {
    logo: blit.Image, // 0 = transparent (logo.png's tRNS index 0)
    font: blit.Image, // 0 = transparent (font.png's alpha-0 field)

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        return .{
            .logo = blit.Image.init(buf[0 .. LOGO_W * LOGO_H], LOGO_W),
            .font = blit.Image.init(buf[LOGO_W * LOGO_H ..][0 .. FONT_W * FONT_H], FONT_W),
        };
    }
};
