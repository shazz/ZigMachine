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

pub const Desktop = struct {
    g: gui.Gui = undefined,
    app_icon: Rect = .{ .x = 44, .y = 30, .w = icons.CARTRIDGE.w, .h = icons.CARTRIDGE.h },

    pub fn init(self: *Desktop, os: *ZigOS, fb: *LogicalFB, blit: *Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen_w = 640, .screen_h = 200 };
    }

    pub fn setPointer(self: *Desktop, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }
    pub fn beginFrame(self: *Desktop) void {
        self.g.beginFrame();
    }

    // Draw the desktop; return true on the frame the ST Replay icon is clicked.
    pub fn render(self: *Desktop) bool {
        const g = &self.g;
        g.rect(.{ .x = 0, .y = 0, .w = 640, .h = 200 }, gui.DESK); // green work area
        g.rect(.{ .x = 0, .y = 0, .w = 640, .h = gui.MENU_H }, gui.WHITE);
        g.blit.fill(g.fb, 0, gui.MENU_H, 640, 1, gui.BLACK);
        g.text("  Desk     File     View     Options", 6, 2, gui.BLACK, gui.WHITE);

        placeIcon(g, 566, 24, icons.FLOPPY, "Floppy");
        placeIcon(g, 566, 130, icons.TRASH, "Trash");

        const r = self.app_icon;
        placeIcon(g, r.x, r.y, icons.CARTRIDGE, "ST REPLAY"); // the app = a RAM cartridge :)
        return g.edge and g.hit(r);
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
