// --------------------------------------------------------------------------
// CODEF screen 417's art, halved onto the 1x Amiga grid the remake doubled
// (tools/private_tools/tsl_hybridglenz_assets.py) and packed into one blob.
//
// ONE plane, so one 256-entry palette holds the lot. The low four indices are
// load-bearing: the glenz objects are drawn with the blitter's OR minterm, so
// the panel MUST be index 0 and a face's ink MUST be a single bit.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Color = zg.Color;

pub const Rect = struct { x: i16, y: i16, w: u16, h: u16 };

// Geometry, from the converter (960x568 -> 360x283; see tsl_hybridglenz.zig).
pub const LOGO_W = 360;
pub const LOGO_H = 94;
pub const FONT_W = 944;
pub const FONT_H = 12;
pub const TXT1 = Rect{ .x = 32, .y = 30, .w = 48, .h = 236 };
pub const TXT2 = Rect{ .x = 288, .y = 98, .w = 48, .h = 153 };
pub const TXT3 = Rect{ .x = 92, .y = 21, .w = 187, .h = 48 };

pub const KEY: u8 = 255; // cookie-cut index: only ever in a source image

// --- palette slots ---------------------------------------------------------
pub const PANEL: u8 = 0; // '#221133' inside the frame, and the glenz OR base
pub const GLENZ_R: u8 = 1; // a col1 face, alone
pub const GLENZ_W: u8 = 2; // a col2 face, alone
pub const GLENZ_RW: u8 = 3; // 1 | 2 — the two-face overlap the OR produces
pub const BG: u8 = 4; // '#334444', mycanvas.fill()
pub const WHITE: u8 = 5; // the frame border and the intro's spinning square
pub const BAR: u8 = 6; // '#660022', the scroller bar
pub const FONT_BASE: u8 = 8; // 9 inks, 8..16
pub const FONT_INKS = 9;
pub const TXT_BASE: u8 = 17; // txt1/txt2/txt3, one animated ink each
pub const LOGO_BASE: u8 = 32; // 23 colours, 32..54
pub const LOGO_PANEL: u8 = 1; // the logo's own '#221133': NOT covered by
// tsl-logowhite.png, so it must not flash white with the other 22.

// --- the blob --------------------------------------------------------------
pub const LOGO_LEN = LOGO_W * LOGO_H;
pub const FONT_LEN = FONT_W * FONT_H;
pub const TXT1_LEN = @as(usize, TXT1.w) * TXT1.h;
pub const TXT2_LEN = @as(usize, TXT2.w) * TXT2.h;
pub const TXT3_LEN = @as(usize, TXT3.w) * TXT3.h;
pub const TOTAL = LOGO_LEN + FONT_LEN + TXT1_LEN + TXT2_LEN + TXT3_LEN;

pub const Images = struct {
    logo: []const u8,
    font: []const u8,
    txt: [3][]const u8,

    pub fn split(buf: []u8) Images {
        var at: usize = 0;
        const logo = buf[at..][0..LOGO_LEN];
        at += LOGO_LEN;
        const font = buf[at..][0..FONT_LEN];
        at += FONT_LEN;
        const t1 = buf[at..][0..TXT1_LEN];
        at += TXT1_LEN;
        const t2 = buf[at..][0..TXT2_LEN];
        at += TXT2_LEN;
        const t3 = buf[at..][0..TXT3_LEN];
        return .{ .logo = logo, .font = font, .txt = .{ t1, t2, t3 } };
    }
};

// --- colours ---------------------------------------------------------------
pub const PANEL_RGB = Color{ .r = 0x22, .g = 0x11, .b = 0x33, .a = 255 };
pub const BG_RGB = Color{ .r = 0x33, .g = 0x44, .b = 0x44, .a = 255 };
pub const WHITE_RGB = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const BAR_RGB = Color{ .r = 0x66, .g = 0x00, .b = 0x22, .a = 255 };

