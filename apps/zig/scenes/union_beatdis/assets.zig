// --------------------------------------------------------------------------
// BEAT DIS assets: the layout of beatdis.bin, the one image this screen
// depacks (tools/private_tools/union_beatdis_assets.py writes it from the
// remake's screens/beatdis/*.png, keeping canvas pixel (2x, 2y) of each).
// Index 0 is transparent, 1 the TEX loader's ink, 2 opaque black.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_beatdis/pal.dat"));
pub const INK: u8 = 1;
pub const BLACK: u8 = 2;

pub const SCREEN_W = 320; // backStLow.png / beatdis.png, 640x400
pub const SCREEN_H = 200;
pub const FRAME_H = 50; // scroll.png 640x100
pub const BACK_W = 576; // scrollback.png 1152x32
pub const BACK_H = 16;
pub const FONT_W = 480; // fonts2.png 960x700: initTile(96,100,32), 10 a row
pub const FONT_H = 350;
pub const GLYPH_W = 48;
pub const GLYPH_H = 50;
pub const FONT_COLS = 10;
pub const SPRITE = 16; // sprite?.png 32x32 (I is 24 wide, padded)
pub const SPRITE_KINDS = 7; // T H E U N I O

pub const TOTAL = 2 * SCREEN_W * SCREEN_H + SCREEN_W * FRAME_H + BACK_W * BACK_H +
    FONT_W * FONT_H + SPRITE * SPRITE_KINDS * SPRITE + GLYPH_W * GLYPH_H;

pub const Images = struct {
    background: blit.Image,
    beatdis: blit.Image,
    frame: blit.Image,
    scrollback: blit.Image,
    font: blit.Image,
    sprites: blit.Image,
    /// '!' as the canvas shows it when its x is odd: its lower half is one
    /// canvas column off the 2x grid.
    bang_odd: blit.Image,

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        var at: usize = 0;
        return .{
            .background = take(buf, &at, SCREEN_W, SCREEN_H),
            .beatdis = take(buf, &at, SCREEN_W, SCREEN_H),
            .frame = take(buf, &at, SCREEN_W, FRAME_H),
            .scrollback = take(buf, &at, BACK_W, BACK_H),
            .font = take(buf, &at, FONT_W, FONT_H),
            .sprites = take(buf, &at, SPRITE * SPRITE_KINDS, SPRITE),
            .bang_odd = take(buf, &at, GLYPH_W, GLYPH_H),
        };
    }

    fn take(buf: []const u8, at: *usize, w: usize, h: usize) blit.Image {
        defer at.* += w * h;
        return blit.Image.init(buf[at.*..][0 .. w * h], w);
    }
};
