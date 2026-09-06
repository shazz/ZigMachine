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

const GRID: i16 = 16; // icons snap to this grid on drop (GEM-style)

const DeskIcon = struct { x: i16, y: i16, ic: icons.Icon, label: []const u8, is_app: bool };

const IC_APP = 0;
const IC_FLOPPY = 1;

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    wm: gui.Wm = .{},
    floppy_win: u8 = 0,
    items: [3]DeskIcon = .{
        .{ .x = 44, .y = 30, .ic = icons.CARTRIDGE, .label = "ST REPLAY", .is_app = true },
        .{ .x = 580, .y = 22, .ic = icons.FLOPPY, .label = "FLOPPY", .is_app = false },
        .{ .x = 580, .y = 130, .ic = icons.TRASH, .label = "TRASH", .is_app = false },
    },
    drag: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,
    grab_px: i16 = 0, // press point, to tell a click from a drag
    grab_py: i16 = 0,
    moved: bool = false,

    pub fn init(self: *Desktop, os: *ZigOS, fb: *LogicalFB, blit: *Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen_w = 640, .screen_h = 200 };
        self.menubar = .{};
        self.wm = .{};
        self.floppy_win = self.wm.add(.{ .r = .{ .x = 40, .y = 40, .w = 180, .h = 110 }, .title = "FLOPPY DISK" });
        self.wm.wins[self.floppy_win].open = false; // opens when the Floppy icon is clicked
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

    // Keep icons on-screen (called when the resolution/screen width changes).
    pub fn clampIcons(self: *Desktop) void {
        for (&self.items) |*it| self.clamp(it);
    }
    fn clamp(self: *Desktop, it: *DeskIcon) void {
        it.x = @max(0, @min(it.x, self.g.screen_w - @as(i16, @intCast(it.ic.w))));
        it.y = @max(gui.MENU_H + 2, @min(it.y, 200 - @as(i16, @intCast(it.ic.h)) - 10));
    }

    fn overWindow(self: *Desktop) bool {
        for (self.wins()) |w| {
            if (w.open and self.g.px >= w.r.x and self.g.px < w.r.x + w.r.w and
                self.g.py >= w.r.y and self.g.py < w.r.y + w.r.h) return true;
        }
        return false;
    }
    fn wins(self: *Desktop) []const gui.Window {
        return self.wm.wins[0..self.wm.n];
    }

    // Draw the desktop (res-adaptive) + windows; handle icon drag/click; return action.
    pub fn render(self: *Desktop) Action {
        const g = &self.g;
        const sw = g.screen_w;
        var action: Action = .none;

        // Windows sit above icons and take input first.
        self.wm.handle(g);
        const busy = self.wm.drag != null or self.wm.resize != null or self.overWindow();

        // --- icon drag (snap on drop) / click (launch app, or open the floppy window) ---
        if (self.drag) |di| {
            if (!g.down) {
                if (self.moved) self.snap(di) else self.clickIcon(di, &action);
                self.drag = null;
            } else {
                if (@abs(@as(i16, @intCast(g.px)) - self.grab_px) > 3 or @abs(@as(i16, @intCast(g.py)) - self.grab_py) > 3) self.moved = true;
                if (self.moved) {
                    self.items[di].x = @intCast(@as(i32, g.px) - self.grab_dx);
                    self.items[di].y = @intCast(@as(i32, g.py) - self.grab_dy);
                    self.clamp(&self.items[di]); // keep the icon inside the desktop while dragging
                }
            }
        } else if (!busy and g.edge and g.py >= gui.MENU_H) {
            for (self.items, 0..) |it, i| {
                if (g.hit(.{ .x = it.x, .y = it.y, .w = @intCast(it.ic.w), .h = @intCast(it.ic.h) })) {
                    self.drag = @intCast(i);
                    self.moved = false;
                    self.grab_px = @intCast(g.px);
                    self.grab_py = @intCast(g.py);
                    self.grab_dx = @intCast(@as(i32, g.px) - it.x);
                    self.grab_dy = @intCast(@as(i32, g.py) - it.y);
                    break;
                }
            }
        }

        // --- draw: desktop, icons, windows, menu (top) ---
        g.rect(.{ .x = 0, .y = 0, .w = sw, .h = 200 }, gui.DESK); // green work area
        for (self.items) |it| placeIcon(g, it.x, it.y, it.ic, it.label);
        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open) continue;
            _ = self.wm.drawChrome(g, id, id == self.wm.topId()); // empty window (white interior)
        }
        if (self.menubar.process(g, &DESK_MENUS, sw, self.overWindow())) |p| {
            if (p.menu == 3) action = if (p.item == 0) .res_low else .res_medium;
        }
        return action;
    }

    fn clickIcon(self: *Desktop, di: u8, action: *Action) void {
        if (self.items[di].is_app) {
            action.* = .launch;
        } else if (di == IC_FLOPPY) {
            self.wm.wins[self.floppy_win].open = true; // open the disk window
            self.wm.toFront(self.floppy_win);
        }
    }

    fn snap(self: *Desktop, di: u8) void {
        const it = &self.items[di];
        it.x = @divFloor(it.x + GRID / 2, GRID) * GRID;
        it.y = @divFloor(it.y + GRID / 2, GRID) * GRID;
        self.clamp(it);
    }
};

// Draw a GEM icon with TRANSPARENCY (ink=black, body=white, outside=transparent,
// so the desktop shows through the icon's silhouette) and a caps label beneath.
fn placeIcon(g: *gui.Gui, x: i16, y: i16, ic: icons.Icon, label: []const u8) void {
    const rowbytes: usize = (@as(usize, ic.w) + 7) / 8;
    var row: u16 = 0;
    while (row < ic.h) : (row += 1) {
        var col: u16 = 0;
        while (col < ic.w) : (col += 1) {
            const idx = row * rowbytes + col / 8;
            const sh: u3 = @intCast(7 - (col % 8));
            const px: u16 = @intCast(x + @as(i16, @intCast(col)));
            const py: u16 = @intCast(y + @as(i16, @intCast(row)));
            if ((ic.ink[idx] >> sh) & 1 != 0) {
                g.fb.setPixelValue(px, py, gui.BLACK);
            } else if ((ic.body[idx] >> sh) & 1 != 0) {
                g.fb.setPixelValue(px, py, gui.WHITE); // enclosed body
            } // else: outside the silhouette -> leave transparent (desktop shows)
        }
    }
    const lw: i16 = @as(i16, @intCast(label.len)) * 8;
    g.text(label, x + @divTrunc(@as(i16, @intCast(ic.w)) - lw, 2), y + @as(i16, @intCast(ic.h)) + 2, gui.WHITE, gui.DESK);
}
