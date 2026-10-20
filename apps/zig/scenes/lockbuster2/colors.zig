// --------------------------------------------------------------------------
// Lockbuster 2's colours (see lockbuster2.zig's header for the three colour
// sources): the 16 static words, the copper tables of entries 0 and 1 and the
// global border HBL's table. All of it depends only on the three toggles, so
// refresh() rewrites it only when one of them changes -- on the board every
// store is a DDR write, and a raster coder never rewrites a register.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const copper = zg.copper;
const engine_mod = @import("engine.zig");

const H: usize = zg.HEIGHT; // 200
const PHYS_H: usize = zg.PHYSICAL_HEIGHT; // 280, the global HBL's lines
const VBORDER: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40

// The demo's own 16 colour words in metallic and gold (Go's `words` arrays,
// quoted; gold turned on by the slide-in bank and stays on).
const WORDS = [16]u16{ 0x000, 0x000, 0x134, 0x235, 0x124, 0x023, 0x346, 0x245, 0x356, 0x457, 0x467, 0x567, 0x677, 0x577, 0x701, 0x777 };
const WORDS_GOLD = [16]u16{ 0x000, 0x000, 0x341, 0x532, 0x421, 0x320, 0x643, 0x542, 0x653, 0x754, 0x764, 0x765, 0x776, 0x775, 0x107, 0x777 };

/// Go's put(): an ST colour word to RGBA on the channels-nibble*34 scale the
/// Go production rendered at.
fn wordColor(w: u16) Color {
    return .{
        .r = @intCast(((w >> 8) & 7) * 34),
        .g = @intCast(((w >> 4) & 7) * 34),
        .b = @intCast((w & 7) * 34),
        .a = 255,
    };
}

pub const BLACK = wordColor(0x000);

/// The raster colour words of an HBL row, 0 past the bank's end exactly as
/// the Go uniform did (engine.zig's rasterWord, on the same embedded banks).
fn rasterWord(bank: usize, row: usize) u16 {
    const b = engine_mod.raster_banks[bank];
    if (row * 2 + 1 < b.len) return std.mem.readInt(u16, b[row * 2 ..][0..2], .big);
    return 0;
}

/// One word per SECOND screen line (the shader's floor(y/2)).
fn rasterColor(bank: usize, y: usize) u32 {
    return wordColor(rasterWord(bank, y / 2)).toRGBA();
}

const SLOT0: copper.Slot = 0; // ST palette entry 0
const SLOT1: copper.Slot = 1; // ST palette entry 1

var copper_tables: [2]copper.Table = undefined;
var border_table: [PHYS_H]u32 = undefined;

/// Global HBL, PHYSICAL lines 0..279: the border takes the bars' colour for
/// the line, black outside the visible band. The table only changes when a
/// key or a phase turns a toggle, in the same render pass that fills the plane
/// (garfield built its table one frame ahead for MOVING bars; these bars never
/// move of their own accord).
fn borderHbl(zigos: *ZigOS, line: u16) void {
    zigos.setBackgroundColor(Color.fromRGBA(border_table[@min(line, border_table.len - 1)]));
}

/// The shown plane's palette, its two copper slots (entries 0 and 1, no
/// border flicker: the plane shows 320x200 and the border follows colour
/// register 0, as on the ST) and the border HBL.
pub fn install(zigos: *ZigOS, fb: *zg.LogicalFB) void {
    // Entries 0/1 are the copper tables' starting colours (black).
    for (WORDS, 0..) |w, i| fb.palette[i] = wordColor(w).toRGBA();
    for (16..256) |i| fb.palette[i] = 0; // unused above 16: transparent, never shown
    @memset(&border_table, BLACK.toRGBA());
    copper.install(fb, &.{ 0, 1 }, &copper_tables, .{});
    zigos.setHBLHandler(borderHbl);
}

/// gold | color_text << 1 | new_raster << 2: what the colours depend on.
pub fn toggles(gold: bool, color_text: bool, new_raster: bool) u8 {
    return @as(u8, @intFromBool(gold)) | @as(u8, @intFromBool(color_text)) << 1 | @as(u8, @intFromBool(new_raster)) << 2;
}

/// Rebuild what the toggles `now` change against `shown` (0xFF = nothing built).
pub fn refresh(fb: *zg.LogicalFB, now: u8, shown: u8) void {
    if ((now ^ shown) & 1 != 0) {
        const words = if (now & 1 != 0) WORDS_GOLD else WORDS;
        for (words, 0..) |w, i| fb.palette[i] = wordColor(w).toRGBA();
    }
    if ((now ^ shown) & 6 == 0) return;
    const bank: usize = if (now & 4 != 0) 1 else 0;
    const color_text = now & 2 != 0;
    const copper0 = copper.visible(fb, SLOT0);
    const copper1 = copper.visible(fb, SLOT1);
    for (0..H) |y| {
        copper0[y] = rasterColor(bank, y);
        // Entry 1: the ink raster nine rows later than colour 0's, when the
        // text is coloured; black otherwise (the metallic words).
        copper1[y] = if (color_text) wordColor(rasterWord(bank, y / 2 + 9)).toRGBA() else BLACK.toRGBA();
    }
    // The border: the same colour-0 words over the visible band, black
    // everywhere else -- top and bottom bands show register 0 black, as the
    // demo's own palette before the rasters wrote it.
    const band = border_table[VBORDER .. VBORDER + H];
    for (0..H) |y| band[y] = rasterColor(bank, y);
}
