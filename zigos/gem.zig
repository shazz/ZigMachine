// --------------------------------------------------------------------------
// ZigGEM — the "ROM": a GEM-style desktop + the GUI libraries an application
// links against. Think of it as the system in ROM; an app in apps/ is the RAM
// cartridge that plugs into it. The desktop boots first, shows icons, and
// launches an app; the app draws over the whole screen and returns here on quit.
//
// The GUI toolkit (windows, menus, dialogs, buttons) lives in gui.zig and is
// re-exported here as `gem.gui` — the ROM's library surface. Apps use it.
// --------------------------------------------------------------------------
const std = @import("std");
const zsrc = @import("zigos.zig");
pub const gui = @import("gui.zig"); // the ROM's GUI libraries (apps link this)
pub const icons = @import("gem_icons.zig"); // 1bpp icons ripped from a GEM icon sheet

const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const Rect = gui.Rect;

pub const Action = enum { none, launch, res_low, res_medium };

const DESK_MENUS = [_]gui.Menu{
    .{ .title = "Desk", .items = &.{ "About ZigGEM", "------------" } },
    .{ .title = "File", .items = &.{"Open"} },
    .{ .title = "View", .items = &.{"Icons"} },
    .{ .title = "Options", .items = &.{"Set Preferences"} },
};
const MENU_DESK = 0;
const MENU_FILE = 1;
const MENU_OPTIONS = 3;

const GRID: i16 = 16; // icons snap to this grid on drop (GEM-style)

const DeskIcon = struct { x: i16, y: i16, ic: icons.Icon, label: []const u8, is_app: bool };

const IC_APP = 0;
const IC_FLOPPY = 1;

