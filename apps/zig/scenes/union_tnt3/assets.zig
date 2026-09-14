// --------------------------------------------------------------------------
// TNT3 assets: the layout of tnt3.bin (tools/private_tools/union_tnt3_assets.py
// halves screens/tnt3/stars.png and fonts.png, both clean on the (0,0) 2x grid)
// and the one palette: the PNGs' colours, then every object colour of
// screen.js, each its own entry.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const STARS_W = 320; // stars.png 640x400, drawn at (0,0)
pub const STARS_H = 200;
pub const FONT_W = 128; // fonts.png 256x72: 16x18 tiles from ' ' (initTile(16,18,32))
pub const FONT_H = 36;
pub const TOTAL = STARS_W * STARS_H + FONT_W * FONT_H;

pub const BLACK: u8 = 1; // the stars' black, also the scroller band's
pub const RED: u8 = 5; // the font's ink, #E00000
const FIRST_OBJECT = 6;

/// screen.js's material colours, in order of first use.
const OBJECT_COLORS = [_]u24{
    0xFF0000, 0xFFFFFF, 0x00FF00, 0x0000FF, // sphere col1..col4
    0xE00000, 0x616263, 0x7F8083, 0xA09FA3, // tntcol1..4
    0xA00000, 0xA0A0A0, 0x606060, 0x808080, 0x606000, 0x4040C0, 0x808000, 0xA0A000, // glidercol1..8
    0xC0A000, 0x00A000, 0x80A0E0, // carriercol2, 4, 5 (1 and 3 are glider colours)
    0xE0A000, 0xE0E000, 0xC0C000, // the U's own
};

pub const palette = blk: {
    var p = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_tnt3/pal.dat"));
    for (OBJECT_COLORS, FIRST_OBJECT..) |c, i| p[i] = .{ .r = c >> 16, .g = (c >> 8) & 0xFF, .b = c & 0xFF, .a = 255 };
    break :blk p;
};

/// The palette entry of an object colour.
pub fn ink(comptime rgb: u24) u8 {
    return comptime blk: {
        for (OBJECT_COLORS, FIRST_OBJECT..) |c, i| if (c == rgb) break :blk i;
        @compileError("colour not in OBJECT_COLORS");
    };
}

pub const Images = struct {
    stars: blit.Image,
    font: blit.Image, // 0 black field, 1 ink

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        return .{
            .stars = blit.Image.init(buf[0 .. STARS_W * STARS_H], STARS_W),
            .font = blit.Image.init(buf[STARS_W * STARS_H ..][0 .. FONT_W * FONT_H], FONT_W),
        };
    }
};
