// --------------------------------------------------------------------------
// The screen GEM lays out on (docs/DEVPAC_GAP.md §3b): ONE description, set by
// the ROM when it binds a plane (rom_main.zig bindFb) and on every mode change
// (deskSetScreen). Every layout reads it: no literal 200 or 640 anywhere else.
//
//   low     320x200, drawn pixel-doubled (2:1)      RESOLUTION = RES_PLANES
//   medium  640x200, 1:1 into the raster (2:1 tall)  RESOLUTION = RES_MEDIUM
//   desk    640x480, 1:1, square pixels             RESOLUTION = RES_DESK (HW 1.17.0)
//
// The font's metrics are data here too (GEM's gl_wchar / gl_hchar / gl_hbox):
// the menu bar and the item rows follow the character cell. v1 is 8x8 in every
// mode (80x60 cells in the desk); an 8x16 font (GEM5 P2.5) changes one Font.
// Pure integer maths, no ZigOS import, so `zig test` covers it.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Mode = enum(u8) { low, medium, desk };

/// The system font's character cell (gl_wchar x gl_hchar).
pub const Font = struct { cell_w: i16 = 8, cell_h: i16 = 8 };

/// What the font sets in the layout. The menu bar is gl_hbox = char height + 3
/// rows: char height + 2 white rows (the text on row 1) and a black line under
/// them, so the work area starts at menu_h + 1.
pub const Metrics = struct {
    cell: i16,
    menu_h: i16,
    item_h: i16,

    pub fn of(f: Font) Metrics {
        return .{ .cell = f.cell_w, .menu_h = f.cell_h + 2, .item_h = f.cell_h };
    }
};

pub const FONT_8X8 = Font{};
/// The 8x8 font's metrics: types.zig's MENU_H / CELL / ITEM_H are these.
pub const METRICS = Metrics.of(FONT_8X8);

/// The host's pointer range in the plane modes: physical-visible 0..639 x 0..199
/// (docs/sealed-loader.js "Pointer input", glass_input.c); 0..639 x 0..479 in the desk.
pub const HOST_W: i16 = 640;

pub const Screen = struct {
    w: i16 = 320,
    h: i16 = 200,
    stride: u16 = 320, // bytes a row in the plane the ROM bound
    mode: Mode = .low,
    font: Font = FONT_8X8,

    pub fn of(mode: Mode) Screen {
        return switch (mode) {
            .low => .{},
            .medium => .{ .w = 640, .stride = 640, .mode = .medium },
            .desk => .{ .w = 640, .h = 480, .stride = 640, .mode = .desk },
        };
    }

    pub fn metrics(self: Screen) Metrics {
        return Metrics.of(self.font);
    }

    /// The desktop's work area: everything below the menu bar (GEM's "full" window).
    pub fn workArea(self: Screen) Rect {
        const top = self.metrics().menu_h + 1;
        return .{ .x = 0, .y = top, .w = self.w, .h = self.h - top };
    }

    /// The top-left that centres a w x h box (dialogs).
    pub fn centreX(self: Screen, w: i16) i16 {
        return @divTrunc(self.w - w, 2);
    }
    pub fn centreY(self: Screen, h: i16) i16 {
        return @divTrunc(self.h - h, 2);
    }

    /// The one pointer mapping: the host's coordinates to this screen's. Low res is
    /// 320 wide on a 640-pixel host range, so x halves; medium and desk are 1:1.
    pub fn fromHost(self: Screen, x: i32, y: i32) [2]i32 {
        return .{ if (self.mode == .low) @divTrunc(x, 2) else x, y };
    }

    /// `r` moved and shrunk to lie in the work area (a window saved in another mode,
    /// or open when the mode changed): at most the work area's size, at least
    /// `min_w` x `min_h`, its title bar below the menu bar and inside the screen.
    pub fn clampRect(self: Screen, r: Rect, min_w: i16, min_h: i16) Rect {
        const a = self.workArea();
        const w = @max(@min(r.w, a.w), @min(min_w, a.w));
        const h = @max(@min(r.h, a.h), @min(min_h, a.h));
        return .{
            .x = @max(a.x, @min(r.x, a.x + a.w - w)),
            .y = @max(a.y, @min(r.y, a.y + a.h - h)),
            .w = w,
            .h = h,
        };
    }
};

/// The GUI's rectangle (types.zig re-exports it): defined here so this file needs no GUI import.
pub const Rect = struct { x: i16, y: i16, w: i16, h: i16 };

/// The machine's RESOLUTION register (machine/sdk/memmap.zig RES_*) as a mode.
pub fn modeOfResolution(res: u8) Mode {
    return switch (res) {
        2 => .medium, // RES_MEDIUM
        3 => .desk, // RES_DESK
        else => .low, // RES_PLANES (and truecolor's border-open state: a plane mode)
    };
}

// --- native tests ----------------------------------------------------------
const expectEqual = std.testing.expectEqual;

test "the 8x8 font gives TOS's menu bar and cells" {
    try expectEqual(@as(i16, 10), METRICS.menu_h);
    try expectEqual(@as(i16, 8), METRICS.cell);
    try expectEqual(@as(i16, 8), METRICS.item_h);
    const tall = Metrics.of(.{ .cell_w = 8, .cell_h = 16 });
    try expectEqual(@as(i16, 18), tall.menu_h); // follows the font, as gl_hbox
}

test "each mode's screen and work area" {
    try expectEqual(Rect{ .x = 0, .y = 11, .w = 320, .h = 189 }, Screen.of(.low).workArea());
    try expectEqual(Rect{ .x = 0, .y = 11, .w = 640, .h = 189 }, Screen.of(.medium).workArea());
    try expectEqual(Rect{ .x = 0, .y = 11, .w = 640, .h = 469 }, Screen.of(.desk).workArea());
    try expectEqual(@as(i16, 164), Screen.of(.desk).centreY(152));
    try expectEqual(@as(i16, 24), Screen.of(.low).centreY(152));
}

test "the pointer halves x in low res only" {
    try expectEqual([2]i32{ 100, 150 }, Screen.of(.low).fromHost(200, 150));
    try expectEqual([2]i32{ 200, 150 }, Screen.of(.medium).fromHost(200, 150));
    try expectEqual([2]i32{ 639, 479 }, Screen.of(.desk).fromHost(639, 479));
    try expectEqual([2]i32{ -2, 3 }, Screen.of(.low).fromHost(-5, 3)); // truncates toward 0, as the shell did
}

test "a desk window clamped into low res stays reachable" {
    const low = Screen.of(.low);
    const r = low.clampRect(.{ .x = 400, .y = 300, .w = 500, .h = 250 }, 64, 44);
    try expectEqual(Rect{ .x = 0, .y = 11, .w = 320, .h = 189 }, r);
    const small = low.clampRect(.{ .x = 300, .y = 190, .w = 80, .h = 60 }, 64, 44);
    try expectEqual(Rect{ .x = 240, .y = 140, .w = 80, .h = 60 }, small);
    const inside = Screen.of(.desk).clampRect(.{ .x = 24, .y = 24, .w = 320, .h = 120 }, 64, 44);
    try expectEqual(Rect{ .x = 24, .y = 24, .w = 320, .h = 120 }, inside); // already inside: untouched
}

test "RESOLUTION codes map to modes" {
    try expectEqual(Mode.low, modeOfResolution(0));
    try expectEqual(Mode.medium, modeOfResolution(2));
    try expectEqual(Mode.desk, modeOfResolution(3));
}