// Disk windows: first one here, each further one cascaded right + down.
const WIN_X0: i16 = 24;
const WIN_Y0: i16 = 24;
const WIN_W: i16 = 213; // the reference low-res disk window is 213x99
const WIN_H: i16 = 99;
const CASCADE_DX: i16 = 16;
const CASCADE_DY: i16 = 12;

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    wm: gui.Wm = .{},
    dlg: gui.Dialog = .{},
    next_win: Rect = .{ .x = WIN_X0, .y = WIN_Y0, .w = WIN_W, .h = WIN_H }, // where the next disk window opens
    items: [3]DeskIcon = .{
        .{ .x = 44, .y = 30, .ic = icons.CARTRIDGE, .label = "ST REPLAY", .is_app = true },
        .{ .x = 580, .y = 22, .ic = icons.FLOPPY, .label = "FLOPPY", .is_app = false },
        .{ .x = 580, .y = 130, .ic = icons.TRASH, .label = "TRASH", .is_app = false },
    },
    drag: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,
    moved: bool = false,
    sel_icon: i16 = -1, // currently selected icon (drawn inverse video), -1 = none
    pending_open: i16 = -1, // icon to open (set by a native double-click), -1 = none
    prefs: Prefs = .{}, // Options > Set Preferences dialog
    bg_r: u8 = 1, // desktop background colour (Prefs); GEM default here is a teal
    bg_g: u8 = 160,
    bg_b: u8 = 164,

    pub fn init(self: *Desktop, os: *ZigOS, fb: *LogicalFB, blit: *Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen_w = 640, .screen_h = 200 };
        self.menubar = .{};
        self.wm = .{};
        self.dlg = .{};
        self.prefs = .{};
        self.applyBg(); // paint the desktop palette with the configured background
    }

    fn applyBg(self: *Desktop) void {
        self.g.fb.setPaletteEntry(gui.DESK, .{ .r = self.bg_r, .g = self.bg_g, .b = self.bg_b, .a = 255 });
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
        it.y = @max(gui.MENU_H + 1, @min(it.y, 200 - @as(i16, @intCast(it.ic.h)) - 10));
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
        const modal = self.dlg.active or self.prefs.active; // a dialog owns all input

        // Windows sit above icons and take input first; a press the windows (or
        // an open drop-down menu) consumed never reaches the icons.
        const menu_open = self.menubar.open >= 0;
        const consumed = !modal and self.wm.handle(g);
        const busy = modal or consumed or menu_open or self.wm.drag != null or self.wm.resize != null or self.overWindow();

        // A native double-click (routed via requestOpenAt) opens/launches now.
        if (self.pending_open >= 0) {
            self.openIcon(@intCast(self.pending_open), &action);
            self.pending_open = -1;
        }

        // --- icon interaction: a press selects (inverse video, GEM selects on
        // the press) and may become a drag; a native double-click opens. ---
        if (self.drag) |di| {
            if (!g.down) { // release: snap to the grid after a drag
                if (self.moved) self.snap(di);
                self.drag = null;
            } else {
                const nx: i16 = @intCast(@as(i32, g.px) - self.grab_dx);
                const ny: i16 = @intCast(@as(i32, g.py) - self.grab_dy);
                if (nx != self.items[di].x or ny != self.items[di].y) self.moved = true;
                if (self.moved) {
                    self.items[di].x = nx;
                    self.items[di].y = ny;
                    self.clamp(&self.items[di]); // keep the icon inside the desktop while dragging
                }
            }
        } else if (!busy and g.edge and g.py > gui.MENU_H) {
            self.pressIcon(g);
        }

        // --- draw: desktop, icons, windows, menu, then the modal alert on top ---
        g.rect(.{ .x = 0, .y = 0, .w = sw, .h = 200 }, gui.DESK); // green work area
        for (self.items, 0..) |it, i| placeIcon(g, it.x, it.y, it.ic, it.label, self.sel_icon == @as(i16, @intCast(i)));
        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open) continue;
            _ = self.wm.drawChrome(g, id, id == self.wm.topId()); // empty window (white interior)
        }
        if (self.menubar.process(g, &DESK_MENUS, sw, modal or self.overWindow())) |p| self.menuPick(p, &action);
        _ = self.dlg.process(g);
        // Set Preferences dialog (drawn last; live-previews the background colour).
        if (self.prefs.active) switch (self.prefs.process(g)) {
            .ok => {
                self.bg_r = self.prefs.cr;
                self.bg_g = self.prefs.cg;
                self.bg_b = self.prefs.cb;
                action = if (self.prefs.medium) .res_medium else .res_low;
                self.prefs.active = false;
            },
            .cancel => {
                self.applyBg(); // restore the saved colour (process previewed a new one)
                self.prefs.active = false;
            },
            .none => {},
        };
        return action;
    }

    fn menuPick(self: *Desktop, p: gui.MenuPick, action: *Action) void {
        switch (p.menu) {
            MENU_DESK => self.dlg.alert("ZigGEM Desktop", "A GEM-style ROM for ZigMachine."),
            MENU_FILE => if (self.sel_icon >= 0) self.openIcon(@intCast(self.sel_icon), action), // Open (GEM: no-op without a selection)
            MENU_OPTIONS => self.prefs.open(self.bg_r, self.bg_g, self.bg_b, self.g.screen_w == 640),
            else => {},
        }
    }

    // A press landed on the desktop (below the menu, no window busy): select the
    // icon hit (GEM selects on the press) and arm a drag, or deselect on empty
    // desktop. (Opening is a separate native double-click — see requestOpenAt.)
    fn pressIcon(self: *Desktop, g: *gui.Gui) void {
        for (self.items, 0..) |it, i| {
            if (!g.hit(.{ .x = it.x, .y = it.y, .w = @intCast(it.ic.w), .h = @intCast(it.ic.h) })) continue;
            self.sel_icon = @intCast(i);
            self.drag = @intCast(i);
            self.moved = false;
            self.grab_dx = @intCast(@as(i32, g.px) - it.x);
            self.grab_dy = @intCast(@as(i32, g.py) - it.y);
            return;
        }
        self.sel_icon = -1; // pressed empty desktop → deselect
    }

    // The loader detected a native double-click at (x,y) (logical coords): open
    // the icon under the cursor. Windows open here directly; launching an app
    // needs an Action, so that is deferred to the next render via pending_open.
    pub fn requestOpenAt(self: *Desktop, x: i32, y: i32) void {
        if (self.dlg.active) return;
        self.drag = null; // the double-click's presses armed a drag — a double-click is not a drag
        for (self.items, 0..) |it, i| {
            if (x >= it.x and x < it.x + @as(i16, @intCast(it.ic.w)) and
                y >= it.y and y < it.y + @as(i16, @intCast(it.ic.h)))
            {
                self.sel_icon = @intCast(i);
                if (it.is_app) {
                    self.pending_open = @intCast(i); // launch handled in render()
                } else if (i == IC_FLOPPY) {
                    self.openFloppy();
                }
                return;
            }
        }
    }

    fn openIcon(self: *Desktop, di: u8, action: *Action) void {
        if (self.items[di].is_app) {
            action.* = .launch;
        } else if (di == IC_FLOPPY) {
            self.openFloppy();
        }
    }

    // GEM Desktop: every open of a disk spawns a NEW window (7 max), each one
    // cascaded right + down from the previous, wrapping back when it would
    // leave the screen. Over the cap, GEM raises the "no more windows" alert.
    fn openFloppy(self: *Desktop) void {
        const r = self.next_win;
        if (self.wm.tryAdd(.{ .r = r, .title = "FLOPPY DISK", .info = "0 bytes used in 0 items." }) == null) {
            self.dlg.alert("The Desktop has no more windows.", "Please close a window first.");
            return;
        }
        var nx = r.x + CASCADE_DX;
        var ny = r.y + CASCADE_DY;
        if (nx + r.w > self.g.screen_w or ny + r.h > 200) {
            nx = WIN_X0;
            ny = WIN_Y0;
        }
        self.next_win = .{ .x = nx, .y = ny, .w = r.w, .h = r.h };
    }

    fn snap(self: *Desktop, di: u8) void {
        const it = &self.items[di];
        it.x = @divFloor(it.x + GRID / 2, GRID) * GRID;
        it.y = @divFloor(it.y + GRID / 2, GRID) * GRID;
        self.clamp(it);
    }
};

