// --------------------------------------------------------------------------
// The engine's two looks over ZigGEM's palette (gui/types.zig: 0 black, 1 white,
// 2 light grey, 3 mid grey, 4 dark grey, 5 the desktop colour): GEM pens map onto
// those, and the other VDI pens onto 16 slots at PEN_BASE, which the engine
// fills from the asset set while it runs (ZigGEM never uses 48..63, so the
// old path, low and medium do not see them).
// --------------------------------------------------------------------------
const L = @import("../../engine/look.zig");
const assets = @import("assets.zig");

pub const PEN_BASE: u8 = 48; // tools/gem_assets_conv.py CICON_BASE: colour icons index here
// VDI pen -> hardware colour index (the order assets' palette_16 lists them in).
const HW = [16]u8{ 0, 15, 1, 2, 4, 6, 3, 5, 7, 8, 9, 10, 12, 14, 11, 13 };

pub fn pens() [16]u8 {
    var p: [16]u8 = undefined;
    for (&p, 0..) |*v, i| v.* = PEN_BASE + HW[i];
    p[L.WHITE] = 1;
    p[L.BLACK] = 0;
    p[L.GREEN] = 5; // the desktop: Set Preferences' colour
    p[L.LWHITE] = 2;
    p[L.LBLACK] = 4;
    return p;
}

pub fn look(set: *const assets.Set, three_d: bool) L.Look {
    return .{ .three_d = three_d, .pal = pens(), .font = &set.sys, .small = &set.small, .grey = 3 };
}

/// The palette entries the VDI pens use: (index, r, g, b) for each slot.
pub fn penEntry(set: *const assets.Set, i: usize) struct { idx: u8, rgb: [3]u8 } {
    return .{ .idx = PEN_BASE + @as(u8, @intCast(i)), .rgb = set.pens[i] };
}
