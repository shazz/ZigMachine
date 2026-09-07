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
const about_mod = @import("about.zig");
const trash_mod = @import("trash.zig");
const info_mod = @import("info.zig");
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
// Host-packed directory entry: 16-byte name · 1 type · 4 size (u32 LE) · 4 date
// (u32 LE, YYYYMMDD). Must match the packer in docs/sealed-loader.js.
const FILE_ENT: usize = 25;
const FLOPPY_TITLE = "A:\\";

// In-memory folders (the mounted disk is a flat read-only FAT; folders live only
// in RAM). A folder has a parent (-1 = root disk) and a window-title path.
const MAX_FOLDERS: usize = 8;
const Folder = struct {
    name: [12]u8 = [_]u8{0} ** 12,
    nlen: u8 = 0,
    parent: i16 = -1, // -1 = root, else a folder index
    title: [40]u8 = [_]u8{0} ** 40, // "A:\FOO\BAR" for the window title
    tlen: u8 = 0,
};
const WIN_NONE: i16 = -2; // win_dir sentinel: not a FLOPPY/folder window
const WIN_ROOT: i16 = -1; // win_dir: the root disk (A:\)

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
    about: about_mod.About = .{}, // Desk > Desktop Info... dialog
    trash: trash_mod.DeleteDlg = .{}, // DELETE FILE(S) confirm (file dropped on TRASH)
    info: info_mod.Info = .{}, // Show Info... (DISK/FILE/FOLDER INFORMATION)
    file_drag: i16 = -1, // file being dragged out of a window, -1 = none
    file_moved: bool = false, // the file drag has moved past the initial press
    trash_target: i16 = -1, // file awaiting the DELETE FILE(S) confirm
    bg_r: u8 = 1, // desktop background colour (Prefs); GEM default here is a teal
    bg_g: u8 = 160,
    bg_b: u8 = 164,
    view: ViewMode = .icons, // View menu: show FLOPPY contents as icons or text
    sort: SortKey = .name, // View menu: sort order for FLOPPY contents
    folders: [MAX_FOLDERS]Folder = [_]Folder{.{}} ** MAX_FOLDERS,
    n_folders: u8 = 0,
    win_dir: [gui.MAX_WIN]i16 = [_]i16{WIN_NONE} ** gui.MAX_WIN, // per-window directory
    sel_folder: i16 = -1, // selected folder in the top window, -1 = none
    new_seq: u8 = 0, // auto-name counter for New Folder
    grow_a: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, // zoom-box: from
    grow_b: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, // zoom-box: to
    grow_t: u8 = 0, // zoom-box frames remaining (0 = idle)
    open_src: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 }, // source rect for the next window open

    pub fn init(self: *Desktop, os: *ZigOS, fb: *LogicalFB, blit: *Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen_w = 640, .screen_h = 200 };
        self.menubar = .{};
        self.wm = .{};
        self.dlg = .{};
        self.prefs = .{};
        self.about = .{};
        self.trash = .{};
        self.info = .{};
        self.n_folders = 0;
        self.new_seq = 0;
        self.win_dir = [_]i16{WIN_NONE} ** gui.MAX_WIN;
        self.applyBg(); // paint the desktop palette with the configured background
    }

    fn applyBg(self: *Desktop) void {
        self.g.fb.setPaletteEntry(gui.DESK, .{ .r = self.bg_r, .g = self.bg_g, .b = self.bg_b, .a = 255 });
    }

    pub fn setPointer(self: *Desktop, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }
    // Character keyboard: feeds the Show Info rename field while it's open.
    pub fn key(self: *Desktop, cp: u32) void {
        if (self.info.active) self.info.key(cp);
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
        const modal = self.dlg.active or self.prefs.active or self.about.active or self.trash.active or self.info.active; // a dialog owns all input
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
            self.selectAt(@intCast(g.px), @intCast(g.py));
            self.file_drag = self.sel_file; // arm a possible drag onto the desktop (TRASH; files only)
            self.file_moved = false;
        }
        // File drag: once it has moved, a release over the TRASH asks to delete it.
        if (!modal and self.file_drag >= 0) {
            if (g.down) {
                if (!g.edge) self.file_moved = true;
            } else {
                // Released over the TRASH after a press on a window file = a drag to
                // delete (the press was over the window, so reaching the trash is a drag).
                if (self.items[desk_icons.IC_TRASH].hitAt(@intCast(g.px), @intCast(g.py))) {
                    self.trash_target = self.file_drag;
                    self.trash.open(0, 1); // 0 folders, 1 file
                }
                self.file_drag = -1;
                self.file_moved = false;
            }
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
    pub fn diskSize(self: *const Desktop, i: usize) u32 {
        return std.mem.readInt(u32, self.disk_dir[i * FILE_ENT + 17 ..][0..4], .little);
    }
    pub fn diskDate(self: *const Desktop, i: usize) u32 { // YYYYMMDD
        return std.mem.readInt(u32, self.disk_dir[i * FILE_ENT + 21 ..][0..4], .little);
    }
    // The display order of the disk's files for the current sort (a permutation of
    // 0..n_disk). All four keys sort on real host-packed data.
    pub fn fileOrder(self: *const Desktop) [MAX_FILES]u8 {
        var ord: [MAX_FILES]u8 = undefined;
        var i: u8 = 0;
        while (i < self.n_disk) : (i += 1) ord[i] = i;
        var a: usize = 1; // insertion sort (n_disk <= 12)
        while (a < self.n_disk) : (a += 1) {
            const v = ord[a];
            var b: usize = a;
            while (b > 0 and self.sortLess(v, ord[b - 1])) : (b -= 1) ord[b] = ord[b - 1];
            ord[b] = v;
        }
        return ord;
    }
    fn sortLess(self: *const Desktop, x: u8, y: u8) bool {
        switch (self.sort) {
            .type => {
                const tx = self.diskType(x);
                const ty = self.diskType(y);
                if (tx != ty) return tx < ty; // programs (0) before documents (1)
            },
            .size => {
                const sx = self.diskSize(x);
                const sy = self.diskSize(y);
                if (sx != sy) return sx > sy; // largest first
            },
            .date => {
                const dx = self.diskDate(x);
                const dy = self.diskDate(y);
                if (dx != dy) return dx > dy; // newest first
            },
            .name => {},
        }
        return std.mem.lessThan(u8, self.diskName(x), self.diskName(y)); // name (and tie-break)
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

    // --- folders (in-memory directory tree over the flat read-only disk) ---
    fn folderName(self: *const Desktop, fidx: u8) []const u8 {
        return self.folders[fidx].name[0..self.folders[fidx].nlen];
    }
    fn dirFileCount(self: *const Desktop, dir: i16) usize {
        return if (dir == WIN_ROOT) self.n_disk else 0; // disk files exist only at root
    }
    fn dirFolderCount(self: *const Desktop, dir: i16) usize {
        var n: usize = 0;
        var k: u8 = 0;
        while (k < self.n_folders) : (k += 1) {
            if (self.folders[k].parent == dir) n += 1;
        }
        return n;
    }
    fn dirNthFolder(self: *const Desktop, dir: i16, rank: usize) u8 {
        var seen: usize = 0;
        var k: u8 = 0;
        while (k < self.n_folders) : (k += 1) {
            if (self.folders[k].parent == dir) {
                if (seen == rank) return k;
                seen += 1;
            }
        }
        return 0;
    }
    // A folder icon laid out at DISPLAY SLOT (folders follow the files).
    fn folderIconSlot(self: *const Desktop, slot: usize, fidx: u8, content: Rect) Icon {
        const bmp = icons.FOLDER;
        const cols: i16 = @max(1, @divTrunc(content.w, icon_mod.CELL_W));
        const s: i16 = @intCast(slot);
        const iw: i16 = @intCast(bmp.w);
        const ih: i16 = @intCast(bmp.h);
        return .{
            .x = content.x + @mod(s, cols) * icon_mod.CELL_W + @divTrunc(icon_mod.CELL_W - iw, 2),
            .y = content.y + @divTrunc(s, cols) * icon_mod.CELL_H + (4 + 30) - ih,
            .bmp = bmp,
            .label = self.folderName(fidx),
            .is_app = false,
            .bounds = content,
        };
    }

    const Hit = union(enum) { none, file: u8, folder: u8 };

    // What a window's directory shows under (x,y): a file, a folder, or nothing.
    pub fn dirHitAt(self: *Desktop, dir: i16, content: Rect, x: i16, y: i16) Hit {
        const nf = self.dirFileCount(dir);
        if (dir == WIN_ROOT) {
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                const a = ord[p];
                const hit = if (self.view == .icons) self.fileIconSlot(p, a, content).hitAt(x, y) else gui.inRect(fileRowRect(p, content), x, y);
                if (hit) return .{ .file = a };
            }
        }
        const fc = self.dirFolderCount(dir);
        var rank: usize = 0;
        while (rank < fc) : (rank += 1) {
            const fidx = self.dirNthFolder(dir, rank);
            const hit = if (self.view == .icons) self.folderIconSlot(nf + rank, fidx, content).hitAt(x, y) else gui.inRect(fileRowRect(nf + rank, content), x, y);
            if (hit) return .{ .folder = fidx };
        }
        return .none;
    }
    // The topmost open FLOPPY/folder window (the one a press just raised).
    pub fn topFloppy(self: *Desktop) ?struct { id: u8, dir: i16, content: Rect } {
        var wi: usize = self.wm.n;
        while (wi > 0) {
            wi -= 1;
            const id = self.wm.order[wi];
            if (!self.wm.wins[id].open or !self.isFloppyWin(id)) continue;
            return .{ .id = id, .dir = self.win_dir[id], .content = self.wm.contentRect(id) };
        }
        return null;
    }
    pub fn isFloppyWin(self: *const Desktop, id: u8) bool {
        return self.win_dir[id] != WIN_NONE;
    }
    // Nothing mounted and no folders yet -> opening A:\ is an error (no disk).
    pub fn rootEmpty(self: *const Desktop) bool {
        return self.n_disk == 0 and self.dirFolderCount(WIN_ROOT) == 0;
    }

    // Single-click a file/folder in a window -> select it (inverse video); clicking
    // empty space clears the selection.
    fn selectAt(self: *Desktop, x: i16, y: i16) void {
        self.sel_file = -1;
        self.sel_folder = -1;
        if (self.topFloppy()) |w| switch (self.dirHitAt(w.dir, w.content, x, y)) {
            .file => |a| {
                self.sel_file = a;
                self.sel_icon = -1;
            },
            .folder => |f| {
                self.sel_folder = f;
                self.sel_icon = -1;
            },
            .none => {},
        };
    }

    // New Folder... : create an (auto-named) folder in the top window's directory,
    // or at root if no window is open. Rename waits on the keyboard ABI.
    fn newFolder(self: *Desktop) void {
        if (self.n_folders >= MAX_FOLDERS) {
            self.dlg.alert("Too many folders.", "Delete one and try again.");
            return;
        }
        const dir: i16 = if (self.topFloppy()) |w| w.dir else WIN_ROOT;
        const f = &self.folders[self.n_folders];
        f.* = .{ .parent = dir };
        self.new_seq += 1;
        const nm = std.fmt.bufPrint(&f.name, "NEWDIR{d}", .{self.new_seq}) catch "NEWDIR";
        f.nlen = @intCast(nm.len);
        const t = if (dir == WIN_ROOT)
            std.fmt.bufPrint(&f.title, "A:\\{s}", .{nm}) catch "A:\\"
        else blk: {
            const par = self.folders[@intCast(dir)];
            break :blk std.fmt.bufPrint(&f.title, "{s}\\{s}", .{ par.title[0..par.tlen], nm }) catch "A:\\";
        };
        f.tlen = @intCast(t.len);
        self.n_folders += 1;
    }

    // Open a NEW window on a folder (GEM opens each folder in its own window;
    // closing it goes back to the parent).
    pub fn openFolderWindow(self: *Desktop, fidx: u8) void {
        const f = self.folders[fidx];
        self.addFloppyWindow(f.title[0..f.tlen], @intCast(fidx));
    }

    // Shared open: a FLOPPY/folder window with cascade + the one-icon min size.
    pub fn addFloppyWindow(self: *Desktop, title: []const u8, dir: i16) void {
        const r = self.next_win;
        const min_w = icon_mod.CELL_W + 2 + gui.SCROLL;
        const min_h = gui.TITLE_H + gui.INFO_H + icon_mod.CELL_H + gui.SCROLL;
        if (self.wm.tryAdd(.{ .r = r, .title = title, .min_w = min_w, .min_h = min_h })) |id| {
            self.win_dir[id] = dir;
            self.sel_file = -1;
            self.sel_folder = -1;
            self.startGrow(self.open_src, r); // GEM zoom-box: dotted frame grows icon -> window
            var nx = r.x + 16;
            var ny = r.y + 12;
            if (nx + r.w > self.g.screen_w or ny + r.h > 200) {
                nx = desk_icons.WIN_X0;
                ny = desk_icons.WIN_Y0;
            }
            self.next_win = .{ .x = nx, .y = ny, .w = r.w, .h = r.h };
        } else {
            self.dlg.alert("The Desktop has no more windows.", "Please close a window first.");
        }
    }

    const GROW_STEPS: u8 = 6;
    fn startGrow(self: *Desktop, from: Rect, to: Rect) void {
        self.grow_a = from;
        self.grow_b = to;
        self.grow_t = GROW_STEPS;
    }
    // GEM zoom-box: a dotted frame interpolated from grow_a to grow_b over a few frames.
    fn drawGrow(self: *Desktop, g: *gui.Gui) void {
        if (self.grow_t == 0) return;
        const n: i16 = GROW_STEPS;
        const k: i16 = n - @as(i16, @intCast(self.grow_t)) + 1; // 1..n
        const a = self.grow_a;
        const b = self.grow_b;
        dottedFrame(g, .{
            .x = a.x + @divTrunc((b.x - a.x) * k, n),
            .y = a.y + @divTrunc((b.y - a.y) * k, n),
            .w = a.w + @divTrunc((b.w - a.w) * k, n),
            .h = a.h + @divTrunc((b.h - a.h) * k, n),
        }, gui.BLACK);
        self.grow_t -= 1;
    }

    // Draw order: desktop work area, icons, then windows (back-to-front). A FLOPPY
    // window also shows the mounted disk's files as icons.
    fn drawScene(self: *Desktop, g: *gui.Gui) void {
        g.rect(.{ .x = 0, .y = 0, .w = g.screen_w, .h = 200 }, gui.DESK); // green work area
        for (&self.items, 0..) |*it, i| {
            // A dragged file over the TRASH highlights it as a valid drop target.
            const drop_hot = i == desk_icons.IC_TRASH and self.file_drag >= 0 and it.hitAt(@intCast(g.px), @intCast(g.py));
            it.draw(g, self.sel_icon == @as(i16, @intCast(i)) or drop_hot);
        }
        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open) continue;
            const content = self.wm.drawChrome(g, id, id == self.wm.topId());
            if (self.isFloppyWin(id)) self.drawDir(g, self.win_dir[id], content);
        }
        // Drag ghost: a GEM dotted OUTLINE (icon box + label box) follows the pointer.
        if (self.file_drag >= 0 and self.file_moved) {
            const bmp = if (self.diskType(@intCast(self.file_drag)) == 0) icons.PROGRAM else icons.DOCUMENT;
            const iw: i16 = @intCast(bmp.w);
            const ih: i16 = @intCast(bmp.h);
            const gx = @as(i16, @intCast(g.px)) - @divTrunc(iw, 2);
            const gy = @as(i16, @intCast(g.py)) - @divTrunc(ih, 2);
            dottedFrame(g, .{ .x = gx, .y = gy, .w = iw, .h = ih }, gui.BLACK); // icon outline
            dottedFrame(g, .{ .x = gx - 8, .y = gy + ih + 2, .w = iw + 16, .h = 8 }, gui.BLACK); // label box
        }
        self.drawGrow(g); // window-open zoom-box
    }

    // Remove a file from the in-memory FAT (the mounted disk itself is read-only).
    fn removeFile(self: *Desktop, idx: usize) void {
        var i = idx;
        while (i + 1 < self.n_disk) : (i += 1) {
            const dst = i * FILE_ENT;
            const src = (i + 1) * FILE_ENT;
            @memcpy(self.disk_dir[dst .. dst + FILE_ENT], self.disk_dir[src .. src + FILE_ENT]);
        }
        if (self.n_disk > 0) self.n_disk -= 1;
        self.sel_file = -1;
    }

    // A window's directory: disk files (root only) then folders, in view + sort order.
    fn drawDir(self: *Desktop, g: *gui.Gui, dir: i16, content: Rect) void {
        const nf = self.dirFileCount(dir);
        if (dir == WIN_ROOT) {
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                const a = ord[p];
                if (self.view == .icons) {
                    var ic = self.fileIconSlot(p, a, content);
                    ic.draw(g, self.sel_file == @as(i16, @intCast(a)));
                } else self.drawFileRow(g, p, a, content);
            }
        }
        const fc = self.dirFolderCount(dir);
        var rank: usize = 0;
        while (rank < fc) : (rank += 1) {
            const fidx = self.dirNthFolder(dir, rank);
            const sel = self.sel_folder == @as(i16, @intCast(fidx));
            if (self.view == .icons) {
                var ic = self.folderIconSlot(nf + rank, fidx, content);
                ic.draw(g, sel);
            } else self.drawFolderRow(g, nf + rank, fidx, content, sel);
        }
    }

    fn drawFolderRow(self: *Desktop, g: *gui.Gui, slot: usize, fidx: u8, content: Rect, sel: bool) void {
        const r = gui.Rect{ .x = content.x, .y = content.y + @as(i16, @intCast(slot)) * TROW_H, .w = content.w, .h = TROW_H };
        if (r.y + TROW_H > content.y + content.h) return;
        if (sel) g.rect(r, gui.BLACK);
        const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
        const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
        g.text(self.folderName(fidx), content.x + 4, r.y + 1, ink, paper);
        g.text("<DIR>", content.x + content.w - 6 * 8 - 2, r.y + 1, ink, paper);
    }

    // One text-view row, TOS columns: NAME(8) EXT(3) SIZE DATE(MM-DD-YY) TIME.
    // Columns sit at fixed cell offsets; each is drawn only if it fits the window,
    // so a narrow window drops the right columns instead of overflowing.
    fn drawFileRow(self: *Desktop, g: *gui.Gui, slot: usize, fidx: u8, content: Rect) void {
        const r = gui.Rect{ .x = content.x, .y = content.y + @as(i16, @intCast(slot)) * TROW_H, .w = content.w, .h = TROW_H };
        if (r.y + TROW_H > content.y + content.h) return; // clip below the window
        const sel = self.sel_file == @as(i16, @intCast(fidx));
        if (sel) g.rect(r, gui.BLACK);
        const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
        const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
        const y = r.y + 1;
        const right = content.x + content.w;
        const cx = content.x + 4;

        const name = self.diskName(fidx);
        var base = name;
        var ext: []const u8 = "";
        if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
            base = name[0..dot];
            ext = name[dot + 1 ..];
        }
        g.text(base[0..@min(base.len, 8)], cx, y, ink, paper); // NAME (8)
        if (cx + 12 * 8 <= right) g.text(ext[0..@min(ext.len, 3)], cx + 9 * 8, y, ink, paper); // EXT (3)
        if (cx + 20 * 8 <= right) { // SIZE, right-aligned at col 20
            var sb: [12]u8 = undefined;
            const s = fmtSize(&sb, self.diskSize(fidx));
            g.text(s, cx + 20 * 8 - @as(i16, @intCast(s.len)) * 8, y, ink, paper);
        }
        if (cx + 30 * 8 <= right) { // DATE (MM-DD-YY) at col 22
            var db: [12]u8 = undefined;
            g.text(fmtDate(&db, self.diskDate(fidx)), cx + 22 * 8, y, ink, paper);
        }
        if (cx + 38 * 8 <= right) g.text("12:00am", cx + 31 * 8, y, ink, paper); // TIME (host FAT has none)
    }

    // Menu bar + modal alert + Set Preferences, drawn last (over everything).
    // Build the desktop menus for THIS frame so ticks (view/sort) and disabled
    // states (no selection, Format) reflect live desktop state.
    fn buildMenus(self: *const Desktop, buf: *MenuBuf) [4]gui.Menu {
        const has_sel = self.sel_icon >= 0 or self.sel_file >= 0 or self.sel_folder >= 0;
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
        const modal = self.dlg.active or self.prefs.active or self.about.active or self.trash.active or self.info.active;
        var buf: MenuBuf = undefined;
        const menus = self.buildMenus(&buf);
        // Only a modal dialog locks the bar. (Don't lock on overWindow: a drop-down
        // that overlaps a window must still accept item clicks — the drop-on-hover
        // guard already blocks menus opening mid window-drag.)
        if (self.menubar.process(g, &menus, g.screen_w, modal)) |p| self.menuPick(p, action);
        _ = self.dlg.process(g);
        _ = self.about.process(g); // Desktop Info... (modal while active)
        switch (self.trash.process(g)) { // DELETE FILE(S) confirm
            .ok => {
                if (self.trash_target >= 0) self.removeFile(@intCast(self.trash_target));
                self.trash_target = -1;
            },
            .cancel => self.trash_target = -1,
            .none => {},
        }
        switch (self.info.process(g)) { // Show Info... (DISK/FILE/FOLDER INFORMATION)
            .ok => self.applyRename(),
            else => {},
        }
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
            MENU_DESK => self.about.open(), // Desktop Info...
            MENU_FILE => switch (p.item) {
                0 => self.openSelection(action), // Open
                1 => self.showInfo(), // Show Info...
                3 => self.newFolder(), // New Folder... (auto-named; rename via keyboard later)
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
        if (self.sel_folder >= 0) {
            self.openFolderWindow(@intCast(self.sel_folder));
        } else if (self.sel_icon >= 0) {
            desk_icons.openIcon(self, @intCast(self.sel_icon), action);
        } else if (self.sel_file >= 0 and self.diskType(@intCast(self.sel_file)) == 0) {
            self.launch_req = true;
        }
    }

    // Show Info... for the current selection (name + kind). Disk is read-only, so
    // this is informational.
    fn showInfo(self: *Desktop) void {
        if (self.sel_folder >= 0) {
            self.info.openFile(self.folderName(@intCast(self.sel_folder)), 0, 0, true);
        } else if (self.sel_file >= 0) {
            const f: u8 = @intCast(self.sel_file);
            self.info.openFile(self.diskName(f), self.diskSize(f), self.diskDate(f), false);
        } else if (self.sel_icon == desk_icons.IC_FLOPPY) {
            var used: u32 = 0; // DISK INFORMATION for drive A: (ref: real TOS)
            var i: u8 = 0;
            while (i < self.n_disk) : (i += 1) used += self.diskSize(i);
            const cap: u32 = 726528; // a 3.5" DS floppy
            self.info.openDisk(@intCast(self.dirFolderCount(WIN_ROOT)), self.n_disk, used, if (cap > used) cap - used else 0);
        } else if (self.sel_icon >= 0) {
            self.dlg.alert(self.items[@intCast(self.sel_icon)].label, "Kind: Desktop icon");
        }
    }

    // Apply the (keyboard-edited) name from the Show Info dialog to the selection.
    fn applyRename(self: *Desktop) void {
        const nm = self.info.name[0..self.info.nlen];
        if (nm.len == 0) return;
        if (self.sel_folder >= 0) {
            const f = &self.folders[@intCast(self.sel_folder)];
            const n = @min(nm.len, f.name.len);
            @memcpy(f.name[0..n], nm[0..n]);
            f.nlen = @intCast(n);
            if (f.parent == WIN_ROOT) {
                const t = std.fmt.bufPrint(&f.title, "A:\\{s}", .{f.name[0..f.nlen]}) catch "A:\\";
                f.tlen = @intCast(t.len);
            } else {
                const par = self.folders[@intCast(f.parent)];
                const t = std.fmt.bufPrint(&f.title, "{s}\\{s}", .{ par.title[0..par.tlen], f.name[0..f.nlen] }) catch "A:\\";
                f.tlen = @intCast(t.len);
            }
        } else if (self.sel_file >= 0) {
            const b = @as(usize, @intCast(self.sel_file)) * FILE_ENT;
            var i: usize = 0;
            while (i < 16) : (i += 1) self.disk_dir[b + i] = if (i < nm.len) nm[i] else 0;
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

// A single pixel, clipped to the visible area (dotted overlays can run to an edge).
fn plot(g: *gui.Gui, x: i16, y: i16, c: u8) void {
    if (x >= 0 and x < g.screen_w and y >= 0 and y < 200) g.fb.setPixelValue(@intCast(x), @intCast(y), c);
}
// A GEM dotted rectangle outline (every-other pixel) — zoom-box + drag ghost.
fn dottedFrame(g: *gui.Gui, r: gui.Rect, c: u8) void {
    var x: i16 = r.x;
    while (x < r.x + r.w) : (x += 2) {
        plot(g, x, r.y, c);
        plot(g, x, r.y + r.h - 1, c);
    }
    var y: i16 = r.y;
    while (y < r.y + r.h) : (y += 2) {
        plot(g, r.x, y, c);
        plot(g, r.x + r.w - 1, y, c);
    }
}

fn fmtSize(buf: []u8, n: u32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch "?";
}
fn fmtDate(buf: []u8, d: u32) []const u8 { // YYYYMMDD -> "MM-DD-YY" (TOS text view)
    if (d == 0) return "--------";
    return std.fmt.bufPrint(buf, "{d:0>2}-{d:0>2}-{d:0>2}", .{ (d / 100) % 100, d % 100, (d / 10000) % 100 }) catch "?";
}
