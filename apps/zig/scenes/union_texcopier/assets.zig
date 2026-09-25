// --------------------------------------------------------------------------
// TEX COPIER assets: the layout of texcopier.bin (the one image the screen
// depacks, written by tools/private_tools/union_texcopier_assets.py) and the
// shared palette, blends included.
//
// Chrome draws two things at half-pixel positions and resamples them
// bilinearly: a pixel between two texels is their 50/50 mix, each channel
// (a + b) >> 1, a transparent texel counting as black (measured against the
// remake in Chrome: 5877 of 5877 raster blends). Every mix the text line can
// make is a palette entry here, so its drawing stays palette lookups; the raster
// windows' mixes are colours of the raster register itself (raster.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Color = zg.Color;
const blit = zg.blit;

pub const DISPLAY_W = 160; // display.png 320x174, doubled
pub const DISPLAY_H = 87;
pub const FONT_W = 160; // font.png 320x42: 20x3 tiles of 16x14, doubled
pub const GLYPH_W = 8;
pub const GLYPH_H = 7;
pub const GLYPHS_PER_ROW = 20;
pub const TEXTURE_W = 1280; // fontback.png / fontbackg.png, every canvas column
pub const TEXTURE_ROWS = 7; // canvas rows 0, 2, .., 12 of the 14 drawn
pub const RASTER_IMAGES = 8; // raster1..8.png
pub const RASTER_COLOURS = 16; // rows 32..63, doubled

pub const TOTAL = DISPLAY_W * DISPLAY_H + FONT_W * GLYPH_H * 3 + 2 * TEXTURE_W * TEXTURE_ROWS + RASTER_IMAGES * RASTER_COLOURS * 3;

pub const BLACK: u8 = 1;
/// Knock-out ids 1..n of each texture (0 = transparent), then every unordered pair's mix.
const Texture = struct { base: u8, colours: u8, mixes: u8 };
const TEXTURES = [2]Texture{
    .{ .base = 15, .colours = 7, .mixes = 28 }, // blue: 7 colours, 28 pairs with transparent
    .{ .base = 22, .colours = 6, .mixes = 56 }, // orange: 6 colours, 21 pairs
};
/// Two knock-out ids (0..7, 0 transparent) -> the palette entry of their mix.
pub const Pairs = [8][8]u8;
pub const pairs: [2]Pairs = .{ pairTable(TEXTURES[0]), pairTable(TEXTURES[1]) };

pub const palette: [256]Color = blk: {
    var p = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/union_texcopier/pal.dat"));
    p[0] = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    for (TEXTURES) |t| for (1..t.colours + 1) |hi| for (0..hi) |lo| {
        p[t.mixes + slot(lo, hi)] = mix(idColour(p, t, lo), idColour(p, t, hi));
    };
    break :blk p;
};

pub const Images = struct {
    display: blit.Image,
    font: []const u8, // 1 = the black field, 0 = the glyph the texture shows through
    textures: [2][]const u8, // blue, orange: knock-out ids, TEXTURE_ROWS x TEXTURE_W
    rasters: []const u8, // RASTER_IMAGES x RASTER_COLOURS x RGB

    /// Views into the depacked image; `buf` must be TOTAL bytes.
    pub fn split(buf: []const u8) Images {
        const tex = TEXTURE_W * TEXTURE_ROWS;
        const font_at = DISPLAY_W * DISPLAY_H;
        const tex_at = font_at + FONT_W * GLYPH_H * 3;
        return .{
            .display = blit.Image.init(buf[0..font_at], DISPLAY_W),
            .font = buf[font_at..tex_at],
            .textures = .{ buf[tex_at..][0..tex], buf[tex_at + tex ..][0..tex] },
            .rasters = buf[tex_at + 2 * tex .. TOTAL],
        };
    }
};

fn pairTable(comptime t: Texture) Pairs {
    var table: Pairs = undefined;
    for (0..8) |a| for (0..8) |b| {
        const lo = @min(a, b);
        const hi = @max(a, b);
        table[a][b] = if (hi > t.colours) BLACK // ids the texture does not have
        else if (a == b) (if (a == 0) BLACK else t.base + a - 1) else t.mixes + slot(lo, hi);
    };
    return table;
}

fn slot(lo: usize, hi: usize) u8 {
    return @intCast(hi * (hi - 1) / 2 + lo);
}

fn idColour(p: [256]Color, t: Texture, id: usize) Color {
    return if (id == 0) .{ .r = 0, .g = 0, .b = 0, .a = 255 } else p[t.base + id - 1];
}

/// Chrome's 50/50 bilinear mix of two opaque (or transparent-as-black) texels.
pub fn mix(a: Color, b: Color) Color {
    return .{ .r = half(a.r, b.r), .g = half(a.g, b.g), .b = half(a.b, b.b), .a = 255 };
}

fn half(a: u8, b: u8) u8 {
    return @intCast((@as(u16, a) + b) >> 1);
}
