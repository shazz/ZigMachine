// The screen's palette layout, shared with tools/private_tools/tcb_spreadpoint_assets.py,
// which writes these indices straight into the .raw files. Thirteen entries:
// the whole screen fits an ST's sixteen colour registers.
//
//   0        the background (transparent over the black machine background)
//   1        the intro pictures' ink, faded per frame
//   2        the 8x6 scroller's ink          raster (raster.zig)
//   3        the logo's inside               raster
//   4..6     the DNA font's three colours    raster
//   7..9     greens: the balls, and the logo outline's green fragments
//   10..12   browns: the logo outline

pub const INTRO_INK: u8 = 1;
pub const SCROLL_INK: u8 = 2;
pub const LOGO_INK: u8 = 3;
pub const DNA_INK: u8 = 4;

/// font_dna.png's three colours, darkest first (DNA_INK + 0..2).
pub const DNA_FONT = [3]u24{ 0x884400, 0xCC8800, 0xEECC00 };