// The 24 faces carry col1 = 0xaa0011 / col2 = 0xffffff at opacity 0.8 over the
// '#221133' panel (obj.js:114-117). Every mesh here is convex and doubleSided,
// so a covered pixel is exactly two faces deep and CanvasRenderer's painter
// gives 0.8*front + 0.16*back + 0.04*panel. Those four results ARE these
// entries; the OR minterm cannot tell red-over-white from white-over-red, so
// index 3 is their mean. See the glenz note in tsl_hybridglenz.zig.
pub const GLENZ_R_RGB = Color{ .r = 165, .g = 1, .b = 18, .a = 255 }; // red over red
pub const GLENZ_W_RGB = Color{ .r = 246, .g = 245, .b = 247, .a = 255 }; // white over white
pub const GLENZ_RW_RGB = Color{ .r = 205, .g = 123, .b = 133, .a = 255 }; // mean of the mixed pair

pub const LOGO_COLORS = [_]Color{
    .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    .{ .r = 34, .g = 17, .b = 51, .a = 255 },
    .{ .r = 51, .g = 34, .b = 68, .a = 255 },
    .{ .r = 68, .g = 51, .b = 85, .a = 255 },
    .{ .r = 85, .g = 0, .b = 0, .a = 255 },
    .{ .r = 85, .g = 68, .b = 102, .a = 255 },
    .{ .r = 102, .g = 85, .b = 119, .a = 255 },
    .{ .r = 119, .g = 0, .b = 0, .a = 255 },
    .{ .r = 119, .g = 102, .b = 136, .a = 255 },
    .{ .r = 136, .g = 17, .b = 17, .a = 255 },
    .{ .r = 136, .g = 119, .b = 153, .a = 255 },
    .{ .r = 153, .g = 136, .b = 170, .a = 255 },
    .{ .r = 170, .g = 34, .b = 34, .a = 255 },
    .{ .r = 170, .g = 153, .b = 187, .a = 255 },
    .{ .r = 187, .g = 68, .b = 68, .a = 255 },
    .{ .r = 187, .g = 170, .b = 204, .a = 255 },
    .{ .r = 204, .g = 85, .b = 85, .a = 255 },
    .{ .r = 204, .g = 187, .b = 221, .a = 255 },
    .{ .r = 221, .g = 204, .b = 238, .a = 255 },
    .{ .r = 238, .g = 119, .b = 119, .a = 255 },
    .{ .r = 238, .g = 221, .b = 255, .a = 255 },
    .{ .r = 255, .g = 153, .b = 153, .a = 255 },
    .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

// tsl-font.png box-averaged across each column pair over the bar colour.
pub const FONT_COLORS = [_]Color{
    .{ .r = 110, .g = 51, .b = 68, .a = 255 },
    .{ .r = 119, .g = 102, .b = 102, .a = 255 },
    .{ .r = 144, .g = 85, .b = 102, .a = 255 },
    .{ .r = 153, .g = 136, .b = 136, .a = 255 },
    .{ .r = 178, .g = 128, .b = 144, .a = 255 },
    .{ .r = 187, .g = 170, .b = 170, .a = 255 },
    .{ .r = 187, .g = 178, .b = 178, .a = 255 },
    .{ .r = 221, .g = 212, .b = 212, .a = 255 },
    .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

/// The palette as it stands once every fade has finished.
pub fn palette() [256]Color {
    var p = [_]Color{.{ .r = 0, .g = 0, .b = 0, .a = 255 }} ** 256;
    p[PANEL] = PANEL_RGB;
    p[GLENZ_R] = GLENZ_R_RGB;
    p[GLENZ_W] = GLENZ_W_RGB;
    p[GLENZ_RW] = GLENZ_RW_RGB;
    p[BG] = BG_RGB;
    p[WHITE] = WHITE_RGB;
    p[BAR] = BAR_RGB;
    for (FONT_COLORS, 0..) |c, i| p[FONT_BASE + i] = c;
    for (0..3) |i| p[TXT_BASE + i] = BG_RGB; // invisible until their cue
    for (LOGO_COLORS, 0..) |c, i| p[LOGO_BASE + i] = c;
    return p;
}
