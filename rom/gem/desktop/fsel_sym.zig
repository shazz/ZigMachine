// --------------------------------------------------------------------------
// The ITEM SELECTOR's small pictures (fsel_tree.zig): TOS's gadget characters
// (the closer, the arrows) and, for a font that has none (ZigOS's 8x8), our own
// symbols for them; the folder mark. Pure: no ZigOS.
// --------------------------------------------------------------------------
const obj = @import("../engine/obj.zig");
const glyphs = @import("../gem_glyphs.zig");

// The gadgets' characters in a TOS font: the closer, up, down (G_BOXCHAR, as TOS 4's tree has them).
pub const CH_CLOSE: u8 = 5;
pub const CH_UP: u8 = 1;
pub const CH_DOWN: u8 = 2;
pub const CHARS = [3]u8{ CH_CLOSE, CH_UP, CH_DOWN };
// A font without them (ZigOS's 8x8 has none): the symbol of our window gadgets (gem_glyphs.zig, a 12x11
// box with its frame) without the box, 8 columns (2..9) by 8 rows from `top`; the G_BOXCHAR is the box.
const Sym = struct { g: [glyphs.GH]u16, top: usize };
const SYMBOL = [3]Sym{ .{ .g = glyphs.CLOSE, .top = 1 }, .{ .g = glyphs.UP, .top = 1 }, .{ .g = glyphs.DOWN, .top = 2 } };
fn symbolBits(comptime k: usize, comptime n: usize) [n]u8 {
    var out: [n]u8 = undefined;
    for (0..n) |i| out[i] = @truncate(SYMBOL[k].g[SYMBOL[k].top + i * 8 / n] >> 2); // 16 rows: each twice
    return out;
}
const SYM8 = [3][8]u8{ symbolBits(0, 8), symbolBits(1, 8), symbolBits(2, 8) };
const SYM16 = [3][16]u8{ symbolBits(0, 16), symbolBits(1, 16), symbolBits(2, 16) };
pub const SYM_BLK = [2][3]obj.BitBlk{
    .{ .{ .data = &SYM8[0], .w = 8, .h = 8 }, .{ .data = &SYM8[1], .w = 8, .h = 8 }, .{ .data = &SYM8[2], .w = 8, .h = 8 } },
    .{ .{ .data = &SYM16[0], .w = 8, .h = 16 }, .{ .data = &SYM16[1], .w = 8, .h = 16 }, .{ .data = &SYM16[2], .w = 8, .h = 16 } },
};
const FOLDER_BITS = [7]u8{ 0x10, 0x38, 0x7C, 0xFE, 0x7C, 0x38, 0x10 }; // TOS's folder diamond
pub const FOLDER: obj.BitBlk = .{ .data = &FOLDER_BITS, .w = 8, .h = 7 };

/// Gadget `k`'s symbol (0 closer, 1 up, 2 down) for the 8- or 16-pixel font.
pub fn symbol(k: usize, tall: bool) *const obj.BitBlk {
    return &SYM_BLK[@intFromBool(tall)][k];
}
