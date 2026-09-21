// --------------------------------------------------------------------------
// What was ripped out of ELT_CFSR.PRG, and the geometry it is drawn at.
//
// The .PRG is Eagle/Hotline-packed (a 40-byte XOR-encrypted banner, then a
// backwards Pack-Ice-family LZ depacker at TEXT+$dc). Unpacked it is a plain
// GEMDOS executable that still carries its SYMBOL TABLE, so every address below
// is the author's own label, not a guess. tools/private_tools/elite_cfsr_assets.py
// turns them into these files.
//
// The 16 palette registers are LOGO_PALETTE (DATA $132). Entries 0, 1 and 8 are
// rewritten per scanline by rasters.zig — 0 is the background AND the border,
// 1 and 8 are the two inks the scroller alternates between every 16 pixels.
// --------------------------------------------------------------------------
const zg = @import("zigos");

pub const LOGO_W: usize = 320; // LOGO header (DATA $12a): 320 x 37, 4 planes
pub const LOGO_H: usize = 37;

pub const GLYPHS: usize = 95; // FONT_POINTERS holds 95 longs, ASCII $20..$7e
pub const GLYPH_COLS: usize = 22; // the widest glyph; every slot is this long
pub const EDGES: usize = 6; // edge toggles stored per pixel column
pub const GLYPH_STRIDE: usize = GLYPH_COLS * EDGES;

pub const COLUMNS: usize = 320; // EDGE_BUFFER holds one screen's worth
pub const BAND_ROWS: usize = 16; // the XOR buffer after WRAP_XOR_BUFFER folds it
pub const PLOT_ROWS: usize = 32; // ... and before, which is what PLOT_EDGES fills
pub const BLOCKS: usize = COLUMNS / 32; // 10 blocks of 32 columns = one u32 a row

// Where the content sits in the 400x280 overscan plane. Visible line 0 is
// physical row 40; the logo is blitted at line 0 and the scroller band starts at
// line 44, which is COPY_XOR_BUFFER's own offset $1b86 = 44 * 160 + 6 read back.
pub const CONTENT_X: usize = 40;
pub const CONTENT_Y: usize = 40;
pub const BAND_TOP: usize = 44;
pub const BAND_REPEATS: usize = 10; // ... every $a00 bytes = every 16 lines

pub const INK_HI: u8 = 8; // columns 0..15 of each block: plane 3 -> colour 8
pub const INK_LO: u8 = 1; // columns 16..31: the same move.l lands in plane 0

pub const logo = @embedFile("../../assets/screens/elite_cfsr/logo.raw");
pub const font = @embedFile("../../assets/screens/elite_cfsr/font.bin");
pub const widths = @embedFile("../../assets/screens/elite_cfsr/widths.bin");
pub const ysin = @embedFile("../../assets/screens/elite_cfsr/ysin.bin");
pub const text = @embedFile("../../assets/screens/elite_cfsr/text.bin");
pub const palette = zg.convertU8ArraytoColors(@embedFile("../../assets/screens/elite_cfsr/logo_pal.dat"));

/// YSIN is masked with $1fff and then walked 320 columns further without being
/// masked again, so the original stores the table TWICE. Only the first half is
/// ripped; the walk wraps here instead.
pub const YSIN_LEN: usize = 4096;

/// An ST colour register ($0rgb, 3 bits a channel) as the palette stores it.
pub fn stColor(v: u16) u32 {
    const ch = struct {
        fn f(x: u16) u32 {
            return @as(u32, @intCast(x & 7)) * 255 / 7;
        }
    };
    return (0xFF << 24) | (ch.f(v) << 16) | (ch.f(v >> 4) << 8) | ch.f(v >> 8);
}
