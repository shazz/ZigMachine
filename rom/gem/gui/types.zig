// --------------------------------------------------------------------------
// ZigOS GUI — shared types, palette and metrics (foundation for the toolkit).
//
// Split out of the former monolithic gui.zig so every widget/window/menu file
// shares one Rect, one palette and one set of GEM metrics. No behaviour change.
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const LogicalFB = zsrc.LogicalFB;
const glyphs = @import("../gem_glyphs.zig"); // GEM window-control bitmaps

// GEM-ish palette (installed on the plane by installPalette).
pub const BLACK: u8 = 0;
pub const WHITE: u8 = 1;
pub const LGRAY: u8 = 2;
pub const MGRAY: u8 = 3;
pub const DGRAY: u8 = 4;
pub const DESK: u8 = 5;
pub const ACCENT: u8 = 6;
pub const WAVE: u8 = 7;

pub fn installPalette(fb: *LogicalFB) void {
    fb.setPaletteEntry(BLACK, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
    fb.setPaletteEntry(WHITE, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    fb.setPaletteEntry(LGRAY, .{ .r = 200, .g = 200, .b = 200, .a = 255 });
    fb.setPaletteEntry(MGRAY, .{ .r = 140, .g = 140, .b = 140, .a = 255 });
    fb.setPaletteEntry(DGRAY, .{ .r = 80, .g = 80, .b = 80, .a = 255 });
    fb.setPaletteEntry(DESK, .{ .r = 0, .g = 150, .b = 90, .a = 255 });
    fb.setPaletteEntry(ACCENT, .{ .r = 40, .g = 90, .b = 220, .a = 255 });
    fb.setPaletteEntry(WAVE, .{ .r = 60, .g = 230, .b = 140, .a = 255 });
}

pub const Rect = struct { x: i16, y: i16, w: i16, h: i16 };

pub fn inRect(r: Rect, px: i32, py: i32) bool {
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h;
}

// --- GEM metrics (shared by menu.zig and window.zig) ---
// The menu bar is gl_hbox = char height + 3 = 11 rows; 10 white rows (text on
// row 1) closed by a black line on row MENU_H; the work area starts at MENU_H+1.
pub const MENU_H: i16 = 10;
pub const ITEM_H: i16 = 8;

// Title bar = the 12x11 gadget box height; info line shares its top line.
pub const TITLE_H: i16 = glyphs.GH;
pub const INFO_H: i16 = glyphs.GH - 1;
pub const SCROLL: i16 = glyphs.GW; // scrollbar gutter / gadget size (12px boxes)
pub const MAX_WIN = 7; // GEM Desktop: 7 windows
pub const MIN_W: i16 = 64;
pub const MIN_H: i16 = 44;

pub const Window = struct {
    r: Rect,
    title: []const u8,
    info: []const u8 = "", // info line under the title (empty = none)
    open: bool = true,
    full: bool = false, // toggled by the full box
    saved: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, // rect to restore from full
    min_w: i16 = MIN_W, // resize floor (a content window raises it to fit one cell)
    min_h: i16 = MIN_H,
};

pub fn topBarsH(w: *const Window) i16 {
    return if (w.info.len > 0) TITLE_H + INFO_H else TITLE_H;
}