// Options > Set Preferences: a modal GEM dialog (centred, 1px black frame + drop
// shadow, like the real SET PREFERENCES) to pick the screen resolution and the
// desktop background colour. Mouse-only: each RGB channel has -/+ steppers (±8,
// clamped 0..255); the colour previews live via the DESK palette entry.
const Prefs = struct {
    active: bool = false,
    cr: u8 = 1,
    cg: u8 = 160,
    cb: u8 = 164,
    medium: bool = false,

    const Result = enum { none, ok, cancel };
    const W: i16 = 252;
    const H: i16 = 152;

    fn open(self: *Prefs, r: u8, g: u8, b: u8, medium: bool) void {
        self.* = .{ .active = true, .cr = r, .cg = g, .cb = b, .medium = medium };
    }

    fn clampStep(v: u8, d: i16) u8 {
        return @intCast(@max(0, @min(255, @as(i16, v) + d)));
    }

    fn channel(g: *gui.Gui, x: i16, y: i16, label: []const u8, v: u8) u8 {
        var nv = v;
        g.text(label, x, y + 2, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = x + 14, .y = y, .w = 16, .h = 12 }, "-", false)) nv = clampStep(nv, -8);
        var buf: [3]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d:0>3}", .{nv}) catch "???";
        g.text(s, x + 36, y + 2, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = x + 62, .y = y, .w = 16, .h = 12 }, "+", false)) nv = clampStep(nv, 8);
        return nv;
    }

    fn process(self: *Prefs, g: *gui.Gui) Result {
        const dx = @divTrunc(g.screen_w - W, 2);
        const dy = @divTrunc(@as(i16, 200) - H, 2);
        g.rect(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.WHITE); // no shadow (dialogs are flat; only windows cast one)
        g.frame(.{ .x = dx, .y = dy, .w = W, .h = H }, gui.BLACK); // GEM double frame:
        g.frame(.{ .x = dx + 3, .y = dy + 3, .w = W - 6, .h = H - 6 }, gui.BLACK); // outer + inner
        title(g, "SET PREFERENCES", dx, dy + 10, W);

        // Background colour: R/G/B steppers on a grid + a live swatch.
        g.text("Background colour:", dx + 22, dy + 32, gui.BLACK, gui.WHITE);
        self.cr = channel(g, dx + 30, dy + 50, "R", self.cr);
        self.cg = channel(g, dx + 30, dy + 68, "G", self.cg);
        self.cb = channel(g, dx + 30, dy + 86, "B", self.cb);
        g.fb.setPaletteEntry(gui.DESK, .{ .r = self.cr, .g = self.cg, .b = self.cb, .a = 255 }); // live preview
        g.rect(.{ .x = dx + 158, .y = dy + 50, .w = 66, .h = 48 }, gui.DESK); // swatch
        g.frame(.{ .x = dx + 158, .y = dy + 50, .w = 66, .h = 48 }, gui.BLACK);

        g.text("Resolution:", dx + 22, dy + 110, gui.BLACK, gui.WHITE);
        if (g.button(.{ .x = dx + 116, .y = dy + 108, .w = 44, .h = 12 }, "Low", !self.medium)) self.medium = false;
        if (g.button(.{ .x = dx + 166, .y = dy + 108, .w = 60, .h = 12 }, "Medium", self.medium)) self.medium = true;

        if (g.buttonThick(.{ .x = dx + 52, .y = dy + 128, .w = 56, .h = 14 }, "OK", false, 3)) return .ok;
        if (g.buttonThick(.{ .x = dx + 138, .y = dy + 128, .w = 70, .h = 14 }, "Cancel", false, 2)) return .cancel;
        return .none;
    }
};

