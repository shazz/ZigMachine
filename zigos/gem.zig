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

const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const Rect = gui.Rect;

pub const Desktop = struct {
    g: gui.Gui = undefined,
    app_icon: Rect = .{ .x = 40, .y = 40, .w = 64, .h = 50 },

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
        g.rect(.{ .x = 0, .y = 0, .w = 640, .h = 200 }, gui.DESK);
        g.rect(.{ .x = 0, .y = 0, .w = 640, .h = gui.MENU_H }, gui.WHITE);
        g.blit.fill(g.fb, 0, gui.MENU_H, 640, 1, gui.BLACK);
        g.text("  Desk     File     View     Options", 6, 2, gui.BLACK, gui.WHITE);

        diskIcon(g, .{ .x = 560, .y = 22, .w = 52, .h = 44 }, "Floppy");
        trashIcon(g, .{ .x = 560, .y = 130, .w = 52, .h = 44 }, "Trash");
        g.text("ZigGEM desktop  -  double-click an app to open it", 40, 178, gui.WHITE, gui.DESK);

        return self.appIcon();
    }

    // The ST Replay application icon (a little cassette). Returns clicked.
    fn appIcon(self: *Desktop) bool {
        const g = &self.g;
        const r = self.app_icon;
        const hover = g.hit(.{ .x = r.x - 2, .y = r.y - 2, .w = r.w + 4, .h = r.h + 14 });
        // cassette body
        g.bevel(.{ .x = r.x, .y = r.y, .w = r.w, .h = 34 }, if (hover) gui.LGRAY else gui.WHITE, true);
        g.rect(.{ .x = r.x + 6, .y = r.y + 6, .w = r.w - 12, .h = 10 }, gui.BLACK); // tape window
        g.blit.fill(g.fb, r.x + 12, r.y + 22, 6, 6, gui.BLACK); // reels
        g.blit.fill(g.fb, r.x + r.w - 18, r.y + 22, 6, 6, gui.BLACK);
        g.text("ST REPLAY", r.x - 12, r.y + 38, gui.WHITE, gui.DESK);
        return g.edge and g.hit(.{ .x = r.x, .y = r.y, .w = r.w, .h = 34 });
    }
};

fn diskIcon(g: *gui.Gui, r: Rect, label: []const u8) void {
    g.bevel(.{ .x = r.x, .y = r.y, .w = r.w, .h = 34 }, gui.LGRAY, true);
    g.rect(.{ .x = r.x + r.w - 16, .y = r.y + 4, .w = 10, .h = 12 }, gui.BLACK); // shutter
    g.rect(.{ .x = r.x + 8, .y = r.y + 20, .w = r.w - 16, .h = 8 }, gui.WHITE); // label strip
    g.text(label, r.x + 2, r.y + 36, gui.WHITE, gui.DESK);
}

fn trashIcon(g: *gui.Gui, r: Rect, label: []const u8) void {
    g.bevel(.{ .x = r.x + 8, .y = r.y, .w = r.w - 16, .h = 34 }, gui.MGRAY, true);
    g.blit.fill(g.fb, r.x + 6, r.y, @intCast(r.w - 12), 4, gui.BLACK); // lid
    g.text(label, r.x + 6, r.y + 36, gui.WHITE, gui.DESK);
}
