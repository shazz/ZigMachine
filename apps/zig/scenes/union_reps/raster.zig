// --------------------------------------------------------------------------
// REPS rasters, as registers: nothing on this screen paints a raster as pixels.
//
// The remake drew rastersPink/Green/Brown.png as 640-wide images under the
// picture, and filled the "CRACKING IS ... GOOD FOR YOU" mask 'source-atop'
// with rasters.png. Every row of all four images is ONE colour, and every
// colour is ST-legal (each channel a multiple of 32, at most 224: the 3-bit
// register rendered as nibble * 32), so they are the colour lists the real
// screen wrote per scanline and only the mechanism was faked. The colours are
// kept; the mechanism is now the ST's:
//
//   colour 0  the background: the picture's windows are colour 0 (overlay.png
//             marks its OTHER blacks as (1,1,1) so they survive as ink), so a
//             bar behind a window is colour 0 changed on that scanline. The ST
//             paints its border from colour 0 too, so the bars run edge to edge,
//             across the closed side borders, with no overscan.
//   MASK_INK  the mask's one ink, rewritten on each of its 54 lines.
//
// Per line that is at most two register CHANGES: colour 0 only where the bar
// colour differs from the line above, MASK_INK on the mask's lines. Two
// move.w, 24 cycles, 24 low-res pixels of a 512-cycle line.
//
// The border is the machine background, and the host paints it (hwClear, the
// global HBL) BEFORE the cart runs the frame, so a table written this frame
// would reach the border a frame late. The border's table is therefore the
// NEXT frame's colour 0 (layers.Bars steps deterministically), and it lands
// on the same frame as the picture's.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const A = @import("assets.zig");

const Color = zg.Color;
const BG: u8 = 0; // colour 0
const BG_SLOT: zg.copper.Slot = 0;
const INK_SLOT: zg.copper.Slot = 1;
const TOP = (zg.PHYSICAL_HEIGHT - zg.HEIGHT) / 2; // the first visible physical row

var tables: [2]zg.copper.Table = undefined;
var border: [zg.PHYSICAL_HEIGHT]u32 = undefined;

/// Plays both registers on `fb` and colour 0 on the border. Colour 0 becomes
/// opaque: it is the background now, not a hole.
pub fn install(zigos: *zg.ZigOS, fb: *zg.LogicalFB) void {
    fb.setPaletteEntry(BG, A.palette[A.BLACK]);
    fb.setPaletteEntry(A.MASK_INK, A.palette[A.BLACK]);
    zg.copper.install(fb, &.{ BG, A.MASK_INK }, &tables, .{});
    @memset(&border, A.rgba(A.BLACK)); // the top and bottom borders stay black
    zigos.setHBLHandler(borderHbl);
}

/// Colour 0 for each visible line of this frame.
pub fn background(fb: *const zg.LogicalFB) *[zg.HEIGHT]u32 {
    return zg.copper.visible(fb, BG_SLOT);
}

/// MASK_INK for each visible line of this frame.
pub fn maskInk(fb: *const zg.LogicalFB) *[zg.HEIGHT]u32 {
    return zg.copper.visible(fb, INK_SLOT);
}

/// Colour 0 for each visible line of the NEXT frame, as the border shows it.
pub fn nextBorder() *[zg.HEIGHT]u32 {
    return border[TOP..][0..zg.HEIGHT];
}

/// The global HBL: PHYSICAL lines 0..279, the border's colour 0.
fn borderHbl(zigos: *zg.ZigOS, line: u16) void {
    if (line < border.len) zigos.setBackgroundColor(Color.fromRGBA(border[line]));
}
