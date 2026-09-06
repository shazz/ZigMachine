// --------------------------------------------------------------------------
// ZigGEM — the "ROM": a GEM-style desktop + the GUI libraries an application
// links against. Think of it as the system in ROM; an app in apps/ is the RAM
// cartridge that plugs into it. The desktop boots first, shows icons, and
// launches an app; the app draws over the whole screen and returns here on quit.
//
// The GUI toolkit (windows, menus, dialogs, buttons) lives in gui.zig and is
// re-exported here as `gem.gui` — the ROM's library surface. Apps use it.
// --------------------------------------------------------------------------
const zsrc = @import("zigos.zig");
pub const gui = @import("gui.zig"); // the ROM's GUI libraries (apps link this)
pub const icons = @import("gem_icons.zig"); // 1bpp icons ripped from a GEM icon sheet

const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const Rect = gui.Rect;

pub const Action = enum { none, launch, res_low, res_medium };

const DESK_MENUS = [_]gui.Menu{
    .{ .title = "Desk", .items = &.{"About ZigGEM"} },
    .{ .title = "File", .items = &.{"Open"} },
    .{ .title = "View", .items = &.{"Icons"} },
    .{ .title = "Options", .items = &.{ "Low Resolution", "Medium Resolution" } },
};

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    app_icon: Rect = .{ .x = 44, .y = 30, .w = icons.CARTRIDGE.w, .h = icons.CARTRIDGE.h },

    pub fn init(self: *Desktop, os: *ZigOS, fb: *LogicalFB, blit: *Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen_w = 640, .screen_h = 200 };
        self.menubar = .{};
    }

    pub fn setPointer(self: *Desktop, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }
    pub fn beginFrame(self: *Desktop) void {
        self.g.beginFrame();
    }
    pub fn endFrame(self: *Desktop) void {
        self.g.endFrame();
    }

    // Draw the desktop (res-adaptive via g.screen_w) and return the chosen action.
    pub fn render(self: *Desktop) Action {
        const g = &self.g;
        const sw = g.screen_w;
        g.rect(.{ .x = 0, .y = 0, .w = sw, .h = 200 }, gui.DESK); // green work area

        placeIcon(g, sw - 60, 22, icons.FLOPPY, "Floppy");
        placeIcon(g, sw - 60, 130, icons.TRASH, "Trash");
        const r = self.app_icon;
        placeIcon(g, r.x, r.y, icons.CARTRIDGE, "ST REPLAY"); // the app = a RAM cartridge :)
        const icon_clicked = g.edge and g.hit(r);

        var action: Action = if (icon_clicked) .launch else .none;
        if (self.menubar.process(g, &DESK_MENUS, sw, false)) |p| {
            if (p.menu == 3) action = if (p.item == 0) .res_low else .res_medium;
        }
        return action;
    }
};

// Blit a 1bpp icon (bit set = black, clear = white) at (x,y) with a centred label.
fn placeIcon(g: *gui.Gui, x: i16, y: i16, ic: icons.Icon, label: []const u8) void {
    const rowbytes: usize = (@as(usize, ic.w) + 7) / 8;
    var row: u16 = 0;
    while (row < ic.h) : (row += 1) {
        var col: u16 = 0;
        while (col < ic.w) : (col += 1) {
            const byte = ic.bits[row * rowbytes + col / 8];
            const ink = (byte >> @intCast(7 - (col % 8))) & 1 != 0;
            g.fb.setPixelValue(@intCast(x + @as(i16, @intCast(col))), @intCast(y + @as(i16, @intCast(row))), if (ink) gui.BLACK else gui.WHITE);
        }
    }
    const lw: i16 = @as(i16, @intCast(label.len)) * 8;
    g.text(label, x + @divTrunc(@as(i16, @intCast(ic.w)) - lw, 2), y + @as(i16, @intCast(ic.h)) + 2, gui.WHITE, gui.DESK);
}
