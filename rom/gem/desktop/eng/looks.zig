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
    p[L.LBLACK] = 3; // the 3D shadow: mid grey (the reference's 136)
    return p;
}

pub fn look(set: *const assets.Set, three_d: bool) L.Look {
    // TOS 4's window, as Matt's reconstruction draws it (aes340_tos4 windows): white gadget faces with a
    // grey shadow edge, the font's gadget glyphs, TOS 1's grey mover; no drop shadow.
    return .{ .three_d = three_d, .pal = pens(), .font = &set.sys, .small = &set.small, .grey = 3, .face = L.WHITE };
}

/// The 16 VDI pens into the plane's palette at PEN_BASE (a colour icon's bytes index them):
/// the engine on entry, the old path too when its icon set has a colour icon (desktop.zig).
pub fn installPens(fb: anytype, rgb: [16][3]u8) void {
    for (rgb, 0..) |c, i| fb.setPaletteEntry(PEN_BASE + @as(u8, @intCast(i)), .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
}
