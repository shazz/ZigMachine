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
const icon_mod = @import("icon.zig");
const Icon = icon_mod.Icon;
const std = @import("std");

pub const Action = enum { none, launch, res_low, res_medium };

// FLOPPY window content view + sort order (Desktop's View menu).
pub const ViewMode = enum { icons, text };
pub const SortKey = enum { name, date, size, type };

// The mounted disk's FAT, packed by the host into `disk_dir`: per file a 16-byte
// NUL-padded name + 1 type byte (0 = program/cart, 1 = data). Shown as icons in
// the FLOPPY window; double-clicking a program launches it.
const MAX_FILES: usize = 12;
const FILE_ENT: usize = 17;
const FLOPPY_TITLE = "A:\\";

// Menus are built per-frame (buildMenus) so ticks/disabled track live state.
const MENU_DESK = 0;
const MENU_FILE = 1;
const MENU_VIEW = 2;
const MENU_OPTIONS = 3;

// Stack storage for the per-frame menu items (their slices are handed to the
// menu bar within the same frame; see buildMenus).
const MenuBuf = struct {
    desk: [1]gui.MenuItem = undefined,
    file: [8]gui.MenuItem = undefined,
    view: [7]gui.MenuItem = undefined,
    opt: [1]gui.MenuItem = undefined,
};

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    wm: gui.Wm = .{},
    dlg: gui.Dialog = .{},
    next_win: Rect = .{ .x = desk_icons.WIN_X0, .y = desk_icons.WIN_Y0, .w = desk_icons.WIN_W, .h = desk_icons.WIN_H },
    // No app icon: GEM is generic. A mounted app-disk (e.g. ST Replay) turns the
    // FLOPPY icon into that app's launcher — see disk_app + desk_icons.openIcon.
    items: [2]Icon = .{
        .{ .x = 8, .y = 24, .bmp = icons.FLOPPY, .label = "FLOPPY", .is_app = false }, // top-left
        .{ .x = 8, .y = 136, .bmp = icons.TRASH, .label = "TRASH", .is_app = false }, // bottom-left
    },
    disk_app: bool = false, // an app-disk is inserted (host sets this)
    disk_dir: [MAX_FILES * FILE_ENT]u8 = [_]u8{0} ** (MAX_FILES * FILE_ENT), // host-filled FAT
    n_disk: u8 = 0, // number of files in the mounted disk's FAT
    launch_req: bool = false, // a program file in a FLOPPY window was double-clicked
    drag: ?u8 = null,
    grab_dx: i16 = 0,
    grab_dy: i16 = 0,
    moved: bool = false,
    sel_icon: i16 = -1, // currently selected desktop icon (inverse video), -1 = none
    sel_file: i16 = -1, // currently selected file in a FLOPPY window, -1 = none
    pending_open: i16 = -1, // icon to open (set by a native double-click), -1 = none
    prefs: prefs.Prefs = .{}, // Options > Set Preferences dialog
    bg_r: u8 = 1, // desktop background colour (Prefs); GEM default here is a teal
    bg_g: u8 = 160,
    bg_b: u8 = 164,
    view: ViewMode = .icons, // View menu: show FLOPPY contents as icons or text
    sort: SortKey = .name, // View menu: sort order for FLOPPY contents

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
        // A press over a window selects the file icon under it (GEM selects on
        // press); a double-click then opens it (requestOpenAt -> launch).
        if (!modal and self.drag == null and g.edge and self.overWindow()) {
            self.selectFileAt(@intCast(g.px), @intCast(g.py));
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
    // The display order of the disk's files for the current sort (a permutation of
    // 0..n_disk). Name/Type sort on real data; Date/Size keep FAT order (the FAT the
    // host packs carries no date or size yet — the menu still ticks the choice).
    pub fn fileOrder(self: *const Desktop) [MAX_FILES]u8 {
        var ord: [MAX_FILES]u8 = undefined;
        var i: u8 = 0;
        while (i < self.n_disk) : (i += 1) ord[i] = i;
        if (self.sort == .name or self.sort == .type) {
            var a: usize = 1; // insertion sort (n_disk <= 12)
            while (a < self.n_disk) : (a += 1) {
                const v = ord[a];
                var b: usize = a;
                while (b > 0 and self.sortLess(v, ord[b - 1])) : (b -= 1) ord[b] = ord[b - 1];
                ord[b] = v;
            }
        }
        return ord;
    }
    fn sortLess(self: *const Desktop, x: u8, y: u8) bool {
        if (self.sort == .type) {
            const tx = self.diskType(x);
            const ty = self.diskType(y);
            if (tx != ty) return tx < ty; // programs (0) before documents (1)
        }
        return std.mem.lessThan(u8, self.diskName(x), self.diskName(y)); // name (also type tie-break)
    }

    // Lay a file out on the window's 72x40 icon grid by DISPLAY SLOT (so sorting
    // reorders the layout); content (name/icon) comes from the actual file index.
    pub fn fileIconSlot(self: *const Desktop, slot: usize, fidx: u8, content: Rect) Icon {
        const bmp = if (self.diskType(fidx) == 0) icons.PROGRAM else icons.DOCUMENT;
        const cols: i16 = @max(1, @divTrunc(content.w, icon_mod.CELL_W));
        const s: i16 = @intCast(slot);
        const col = @mod(s, cols);
        const row = @divTrunc(s, cols);
        const iw: i16 = @intCast(bmp.w);
        const ih: i16 = @intCast(bmp.h);
        const baseline: i16 = 4 + 30; // top margin + tallest icon; icon BOTTOMS align
        return .{
            .x = content.x + col * icon_mod.CELL_W + @divTrunc(icon_mod.CELL_W - iw, 2),
            .y = content.y + row * icon_mod.CELL_H + baseline - ih, // bottom-align -> labels align
            .bmp = bmp,
            .label = self.diskName(fidx),
            .is_app = self.diskType(fidx) == 0,
            .bounds = content,
        };
    }

    // Text-view: one row per file (DISPLAY SLOT), name + a right type tag.
    const TROW_H: i16 = 10;
    pub fn fileRowRect(slot: usize, content: Rect) Rect {
        const s: i16 = @intCast(slot);
        return .{ .x = content.x, .y = content.y + s * TROW_H, .w = content.w, .h = TROW_H };
    }

    // Actual file index under (x,y) in the topmost open FLOPPY window, honouring the
    // current view (icon or text) and sort order; -1 if none / not over a window.
    pub fn fileAt(self: *Desktop, x: i16, y: i16) i16 {
        var wi: usize = self.wm.n;
        while (wi > 0) {
            wi -= 1;
            const id = self.wm.order[wi];
            if (!self.wm.wins[id].open or !self.isFloppyWin(id)) continue;
            const content = self.wm.contentRect(id);
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                const a = ord[p];
                const hit = if (self.view == .icons)
                    self.fileIconSlot(p, a, content).hitAt(x, y)
                else
                    gui.inRect(fileRowRect(p, content), x, y);
                if (hit) return @intCast(a);
            }
            return -1; // the topmost floppy window consumed the point
        }
        return -1;
    }
    pub fn isFloppyWin(self: *const Desktop, id: u8) bool {
        return std.mem.eql(u8, self.wm.wins[id].title, FLOPPY_TITLE);
    }

    // Single-click a file in a FLOPPY window -> select it (inverse video), like a
    // desktop icon; clicking away clears the file selection.
    fn selectFileAt(self: *Desktop, x: i16, y: i16) void {
        const a = self.fileAt(x, y);
        if (a >= 0) {
            self.sel_file = a;
            self.sel_icon = -1; // file + desktop selections are exclusive
        } else {
            self.sel_file = -1;
        }
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
            const content = self.wm.drawChrome(g, id, id == self.wm.topId());
            if (self.isFloppyWin(id)) self.drawFiles(g, content);
        }
    }

    // A FLOPPY window's files, in the current view + sort order.
    fn drawFiles(self: *Desktop, g: *gui.Gui, content: Rect) void {
        const ord = self.fileOrder();
        var p: usize = 0;
        while (p < self.n_disk) : (p += 1) {
            const a = ord[p];
            if (self.view == .icons) {
                var ic = self.fileIconSlot(p, a, content);
                ic.draw(g, self.sel_file == @as(i16, @intCast(a)));
            } else {
                self.drawFileRow(g, p, a, content);
            }
        }
    }

    // One text-view row: NAME | EXT | SIZE | DATE (ref TOS text view). The host FAT
    // carries only name+type today, so size/date show placeholders for now.
    fn drawFileRow(self: *Desktop, g: *gui.Gui, slot: usize, fidx: u8, content: Rect) void {
        const r = gui.Rect{ .x = content.x, .y = content.y + @as(i16, @intCast(slot)) * TROW_H, .w = content.w, .h = TROW_H };
        if (r.y + TROW_H > content.y + content.h) return; // clip below the window
        const sel = self.sel_file == @as(i16, @intCast(fidx));
        if (sel) g.rect(r, gui.BLACK);
        const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
        const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
        const name = self.diskName(fidx);
        var base = name;
        var ext: []const u8 = "";
        if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
            base = name[0..dot];
            ext = name[dot + 1 ..];
        }
        const y = r.y + 1;
        g.text(base, r.x + 4, y, ink, paper); // name
        g.text(ext, r.x + 4 + 9 * 8, y, ink, paper); // ext
        g.text("----", r.x + 4 + 13 * 8, y, ink, paper); // size (host FAT has none yet)
        g.text("--/--/--", r.x + 4 + 18 * 8, y, ink, paper); // date (host FAT has none yet)
    }

    // Menu bar + modal alert + Set Preferences, drawn last (over everything).
    // Build the desktop menus for THIS frame so ticks (view/sort) and disabled
    // states (no selection, Format) reflect live desktop state.
    fn buildMenus(self: *const Desktop, buf: *MenuBuf) [4]gui.Menu {
        const has_sel = self.sel_icon >= 0 or self.sel_file >= 0;
        buf.desk = .{.{ .label = "Desktop Info..." }};
        buf.file = .{
            .{ .label = "Open", .disabled = !has_sel },
            .{ .label = "Show Info...", .disabled = !has_sel },
            .{ .label = "----------" },
            .{ .label = "New Folder..." },
            .{ .label = "Close" },
            .{ .label = "Close Window" },
            .{ .label = "----------" },
            .{ .label = "Format...", .disabled = true },
        };
        buf.view = .{
            .{ .label = "Show as Icons", .tick = self.view == .icons },
            .{ .label = "Show as Text", .tick = self.view == .text },
            .{ .label = "----------" },
            .{ .label = "Sort by Name", .tick = self.sort == .name },
            .{ .label = "Sort by Date", .tick = self.sort == .date },
            .{ .label = "Sort by Size", .tick = self.sort == .size },
            .{ .label = "Sort by Type", .tick = self.sort == .type },
        };
        buf.opt = .{.{ .label = "Set Preferences" }};
        return .{
            .{ .title = "Desk", .items = &buf.desk },
            .{ .title = "File", .items = &buf.file },
            .{ .title = "View", .items = &buf.view },
            .{ .title = "Options", .items = &buf.opt },
        };
    }

    fn runDialogs(self: *Desktop, g: *gui.Gui, action: *Action) void {
        const modal = self.dlg.active or self.prefs.active;
        var buf: MenuBuf = undefined;
        const menus = self.buildMenus(&buf);
        if (self.menubar.process(g, &menus, g.screen_w, modal or self.overWindow())) |p| self.menuPick(p, action);
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
            MENU_DESK => self.dlg.alert("GEM Desktop", "ZigGEM - a GEM-style ROM for ZigMachine."), // TODO #7: TOS-style dialog
            MENU_FILE => switch (p.item) {
                0 => self.openSelection(action), // Open
                1 => self.showInfo(), // Show Info...
                3 => self.dlg.alert("New Folder", "Not available on a read-only disk."), // TODO: needs keyboard entry
                4, 5 => self.closeTopWindow(), // Close / Close Window
                else => {}, // separators + Format... (disabled)
            },
            MENU_VIEW => switch (p.item) {
                0 => self.view = .icons,
                1 => self.view = .text,
                3 => self.sort = .name,
                4 => self.sort = .date,
                5 => self.sort = .size,
                6 => self.sort = .type,
                else => {}, // separator
            },
            MENU_OPTIONS => self.prefs.open(self.bg_r, self.bg_g, self.bg_b, self.g.screen_w == 640),
            else => {},
        }
    }

    // Open the current selection: a desktop icon opens its window/app; a selected
    // file launches it if it's a program (GEM: no-op with nothing selected).
    fn openSelection(self: *Desktop, action: *Action) void {
        if (self.sel_icon >= 0) {
            desk_icons.openIcon(self, @intCast(self.sel_icon), action);
        } else if (self.sel_file >= 0 and self.diskType(@intCast(self.sel_file)) == 0) {
            self.launch_req = true;
        }
    }

    // Show Info... for the current selection (name + kind). Disk is read-only, so
    // this is informational.
    fn showInfo(self: *Desktop) void {
        if (self.sel_file >= 0) {
            const kind = if (self.diskType(@intCast(self.sel_file)) == 0) "Kind: Program" else "Kind: Document";
            self.dlg.alert(self.diskName(@intCast(self.sel_file)), kind);
        } else if (self.sel_icon >= 0) {
            self.dlg.alert(self.items[@intCast(self.sel_icon)].label, "Kind: Desktop icon");
        }
    }

    // Close the topmost open window (Close / Close Window).
    fn closeTopWindow(self: *Desktop) void {
        if (self.wm.n == 0) return;
        const id = self.wm.topId();
        if (self.wm.wins[id].open) {
            self.wm.wins[id].open = false;
            self.sel_file = -1;
        }
    }

    pub fn requestOpenAt(self: *Desktop, x: i32, y: i32) void {
        desk_icons.requestOpenAt(self, x, y);
    }
};
