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

// A full-spectrum ramp parked above the GEM colours: the Desktop Info logo cycles
// through it to get the scrolling rainbow every ST intro opened with. GEM itself
// only ever uses entries 0..7, so 16.. is free.
pub const RAINBOW0: u8 = 16;
pub const RAINBOW_N: u8 = 32;

// One step of the spectrum as RGB — a 6-sector HSV sweep at full saturation and
// value, in integer maths (no float on the way to a palette entry).
fn spectrum(step: u8) [3]u8 {
    const h: u16 = @as(u16, step) * 1536 / RAINBOW_N; // 0..1535 = six 256-wide sectors
    const sector: u16 = h / 256;
    const t: u8 = @intCast(h % 256);
    const up = t;
    const dn: u8 = 255 - t;
    return switch (sector) {
        0 => .{ 255, up, 0 },
        1 => .{ dn, 255, 0 },
        2 => .{ 0, 255, up },
        3 => .{ 0, dn, 255 },
        4 => .{ up, 0, 255 },
        else => .{ 255, 0, dn },
    };
}

pub fn installPalette(fb: *LogicalFB) void {
    fb.setPaletteEntry(BLACK, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
    fb.setPaletteEntry(WHITE, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    fb.setPaletteEntry(LGRAY, .{ .r = 200, .g = 200, .b = 200, .a = 255 });
    fb.setPaletteEntry(MGRAY, .{ .r = 140, .g = 140, .b = 140, .a = 255 });
    fb.setPaletteEntry(DGRAY, .{ .r = 80, .g = 80, .b = 80, .a = 255 });
    fb.setPaletteEntry(DESK, .{ .r = 0, .g = 150, .b = 90, .a = 255 });
    fb.setPaletteEntry(ACCENT, .{ .r = 40, .g = 90, .b = 220, .a = 255 });
    fb.setPaletteEntry(WAVE, .{ .r = 60, .g = 230, .b = 140, .a = 255 });
    var i: u8 = 0;
    while (i < RAINBOW_N) : (i += 1) {
        const c = spectrum(i);
        fb.setPaletteEntry(RAINBOW0 + i, .{ .r = c[0], .g = c[1], .b = c[2], .a = 255 });
    }
}

pub const Rect = struct { x: i16, y: i16, w: i16, h: i16 };

pub fn inRect(r: Rect, px: i32, py: i32) bool {
    return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h;
}

// --- GEM metrics (shared by menu.zig and window.zig) ---
// The menu bar is gl_hbox = char height + 3 = 11 rows; 10 white rows (text on
// row 1) closed by a black line on row MENU_H; the work area starts at MENU_H+1.
pub const MENU_H: i16 = 10;
pub const CELL: i16 = 8; // one character cell (gl_wchar) — the GEM layout unit
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
    // Scroll state. `vslide`/`hslide` are how much of each track the slider fills,
    // in PER MILLE (1000 = everything fits, GEM's full white slider); `vscroll` /
    // `hscroll` are how far the content is scrolled, in the owner's own units
    // (rows / character cells), bounded by `vmax` / `hmax`. The owner recomputes
    // the sizes and the bounds whenever it lays out; the window manager moves the
    // scroll values when the arrow gadgets are clicked.
    vslide: i16 = 1000,
    hslide: i16 = 1000,
    vscroll: i16 = 0,
    hscroll: i16 = 0,
    vmax: i16 = 0,
    hmax: i16 = 0,
};

pub fn topBarsH(w: *const Window) i16 {
    return if (w.info.len > 0) TITLE_H + INFO_H else TITLE_H;
}

// --- scrollbar geometry ---------------------------------------------------
// One definition of where the tracks and the sliders are, shared by chrome.zig
// (which paints them) and window.zig (which hit-tests and drags them) — the two
// must not drift apart or a slider becomes ungrabbable where it is drawn.

pub fn vTrack(w: *const Window) Rect {
    const gw = glyphs.GW;
    const gh = glyphs.GH;
    const uy = w.r.y + topBarsH(w) - 1;
    const dy = w.r.y + w.r.h - 2 * gh + 1;
    return .{ .x = w.r.x + w.r.w - gw, .y = uy + gh - 1, .w = gw, .h = dy - uy - gh + 2 };
}

pub fn hTrack(w: *const Window) Rect {
    const gw = glyphs.GW;
    const gh = glyphs.GH;
    const rrx = w.r.x + w.r.w - 2 * gw + 1;
    return .{ .x = w.r.x + gw - 1, .y = w.r.y + w.r.h - gh, .w = rrx - w.r.x - gw + 2, .h = gh };
}

// A window growing to / shrinking from full size, for the owner's zoom animation.
pub const Zoom = struct { from: Rect, to: Rect };

// The white slider box inside `track`: its LENGTH is the visible fraction of the
// content (permille) and its position is scroll/max of the remaining travel.
pub fn sliderBox(track: Rect, permille: i16, scroll: i16, max: i16, vertical: bool) Rect {
    const span = if (vertical) track.h else track.w;
    const box = @max(glyphs.GH, @divTrunc(span * @max(@min(permille, 1000), 0), 1000));
    const travel = span - box;
    const at: i16 = if (max > 0 and travel > 0)
        @intCast(@divTrunc(@as(i32, travel) * @max(0, @min(scroll, max)), max))
    else
        0;
    return if (vertical)
        .{ .x = track.x, .y = track.y + at, .w = track.w, .h = box }
    else
        .{ .x = track.x + at, .y = track.y, .w = box, .h = track.h };
}

// Where along `track` a slider grabbed at `grab` pixels from its own start now
// sits, expressed as a scroll value in 0..max.
pub fn sliderScroll(track: Rect, permille: i16, max: i16, vertical: bool, pointer: i32, grab: i16) i16 {
    const span = if (vertical) track.h else track.w;
    const box = @max(glyphs.GH, @divTrunc(span * @max(@min(permille, 1000), 0), 1000));
    const travel = span - box;
    if (travel <= 0 or max <= 0) return 0;
    const start = if (vertical) track.y else track.x;
    const at: i32 = @max(0, @min(@as(i32, travel), pointer - @as(i32, grab) - @as(i32, start)));
    return @intCast(@divTrunc(at * max + @divTrunc(travel, 2), travel));
}
