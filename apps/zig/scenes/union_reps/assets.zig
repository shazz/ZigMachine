// --------------------------------------------------------------------------
// REPS assets: the layout of reps.bin, the one image this screen depacks
// (tools/private_tools/union_reps_assets.py writes it from the remake's
// screens/reps/*.png, each halved on its measured (0,0) 2x grid).
// Index 0 is transparent everywhere; the palette's first 26 slots are fixed.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_reps/pal.dat"));
pub const BLACK: u8 = 1; // maincanvas.fill('#000000')
pub const RED_INK: u8 = 2; // fontRed.png's one colour
pub const BLUE_INK: u8 = 3; // fontBlue.png's

/// theunion.png's soft edges (alpha 204, 84, 171) land only on these: the four
/// overlay colours under them and the two scroller inks. Blend row k starts at
/// BLEND_BASE + 6k and is ordered like BLEND_UNDER; the halved theunion image
/// stores a soft pixel as its row's first index.
pub const BLEND_UNDER = [_]u8{ 4, 5, 6, 7, RED_INK, BLUE_INK };
pub const BLEND_BASE: u8 = 8;
pub const BLEND_END: u8 = BLEND_BASE + 3 * BLEND_UNDER.len;

pub const W = 320;
pub const OVERLAY_H = 200; // overlay.png 640x400
pub const MASK_H = 54; // rastersOverlay.png 640x108, 0/1
pub const UNION_H = 43; // theunion.png 640x86
pub const FONT_W = 512; // fontBlue.png 1024x256, 64x64 tiles from ' ' (initTile(64,64,32)), 0/1
pub const FONT_H = 128;
pub const SPRITE = 16; // sprite?.png 32x32
pub const SPRITE_LETTERS = "THERPLICANS"; // spriteSpace.png is blank
pub const RASTER_ROWS = 84; // rasters.png 640x168, one colour a row
pub const PINK_ROWS = 14; // rastersPink.png 640x28
pub const GREEN_ROWS = 14; // rastersGreen.png 640x28
pub const BROWN_ROWS = 15; // rastersBrown.png 640x30

pub const TOTAL = W * (OVERLAY_H + MASK_H + UNION_H) + FONT_W * FONT_H +
    SPRITE_LETTERS.len * SPRITE * SPRITE + RASTER_ROWS + PINK_ROWS + GREEN_ROWS + BROWN_ROWS;

pub const Images = struct {
    overlay: blit.Image,
    mask: blit.Image,
    theunion: blit.Image,
    font: blit.Image,
    sprites: [SPRITE_LETTERS.len]blit.Image,
    rasters: []const u8,
    pink: []const u8,
    green: []const u8,
    brown: []const u8,

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        var r = Reader{ .buf = buf, .at = 0 };
        var self: Images = undefined;
        self.overlay = blit.Image.init(r.take(W * OVERLAY_H), W);
        self.mask = blit.Image.init(r.take(W * MASK_H), W);
        self.theunion = blit.Image.init(r.take(W * UNION_H), W);
        self.font = blit.Image.init(r.take(FONT_W * FONT_H), FONT_W);
        for (&self.sprites) |*s| s.* = blit.Image.init(r.take(SPRITE * SPRITE), SPRITE);
        self.rasters = r.take(RASTER_ROWS);
        self.pink = r.take(PINK_ROWS);
        self.green = r.take(GREEN_ROWS);
        self.brown = r.take(BROWN_ROWS);
        return self;
    }
};

const Reader = struct {
    buf: []const u8,
    at: usize,

    fn take(self: *Reader, n: usize) []const u8 {
        defer self.at += n;
        return self.buf[self.at..][0..n];
    }
};
