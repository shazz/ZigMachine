// --------------------------------------------------------------------------
// ZigGEM Desktop — the GEM-style desktop shell: icons, windows, menu bar and
// dialogs. Icon behaviour lives in desk_icons.zig and Set Preferences in
// prefs.zig; this file owns the Desktop state and the per-frame render loop.
// Split out of the former monolithic gem.zig with no behaviour change.
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const gui = @import("../gui.zig");
const icons = @import("../gem_icons.zig");
const prefs = @import("prefs.zig");
const desk_icons = @import("desk_icons.zig");

const ZigOS = zsrc.ZigOS;
const LogicalFB = zsrc.LogicalFB;
const Blitter = zsrc.Blitter;
const Rect = gui.Rect;
const Icon = @import("icon.zig").Icon;
const std = @import("std");

pub const Action = enum { none, launch, res_low, res_medium };

// The mounted disk's FAT, packed by the host into `disk_dir`: per file a 16-byte
// NUL-padded name + 1 type byte (0 = program/cart, 1 = data). Shown as icons in
// the FLOPPY window; double-clicking a program launches it.
const MAX_FILES: usize = 12;
const FILE_ENT: usize = 17;
const FLOPPY_TITLE = "FLOPPY DISK";

const DESK_MENUS = [_]gui.Menu{
    .{ .title = "Desk", .items = &.{ "About ZigGEM", "------------" } },
    .{ .title = "File", .items = &.{"Open"} },
    .{ .title = "View", .items = &.{"Icons"} },
    .{ .title = "Options", .items = &.{"Set Preferences"} },
};
const MENU_DESK = 0;
const MENU_FILE = 1;
const MENU_OPTIONS = 3;

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    wm: gui.Wm = .{},
    dlg: gui.Dialog = .{},
    next_win: Rect = .{ .x = desk_icons.WIN_X0, .y = desk_icons.WIN_Y0, .w = desk_icons.WIN_W, .h = desk_icons.WIN_H },
    // No app icon: GEM is generic. A mounted app-disk (e.g. ST Replay) turns the
    // FLOPPY icon into that app's launcher — see disk_app + desk_icons.openIcon.
    items: [2]Icon = .{
        .{ .x = 580, .y = 22, .bmp = icons.FLOPPY, .label = "FLOPPY", .is_app = false },
        .{ .x = 580, .y = 130, .bmp = icons.TRASH, .label = "TRASH", .is_app = false },
    },
    disk_app: bool = false, // an app-disk is inserted (host sets this)
    disk_dir: [MAX_FILES * FILE_ENT]u8 = [_]u8{0} ** (MAX_FILES * FILE_ENT), // host-filled FAT
    n_disk: u8 = 0, // number of files in the mounted disk's FAT
    launch_req: bool = false, // a program file in a FLOPPY window was double-clicked
    drag: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,
    moved: bool = false,
    sel_icon: i16 = -1, // currently selected icon (drawn inverse video), -1 = none
    pending_open: i16 = -1, // icon to open (set by a native double-click), -1 = none
    prefs: prefs.Prefs = .{}, // Options > Set Preferences dialog
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

    pub fn clampIcons(self: *Desktop) void {
        desk_icons.clampIcons(self);
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
        var action: Action = .none;
        const modal = self.dlg.active or self.prefs.active; // a dialog owns all input
        const menu_open = self.menubar.open >= 0;
        // Windows sit above icons and take input first; a press the windows (or
        // an open drop-down menu) consumed never reaches the icons.
        const consumed = !modal and self.wm.handle(g);
        const busy = modal or consumed or menu_open or self.wm.drag != null or self.wm.resize != null or self.overWindow();

        // A native double-click (routed via requestOpenAt) opens/launches now.
        if (self.pending_open >= 0) {
            desk_icons.openIcon(self, @intCast(self.pending_open), &action);
            self.pending_open = -1;
        }

        // A press selects (inverse video, GEM selects on the press) and may
        // become a drag; a native double-click opens (handled in desk_icons).
        if (self.drag) |di| {
            desk_icons.updateDrag(self, g, di);
        } else if (!busy and g.edge and g.py > gui.MENU_H) {
            desk_icons.pressIcon(self, g);
        }

        self.drawScene(g);
        self.runDialogs(g, &action);
        if (self.launch_req) { // a program file in a FLOPPY window was double-clicked
            self.launch_req = false;
            action = .launch;
        }
        return action;
    }

    // The i-th disk file's name / type / icon (laid out inside a window's rect).
    pub fn diskName(self: *const Desktop, i: usize) []const u8 {
        const s = self.disk_dir[i * FILE_ENT .. i * FILE_ENT + 16];
        var n: usize = 0;
        while (n < 16 and s[n] != 0) : (n += 1) {}
        return s[0..n];
    }
    pub fn diskType(self: *const Desktop, i: usize) u8 {
        return self.disk_dir[i * FILE_ENT + 16];
    }
    pub fn fileIcon(self: *const Desktop, i: usize, wr: Rect) Icon {
        const col: i16 = @intCast(i % 2);
        const rowi: i16 = @intCast(i / 2);
        return .{
            .x = wr.x + 12 + col * 100,
            .y = wr.y + 26 + rowi * 42, // below the window's title + info bars
            .bmp = if (self.diskType(i) == 0) icons.CARTRIDGE else icons.PROGRAM,
            .label = self.diskName(i),
            .is_app = self.diskType(i) == 0,
        };
    }
    pub fn isFloppyWin(self: *const Desktop, id: u8) bool {
        return std.mem.eql(u8, self.wm.wins[id].title, FLOPPY_TITLE);
    }

    // Draw order: desktop work area, icons, then windows (back-to-front). A FLOPPY
    // window also shows the mounted disk's files as icons.
    fn drawScene(self: *Desktop, g: *gui.Gui) void {
        g.rect(.{ .x = 0, .y = 0, .w = g.screen_w, .h = 200 }, gui.DESK); // green work area
        for (&self.items, 0..) |*it, i| it.draw(g, self.sel_icon == @as(i16, @intCast(i)));
        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open) continue;
            _ = self.wm.drawChrome(g, id, id == self.wm.topId());
            if (self.isFloppyWin(id)) {
                var f: usize = 0;
                while (f < self.n_disk) : (f += 1) {
                    var ic = self.fileIcon(f, self.wm.wins[id].r);
                    ic.draw(g, false);
                }
            }
        }
    }

    // Menu bar + modal alert + Set Preferences, drawn last (over everything).
    fn runDialogs(self: *Desktop, g: *gui.Gui, action: *Action) void {
        const modal = self.dlg.active or self.prefs.active;
        if (self.menubar.process(g, &DESK_MENUS, g.screen_w, modal or self.overWindow())) |p| self.menuPick(p, action);
        _ = self.dlg.process(g);
        // Set Preferences dialog (live-previews the background colour).
        if (self.prefs.active) switch (self.prefs.process(g)) {
            .ok => {
                self.bg_r = self.prefs.cr;
                self.bg_g = self.prefs.cg;
                self.bg_b = self.prefs.cb;
                action.* = if (self.prefs.medium) .res_medium else .res_low;
                self.prefs.active = false;
            },
            .cancel => {
                self.applyBg(); // restore the saved colour (process previewed a new one)
                self.prefs.active = false;
            },
            .none => {},
        };
    }

    fn menuPick(self: *Desktop, p: gui.MenuPick, action: *Action) void {
        switch (p.menu) {
            MENU_DESK => self.dlg.alert("ZigGEM Desktop", "A GEM-style ROM for ZigMachine."),
            MENU_FILE => if (self.sel_icon >= 0) desk_icons.openIcon(self, @intCast(self.sel_icon), action), // Open (GEM: no-op without a selection)
            MENU_OPTIONS => self.prefs.open(self.bg_r, self.bg_g, self.bg_b, self.g.screen_w == 640),
            else => {},
        }
    }

    pub fn requestOpenAt(self: *Desktop, x: i32, y: i32) void {
        desk_icons.requestOpenAt(self, x, y);
    }
};
