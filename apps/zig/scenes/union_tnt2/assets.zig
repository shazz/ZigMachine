// --------------------------------------------------------------------------
// TNT2 assets: the layout of tnt2.bin, the one image this screen depacks
// (tools/private_tools/union_tnt2_assets.py writes it from the remake's
// screens/tnt2/*.png, every PNG halved on its measured (0,0) 2x grid and
// cropped to the ST rectangle holding its opaque pixels).
// Index 0 is transparent everywhere; 1 is opaque black.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const blit = zg.blit;

pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_tnt2/pal.dat"));
pub const BLACK: u8 = 1;

/// Where a cropped picture sits on the ST screen.
pub const Piece = struct { x: i32, y: i32, w: usize, h: usize };

pub const OVERLAY2 = Piece{ .x = 96, .y = 0, .w = 131, .h = 198 }; // overlay2.png, the logo's shadow
pub const BLUE = Piece{ .x = 0, .y = 0, .w = 320, .h = 200 }; // blueLayer.png
pub const BROWN = Piece{ .x = 0, .y = 40, .w = 320, .h = 120 }; // brownLayer.png
pub const GREEN = Piece{ .x = 0, .y = 64, .w = 320, .h = 72 }; // greenLayer.png
pub const OVERLAY = Piece{ .x = 99, .y = 4, .w = 131, .h = 191 }; // overlay.png, the logo
pub const FONT = Piece{ .x = 0, .y = 0, .w = 320, .h = 140 }; // fonts.png 640x280

const ORDER = [_]Piece{ OVERLAY2, BLUE, BROWN, GREEN, OVERLAY, FONT };

pub const TOTAL: usize = blk: {
    var n: usize = 0;
    for (ORDER) |p| n += p.w * p.h;
    break :blk n;
};

pub const Images = struct {
    overlay2: blit.Image,
    blue: blit.Image,
    brown: blit.Image,
    green: blit.Image,
    overlay: blit.Image,
    font: blit.Image,

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        var views: [ORDER.len]blit.Image = undefined;
        var at: usize = 0;
        for (ORDER, &views) |p, *v| {
            v.* = blit.Image.init(buf[at..][0 .. p.w * p.h], p.w);
            at += p.w * p.h;
        }
        return .{ .overlay2 = views[0], .blue = views[1], .brown = views[2], .green = views[3], .overlay = views[4], .font = views[5] };
    }
};