// Centre a title string in a `width`-wide area starting at x.
fn title(g: *gui.Gui, s: []const u8, x: i16, y: i16, width: i16) void {
    g.text(s, x + @divTrunc(width - @as(i16, @intCast(s.len)) * 8, 2), y, gui.BLACK, gui.WHITE);
}

// Icon label geometry: GEM draws the name in the 6x6 system font in a fixed-width
// field so all labels line up regardless of length — 11 characters wide plus a
// 2px margin each side, centred under the icon.
const LABEL_FW: i16 = 6; // 6x6 icon-label font
const LABEL_CHARS: i16 = 11;
const LABEL_MARGIN: i16 = 2;
const LABEL_W: i16 = LABEL_CHARS * LABEL_FW + 2 * LABEL_MARGIN;
const LABEL_H: i16 = 6 + 2; // 6x6 font + 1px top/bottom

// Draw a GEM icon with TRANSPARENCY (ink=black, body=white, outside=transparent,
// so the desktop shows through the icon's silhouette) and a caps label beneath
// on a fixed-width white box (black text). When `sel`, the icon is inverse-video
// (GEM selection): silhouette pixels swap ink/body and the label box inverts.
fn placeIcon(g: *gui.Gui, x: i16, y: i16, ic: icons.Icon, label: []const u8, sel: bool) void {
    const ink_c: u8 = if (sel) gui.WHITE else gui.BLACK;
    const body_c: u8 = if (sel) gui.BLACK else gui.WHITE;
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
                g.fb.setPixelValue(px, py, ink_c);
            } else if ((ic.body[idx] >> sh) & 1 != 0) {
                g.fb.setPixelValue(px, py, body_c); // enclosed body
            } // else: outside the silhouette -> leave transparent (desktop shows)
        }
    }
    // Fixed-width label box, centred under the icon and clamped on-screen.
    const cx = x + @divTrunc(@as(i16, @intCast(ic.w)), 2);
    const box_x = @max(0, @min(cx - @divTrunc(LABEL_W, 2), g.screen_w - LABEL_W));
    const box_y = y + @as(i16, @intCast(ic.h)) + 2;
    const box_bg: u8 = if (sel) gui.BLACK else gui.WHITE;
    g.rect(.{ .x = box_x, .y = box_y, .w = LABEL_W, .h = LABEL_H }, box_bg);
    const lw: i16 = @as(i16, @intCast(label.len)) * LABEL_FW;
    g.textSmall(label, box_x + @divTrunc(LABEL_W - lw, 2), box_y + 1, if (sel) gui.WHITE else gui.BLACK, box_bg);
}
