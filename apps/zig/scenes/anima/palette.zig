// --------------------------------------------------------------------------
// ANIMA's one palette: who owns which index of plane 0.
//
//   0         the raster: the copper rewrites it every physical line, so the
//             whole 400x280 (borders included) shows it wherever nothing is drawn
//   1..5      the ANIMA logo: outline, drop shadow, bevel light, bevel dark, body
//             (body = copper slot, a chrome ramp per line)
//   6..9      the scroller font: outline, bevel light, bevel dark, body (copper)
//   10..12    the stars, far to near
//   0x10..    the glenz: back faces on lanes 0x10/0x20, front faces on 0x40/0x80;
//             CHISEL ORs a face into what is there, so an overlap is the OR of
//             its lanes and every combination has its own colour
//
// Colours are STE words (4 bits a gun) shown at level*17.
// --------------------------------------------------------------------------
pub const BG: u8 = 0;

pub const LOGO_OUTLINE: u8 = 1;
pub const LOGO_SHADOW: u8 = 2;
pub const LOGO_HI: u8 = 3;
pub const LOGO_LO: u8 = 4;
pub const LOGO_BODY: u8 = 5;

pub const FONT_OUTLINE: u8 = 6;
pub const FONT_HI: u8 = 7;
pub const FONT_LO: u8 = 8;
pub const FONT_BODY: u8 = 9;

pub const STAR0: u8 = 10; // 10, 11, 12: far, mid, near
pub const STARS: u8 = 3;

pub const BACK_A: u8 = 0x10;
pub const BACK_B: u8 = 0x20;
pub const FRONT_A: u8 = 0x40;
pub const FRONT_B: u8 = 0x80;

/// An STE colour (levels 0..15 a gun) as the palette's RGBA word.
pub fn ste(r: u32, g: u32, b: u32) u32 {
    return 0xFF00_0000 | (b * 17) << 16 | (g * 17) << 8 | r * 17;
}

/// Scale an RGBA word's guns by k/16 (k 0..16), alpha kept.
pub fn dim(c: u32, k: u32) u32 {
    const r = (c & 0xFF) * k >> 4;
    const g = (c >> 8 & 0xFF) * k >> 4;
    const b = (c >> 16 & 0xFF) * k >> 4;
    return 0xFF00_0000 | b << 16 | g << 8 | r;
}

/// The fixed entries; the copper owns 0, LOGO_BODY and FONT_BODY.
pub fn install(pal: [*]u32) void {
    pal[BG] = ste(0, 0, 0);
    pal[LOGO_OUTLINE] = ste(0, 0, 1);
    pal[LOGO_SHADOW] = ste(1, 0, 3);
    pal[LOGO_HI] = ste(15, 15, 15);
    pal[LOGO_LO] = ste(4, 2, 8);
    pal[LOGO_BODY] = ste(10, 8, 15);
    pal[FONT_OUTLINE] = ste(0, 0, 0);
    pal[FONT_HI] = ste(15, 15, 15);
    pal[FONT_LO] = ste(3, 1, 5);
    pal[FONT_BODY] = ste(15, 12, 4);
    pal[STAR0 + 0] = ste(5, 5, 8);
    pal[STAR0 + 1] = ste(9, 9, 12);
    pal[STAR0 + 2] = ste(15, 15, 15);
    glenz(pal, 0);
}

// Glenz schemes: back A, back B, front A, front B (one per object). Saturated:
// one gun low in every lane, so where faces overlap the light adds up visibly.
const SCHEMES = [_][4]u32{
    .{ ste(0, 2, 9), ste(5, 0, 9), ste(0, 10, 15), ste(9, 5, 15) }, // ice
    .{ ste(9, 0, 0), ste(8, 0, 5), ste(15, 7, 0), ste(15, 0, 6) }, // fire
    .{ ste(0, 6, 1), ste(0, 3, 7), ste(2, 15, 4), ste(9, 15, 0) }, // jade
    .{ ste(6, 0, 9), ste(9, 0, 2), ste(15, 0, 12), ste(10, 4, 15) }, // orchid
};

/// Load scheme `s` into the 15 glenz entries: lane combination m (bit i =
/// lane i present) is the SUM of its lanes' colours, clamped: light through
/// two layers of coloured glass adds up, so every overlap is brighter and of a
/// new hue. Written once an object (15 stores every 12 s).
pub fn glenz(pal: [*]u32, s: usize) void {
    const k = SCHEMES[s % SCHEMES.len];
    for (1..16) |m| {
        var c: u32 = 0xFF00_0000;
        for (0..3) |g| {
            var sum: u32 = 0;
            for (0..4) |i| {
                if (m >> @intCast(i) & 1 != 0) sum += k[i] >> @intCast(8 * g) & 0xFF;
            }
            c |= @as(u32, @min(sum, 255)) << @intCast(8 * g); // u32: @min narrows to u8
        }
        pal[m << 4] = c;
    }
}

pub const SCHEME_COUNT = SCHEMES.len;
