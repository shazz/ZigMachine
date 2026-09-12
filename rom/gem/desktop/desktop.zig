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
const stamp = @import("stamp.zig");
const deskinf = @import("deskinf.zig");

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
pub const MAX_FILES: usize = 12;
// Host-packed directory entry: 16-byte name · 1 type · 4 size (u32 LE) · 4 date
// (u32 LE, YYYYMMDD). Must match the packer in docs/sealed-loader.js.
pub const FILE_ENT: usize = 25;
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
// A directory window's layout frame. `clip` is the real content rectangle (all
// that may be painted); `org` is where item (0,0) is placed — `clip` shifted by
// the window's scroll offset; `cols` is the icon grid's width in cells, FIXED
// when the window opened, so resizing the window SCROLLS the icons instead of
// re-wrapping them (GEM keeps a directory's layout put).
pub const View = struct { clip: Rect, org: Rect, cols: i16 };

// win_geom is indexed by directory: WIN_ROOT (-1) first, then folder 0..N-1.
fn geomSlot(dir: i16) usize {
    return @intCast(dir + 1);
}

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
    opt: [3]gui.MenuItem = undefined,
};

pub const Desktop = struct {
    g: gui.Gui = undefined,
    menubar: gui.MenuBar = .{},
    wm: gui.Wm = .{},
    dlg: gui.Dialog = .{},
    next_win: Rect = .{ .x = desk_icons.WIN_X0, .y = desk_icons.WIN_Y0, .w = desk_icons.WIN_W, .h = desk_icons.WIN_H },
    // No app icon: GEM is generic. A mounted app-disk (e.g. ST Replay) turns the
    // FLOPPY icon into that app's launcher — see disk_app + desk_icons.openIcon.
    // Positions are set on the desktop grid in init() — see placeDefaultIcons.
    items: [2]Icon = .{
        .{ .x = 0, .y = 0, .bmp = icons.FLOPPY, .label = "FLOPPY DISK", .is_app = false },
        .{ .x = 0, .y = 0, .bmp = icons.TRASH, .label = "TRASH", .is_app = false },
    },
    disk_app: bool = false, // an app-disk is inserted (host sets this)
    disk_dir: [MAX_FILES * FILE_ENT]u8 = [_]u8{0} ** (MAX_FILES * FILE_ENT), // host-filled FAT
    n_disk: u8 = 0, // number of files in the mounted disk's FAT
    launch_req: bool = false, // a program file in a FLOPPY window was double-clicked
    // WHICH program. -1 = "the disk's app" (the FLOPPY icon acting as a launcher,
    // which names no file), resolved by launchName() to the first program on the
    // disk. The host needs a NAME, not an index: it reads the file out of the
    // mounted disk's FAT and instantiates it as the next cart.
    launch_file: i16 = -1,
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
    copy: trash_mod.DeleteDlg = .{}, // COPY FOLDERS / ITEMS confirm (file dropped on a folder)
    file_drag: i16 = -1, // file being dragged out of a window, -1 = none
    file_moved: bool = false, // the file drag has moved past the initial press
    file_gx: i16 = 0, // grab offset inside the dragged file's icon (see armFileGrab)
    file_gy: i16 = 0,
    trash_target: i16 = -1, // file awaiting the DELETE FILE(S) confirm
    bg_r: u8 = 1, // desktop background colour (Prefs); GEM default here is a teal
    bg_g: u8 = 160,
    bg_b: u8 = 164,
    view: ViewMode = .icons, // View menu: show FLOPPY contents as icons or text
    sort: SortKey = .name, // View menu: sort order for FLOPPY contents
    folders: [MAX_FOLDERS]Folder = [_]Folder{.{}} ** MAX_FOLDERS,
    n_folders: u8 = 0,
    win_dir: [gui.MAX_WIN]i16 = [_]i16{WIN_NONE} ** gui.MAX_WIN, // per-window directory
    win_cols: [gui.MAX_WIN]i16 = [_]i16{1} ** gui.MAX_WIN, // icon grid width, fixed at open
    // Each DIRECTORY remembers where its window was and how big, so closing and
    // reopening it puts it back rather than restarting the cascade. Indexed by
    // dir + 1 (WIN_ROOT is -1); w == 0 means "never opened".
    inf_buf: [deskinf.MAX_BYTES]u8 = [_]u8{0} ** deskinf.MAX_BYTES, // DESKTOP.INF text
    win_geom: [MAX_FOLDERS + 1]Rect = [_]Rect{.{ .x = 0, .y = 0, .w = 0, .h = 0 }} ** (MAX_FOLDERS + 1),
    // Backing store for each window's GEM info line ("N bytes used in M items.").
    // Window.info is a slice, and Desktop is static, so it may point in here.
    win_info: [gui.MAX_WIN][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** gui.MAX_WIN,
    sel_folder: i16 = -1, // selected folder in the top window, -1 = none
    sel_files: u16 = 0, // rubber-band multi-select: bit per file
    sel_folders: u16 = 0, // rubber-band multi-select: bit per folder
    band: bool = false, // rubber-band marquee in progress
    band_x: i16 = 0,
    band_y: i16 = 0,
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
        self.copy = .{};
        self.band = false;
        self.sel_files = 0;
        self.sel_folders = 0;
        self.sel_folder = -1;
        self.n_folders = 0;
        self.new_seq = 0;
        self.win_dir = [_]i16{WIN_NONE} ** gui.MAX_WIN;
        self.placeDefaultIcons();
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
        const modal = self.dlg.active or self.prefs.active or self.about.active or self.trash.active or self.info.active or self.copy.active; // a dialog owns all input
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
            self.pressInWindow(@intCast(g.px), @intCast(g.py));
        }
        // Rubber-band: while dragging, the marquee grows (drawn in drawScene); on
        // release, every item it touches becomes selected.
        if (self.band and !g.down) {
            self.bandSelect();
            self.band = false;
        }
        // File drag: release over the TRASH deletes; release over a folder copies.
        if (!modal and self.file_drag >= 0) {
            if (g.down) {
                if (!g.edge) self.file_moved = true;
            } else {
                self.dropFileDrag(@intCast(g.px), @intCast(g.py));
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
    // The program a .launch action refers to. Empty when the disk holds none, so
    // the caller can report "no program on this disk" instead of booting nothing.
    pub fn launchName(self: *const Desktop) []const u8 {
        if (self.launch_file >= 0 and self.launch_file < self.n_disk) {
            const i: usize = @intCast(self.launch_file);
            if (self.diskType(i) == 0) return self.diskName(i);
        }
        var i: usize = 0; // the FLOPPY-as-launcher case: the disk's first program
        while (i < self.n_disk) : (i += 1) if (self.diskType(i) == 0) return self.diskName(i);
        return &.{};
    }

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
    pub fn fileIconSlot(self: *const Desktop, slot: usize, fidx: u8, v: View) Icon {
        const bmp = if (self.diskType(fidx) == 0) icons.PROGRAM else icons.DOCUMENT;
        const s: i16 = @intCast(slot);
        const col = @mod(s, v.cols);
        const row = @divTrunc(s, v.cols);
        const a = icon_mod.artBox(bmp); // the ART, not the (sometimes padded) bitmap
        return .{
            .x = v.org.x + col * icon_mod.CELL_W + @divTrunc(icon_mod.CELL_W - a.w, 2) - a.x,
            .y = v.org.y + row * icon_mod.CELL_H + ICON_BASELINE - a.y - a.h, // bottom-align -> labels align
            .bmp = bmp,
            .label = self.diskName(fidx),
            .is_app = self.diskType(fidx) == 0,
            .bounds = v.clip,
        };
    }

    // Text-view: one row per file (DISPLAY SLOT), name + a right type tag.
    // Icon BOTTOMS sit on this line inside a cell, so every label in a row lines
    // up regardless of how tall (or how padded) the bitmap is.
    const ICON_BASELINE: i16 = 4 + 30; // top margin + tallest icon
    const TROW_H: i16 = 10;
    const TOS_COLS: i16 = 37; // NAME(8) EXT(3) SIZE DATE TIME — see drawFileRow
    pub fn fileRowRect(slot: usize, v: View) Rect {
        const s: i16 = @intCast(slot);
        return .{ .x = v.clip.x, .y = v.org.y + s * TROW_H, .w = v.clip.w, .h = TROW_H };
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
    fn folderIconSlot(self: *const Desktop, slot: usize, fidx: u8, v: View) Icon {
        const bmp = icons.FOLDER;
        const s: i16 = @intCast(slot);
        const a = icon_mod.artBox(bmp);
        return .{
            .x = v.org.x + @mod(s, v.cols) * icon_mod.CELL_W + @divTrunc(icon_mod.CELL_W - a.w, 2) - a.x,
            .y = v.org.y + @divTrunc(s, v.cols) * icon_mod.CELL_H + ICON_BASELINE - a.y - a.h,
            .bmp = bmp,
            .label = self.folderName(fidx),
            .is_app = false,
            .bounds = v.clip,
        };
    }

    const Hit = union(enum) { none, file: u8, folder: u8 };

    // What a window's directory shows under (x,y): a file, a folder, or nothing.
    pub fn dirHitAt(self: *Desktop, dir: i16, v: View, x: i16, y: i16) Hit {
        const nf = self.dirFileCount(dir);
        if (dir == WIN_ROOT) {
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                const a = ord[p];
                const hit = if (self.view == .icons) self.fileIconSlot(p, a, v).hitAt(x, y) else gui.inRect(fileRowRect(p, v), x, y);
                if (hit) return .{ .file = a };
            }
        }
        const fc = self.dirFolderCount(dir);
        var rank: usize = 0;
        while (rank < fc) : (rank += 1) {
            const fidx = self.dirNthFolder(dir, rank);
            const hit = if (self.view == .icons) self.folderIconSlot(nf + rank, fidx, v).hitAt(x, y) else gui.inRect(fileRowRect(nf + rank, v), x, y);
            if (hit) return .{ .folder = fidx };
        }
        return .none;
    }
    // The topmost open FLOPPY/folder window (the one a press just raised).
    pub fn topFloppy(self: *Desktop) ?struct { id: u8, dir: i16, view: View } {
        var wi: usize = self.wm.n;
        while (wi > 0) {
            wi -= 1;
            const id = self.wm.order[wi];
            if (!self.wm.wins[id].open or !self.isFloppyWin(id)) continue;
            return .{ .id = id, .dir = self.win_dir[id], .view = self.viewOf(id) };
        }
        return null;
    }

    // The layout frame for window `id`: its content rect, the same rect shifted
    // by the scroll offset, and the icon grid width frozen at open time.
    pub fn viewOf(self: *Desktop, id: u8) View {
        const c = self.wm.contentRect(id);
        const w = &self.wm.wins[id];
        return .{
            .clip = c,
            .org = .{
                .x = c.x - w.hscroll * self.hStep(),
                .y = c.y - w.vscroll * self.vStep(),
                .w = c.w,
                .h = c.h,
            },
            .cols = self.win_cols[id],
        };
    }

    // One click of a scroll arrow moves the content by exactly one ITEM: an icon
    // cell in icon view, a row / a character cell in text view.
    fn vStep(self: *const Desktop) i16 {
        return if (self.view == .icons) icon_mod.CELL_H else TROW_H;
    }
    fn hStep(self: *const Desktop) i16 {
        return if (self.view == .icons) icon_mod.CELL_W else gui.CELL;
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
    // Record where inside the dragged file's icon the pointer grabbed it, so the
    // ghost keeps that offset (GEM never re-centres the outline on the cursor).
    // In text view there is no icon box to grab, so fall back to centring.
    fn armFileGrab(self: *Desktop, fidx: u8, v: View, x: i16, y: i16) void {
        const bmp = if (self.diskType(fidx) == 0) icons.PROGRAM else icons.DOCUMENT;
        if (self.view == .icons) {
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                if (ord[p] != fidx) continue;
                const ic = self.fileIconSlot(p, fidx, v);
                self.file_gx = x - ic.x;
                self.file_gy = y - ic.y;
                return;
            }
        }
        self.file_gx = @divTrunc(@as(i16, @intCast(bmp.w)), 2);
        self.file_gy = @divTrunc(@as(i16, @intCast(bmp.h)), 2);
    }

    // A press in a window: single-select the item under it (arming a file drag), or
    // start a rubber-band on empty content.
    fn pressInWindow(self: *Desktop, x: i16, y: i16) void {
        if (self.topFloppy()) |w| switch (self.dirHitAt(w.dir, w.view, x, y)) {
            .file => |a| {
                self.clearSel();
                self.sel_file = a;
                self.file_drag = a; // arm a drag (TRASH = delete, folder = copy)
                self.file_moved = false;
                self.armFileGrab(a, w.view, x, y);
            },
            .folder => |f| {
                self.clearSel();
                self.sel_folder = f;
            },
            .none => {
                self.clearSel();
                if (gui.inRect(w.view.clip, x, y)) { // empty content -> rubber-band
                    self.band = true;
                    self.band_x = x;
                    self.band_y = y;
                }
            },
        };
    }
    // Options > Save Desktop: serialise the desktop (icon cells, open windows,
    // resolution, background) into DESKTOP.INF on the boot disk, the way TOS
    // does. The mounted disk is read-only, so the file is written into the
    // in-memory FAT — it shows up in the FLOPPY window like any other file.
    fn saveDesktop(self: *Desktop) void {
        var open_wins: [gui.MAX_WIN]deskinf.Win = undefined;
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.wm.n) : (i += 1) {
            const id = self.wm.order[i];
            if (!self.wm.wins[id].open or !self.isFloppyWin(id)) continue;
            const w = &self.wm.wins[id];
            open_wins[n] = .{
                .x = w.r.x,
                .y = w.r.y,
                .w = w.r.w,
                .h = w.r.h,
                .text_view = self.view == .text,
                .path = w.title,
            };
            n += 1;
        }
        const drive = &self.items[desk_icons.IC_FLOPPY];
        const trash = &self.items[desk_icons.IC_TRASH];
        const text = deskinf.write(&self.inf_buf, .{
            .medium = self.g.screen_w == 640,
            .bg = .{ self.bg_r, self.bg_g, self.bg_b },
            .drive = .{ .col = drive.cellCol(), .row = drive.cellRow(), .label = drive.label },
            .trash = .{ .col = trash.cellCol(), .row = trash.cellRow(), .label = trash.label },
            .wins = open_wins[0..n],
        });
        if (!self.putFile(deskinf.NAME, @intCast(text.len)))
            self.dlg.alert("Cannot save the desktop.", "The disk directory is full.");
    }

    // Add (or update) a data file in the in-memory FAT. Returns false when the
    // directory is full — the caller must NOT report a save that did not happen.
    fn putFile(self: *Desktop, name: []const u8, size: u32) bool {
        var i: u8 = 0;
        while (i < self.n_disk) : (i += 1) {
            if (std.mem.eql(u8, self.diskName(i), name)) break;
        }
        if (i == self.n_disk) {
            if (self.n_disk >= MAX_FILES) return false;
            self.n_disk += 1;
        }
        const e = @as(usize, i) * FILE_ENT;
        @memset(self.disk_dir[e .. e + FILE_ENT], 0);
        @memcpy(self.disk_dir[e .. e + name.len], name);
        self.disk_dir[e + 16] = 1; // data file
        std.mem.writeInt(u32, self.disk_dir[e + 17 ..][0..4], size, .little);
        std.mem.writeInt(u32, self.disk_dir[e + 21 ..][0..4], stamp.DEFAULT_DATE, .little);
        return true;
    }

    // GEM's default desktop: the drive in the top-left cell, the trash in the
    // bottom one of the same column.
    fn placeDefaultIcons(self: *Desktop) void {
        const rows = @divTrunc(self.g.screen_h - icon_mod.GRID_Y0, icon_mod.CELL_H);
        self.items[desk_icons.IC_FLOPPY].place(0, 0, self.g.screen_w, self.g.screen_h);
        self.items[desk_icons.IC_TRASH].place(0, rows - 1, self.g.screen_w, self.g.screen_h);
    }

    pub fn clearSel(self: *Desktop) void {
        self.sel_file = -1;
        self.sel_folder = -1;
        self.sel_icon = -1;
        self.sel_files = 0;
        self.sel_folders = 0;
    }
    fn fileSelected(self: *const Desktop, a: u8) bool {
        return self.sel_file == @as(i16, @intCast(a)) or (self.sel_files >> @intCast(a)) & 1 != 0;
    }
    fn folderSelected(self: *const Desktop, f: u8) bool {
        return self.sel_folder == @as(i16, @intCast(f)) or (self.sel_folders >> @intCast(f)) & 1 != 0;
    }
    fn bandRect(self: *const Desktop) Rect {
        const px: i16 = @intCast(self.g.px);
        const py: i16 = @intCast(self.g.py);
        const x0 = @min(self.band_x, px);
        const y0 = @min(self.band_y, py);
        return .{ .x = x0, .y = y0, .w = @max(self.band_x, px) - x0, .h = @max(self.band_y, py) - y0 };
    }
    // On marquee release: select every item its rect overlaps.
    fn bandSelect(self: *Desktop) void {
        const br = self.bandRect();
        const w = self.topFloppy() orelse return;
        const nf = self.dirFileCount(w.dir);
        if (w.dir == WIN_ROOT) {
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                const a = ord[p];
                const ir = if (self.view == .icons) self.fileIconSlot(p, a, w.view).rect() else fileRowRect(p, w.view);
                if (overlap(br, ir)) self.sel_files |= @as(u16, 1) << @intCast(a);
            }
        }
        var rank: usize = 0;
        const fc = self.dirFolderCount(w.dir);
        while (rank < fc) : (rank += 1) {
            const fidx = self.dirNthFolder(w.dir, rank);
            const ir = if (self.view == .icons) self.folderIconSlot(nf + rank, fidx, w.view).rect() else fileRowRect(nf + rank, w.view);
            if (overlap(br, ir)) self.sel_folders |= @as(u16, 1) << @intCast(fidx);
        }
    }
    // Resolve a file drag's drop: TRASH = delete, a folder = copy (COPY dialog).
    fn dropFileDrag(self: *Desktop, x: i16, y: i16) void {
        if (self.items[desk_icons.IC_TRASH].hitAt(x, y)) {
            self.trash_target = self.file_drag;
            self.trash.open(0, 1);
            return;
        }
        if (self.topFloppy()) |w| switch (self.dirHitAt(w.dir, w.view, x, y)) {
            .folder => self.copy.openCopy(0, 1), // COPY FOLDERS / ITEMS (cosmetic: disk read-only)
            else => {},
        };
    }

    // New Folder... : create an (auto-named) folder in the top window's directory,
    // or at root if no window is open. Rename waits on the keyboard ABI.
    // File > New Folder: TOS asks for the name first (NEW FOLDER box with an 8.3
    // field); the folder is only created when that dialog is confirmed.
    fn newFolder(self: *Desktop) void {
        if (self.n_folders >= MAX_FOLDERS) {
            self.dlg.alert("Too many folders.", "Delete one and try again.");
            return;
        }
        self.info.openNewFolder();
    }

    // OK on the NEW FOLDER box: create it under the top window's directory with
    // the typed name (empty -> the classic auto-name, so OK is never a dead end).
    fn createFolder(self: *Desktop) void {
        if (self.n_folders >= MAX_FOLDERS) return;
        const dir: i16 = if (self.topFloppy()) |w| w.dir else WIN_ROOT;
        const f = &self.folders[self.n_folders];
        f.* = .{ .parent = dir };
        const typed = self.info.name.text();
        const nm = if (typed.len > 0) blk: {
            const n = @min(typed.len, f.name.len);
            @memcpy(f.name[0..n], typed[0..n]);
            break :blk f.name[0..n];
        } else blk: {
            self.new_seq += 1;
            break :blk std.fmt.bufPrint(&f.name, "NEWDIR{d}", .{self.new_seq}) catch "NEWDIR";
        };
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
        // A directory that has been open before reopens exactly where it was;
        // a new one takes the next cascade slot.
        const saved = self.win_geom[geomSlot(dir)];
        const remembered = saved.w > 0;
        var r = if (remembered) saved else self.next_win;
        // The default width is sized for the TOS text columns, which is as wide as
        // a 320px low-res screen — so pull the window LEFT before narrowing it.
        // Both edges (and the size gadget with them) must open on screen, and the
        // content must stay wide enough for the text view's last column.
        r.w = @min(r.w, self.g.screen_w - 4);
        r.x = @max(0, @min(r.x, self.g.screen_w - r.w - 2));
        const min_w = icon_mod.CELL_W + 2 + gui.SCROLL;
        const min_h = gui.TITLE_H + gui.INFO_H + icon_mod.CELL_H + gui.SCROLL;
        if (self.wm.tryAdd(.{ .r = r, .title = title, .min_w = min_w, .min_h = min_h })) |id| {
            self.win_dir[id] = dir;
            self.sel_icon = -1; // the window, not the icon, is now the selection
            // Freeze the icon grid at the width the window OPENS with; resizing
            // then scrolls the same layout instead of re-flowing it.
            self.win_cols[id] = @max(1, @divTrunc(self.wm.contentRect(id).w, icon_mod.CELL_W));
            self.sel_file = -1;
            self.sel_folder = -1;
            self.startGrow(self.open_src, r); // GEM zoom-box: dotted frame grows icon -> window
            if (remembered) return; // reusing a remembered spot does not consume one
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

    // A window that just closed zooms back DOWN to the desktop icon it came from
    // (the FLOPPY drive), the mirror of the box that grew when it opened.
    fn shrinkClosed(self: *Desktop) void {
        const id = self.wm.takeClosed() orelse return;
        // Remember where this directory's window was before it goes away.
        if (self.isFloppyWin(id)) self.win_geom[geomSlot(self.win_dir[id])] = self.wm.wins[id].r;
        const to = if (self.isFloppyWin(id))
            self.items[desk_icons.IC_FLOPPY].rect()
        else
            Rect{ .x = self.wm.wins[id].r.x, .y = self.wm.wins[id].r.y, .w = 0, .h = 0 };
        self.startGrow(self.wm.wins[id].r, to);
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
            if (self.isFloppyWin(id)) self.updateChrome(id); // info line + scroll state
            const v = if (self.isFloppyWin(id)) self.viewOf(id) else undefined;
            _ = self.wm.drawChrome(g, id, id == self.wm.topOpen());
            if (self.isFloppyWin(id)) self.drawDir(g, self.win_dir[id], v);
        }
        if (self.wm.takeZoom()) |z| self.startGrow(z.from, z.to); // full-box zoom
        self.shrinkClosed(); // a window just closed -> zoom-box back to its icon
        self.wm.drawGhost(g); // pending window move / resize outline
        // Drag ghost for a file dragged out of a window. Like a desktop icon it
        // hangs off the pointer at the offset it was GRABBED at, so the outline
        // sits over the icon instead of jumping left of the cursor.
        if (self.file_drag >= 0 and self.file_moved) {
            const bmp = if (self.diskType(@intCast(self.file_drag)) == 0) icons.PROGRAM else icons.DOCUMENT;
            dragGhost(g, @intCast(@as(i32, g.px) - self.file_gx), @intCast(@as(i32, g.py) - self.file_gy), bmp);
        }
        // The same ghost for a DESKTOP icon being dragged: the icon itself stays
        // where it is (drawn above) until the drop.
        if (self.drag) |di| {
            if (self.moved) {
                const it = &self.items[di];
                const p = desk_icons.ghostAt(self, g);
                dragGhost(g, p.x, p.y, it.bmp);
            }
        }
        self.drawGrow(g); // window-open zoom-box
        if (self.band) dottedFrame(g, self.bandRect(), gui.BLACK); // rubber-band marquee
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

    // Refresh a directory window's chrome for THIS frame: the GEM info line, how
    // much of each scroll track its slider fills, and how far it may scroll. All
    // depend on the window's current size, so they are recomputed every frame
    // rather than at open time — but the icon GRID is not, which is why resizing
    // scrolls the icons instead of re-wrapping them (see View).
    fn updateChrome(self: *Desktop, id: u8) void {
        const dir = self.win_dir[id];
        const n = self.dirFileCount(dir) + self.dirFolderCount(dir);
        var used: u32 = 0;
        if (dir == WIN_ROOT) {
            var k: u8 = 0;
            while (k < self.n_disk) : (k += 1) used += self.diskSize(k);
        }
        const w = &self.wm.wins[id];
        w.info = std.fmt.bufPrint(&self.win_info[id], "{d} bytes used in {d} items.", .{ used, n }) catch "";
        // The info line changes topBarsH, so measure the content AFTER setting it.
        const c = self.wm.contentRect(id);
        const shown = @divTrunc(c.h, self.vStep());
        const rows = self.contentRows(id, n);
        w.vslide = permille(shown, rows);
        w.vmax = @max(0, rows - shown);
        w.vscroll = @max(0, @min(w.vscroll, w.vmax));

        const width = self.contentWidth(id, n);
        w.hslide = permille(c.w, width);
        const hs = self.hStep();
        w.hmax = @max(0, @divTrunc(width - c.w + hs - 1, hs));
        w.hscroll = @max(0, @min(w.hscroll, w.hmax));
    }

    // Rows the window's content occupies — icon view wraps into the window's
    // FIXED column count, text view is one row per item.
    fn contentRows(self: *const Desktop, id: u8, n: usize) i16 {
        const items: i16 = @intCast(n);
        if (self.view != .icons) return items;
        const cols = self.win_cols[id];
        return @divTrunc(items + cols - 1, cols); // ceil
    }
    // Pixels the content is wide: the OCCUPIED part of the frozen icon grid (a
    // half-empty grid is not something to scroll across), or the fixed TOS column
    // layout of the text view.
    fn contentWidth(self: *const Desktop, id: u8, n: usize) i16 {
        if (n == 0) return 0;
        if (self.view != .icons) return TOS_COLS * 8;
        return @min(self.win_cols[id], @as(i16, @intCast(n))) * icon_mod.CELL_W;
    }

    // What fraction of `total` is visible, in per mille, clamped to a full track.
    fn permille(visible: i16, total: i16) i16 {
        if (total <= 0 or visible >= total) return 1000;
        return @intCast(@max(1, @divTrunc(@as(i32, visible) * 1000, @as(i32, total))));
    }

    // A window's directory: disk files (root only) then folders, in view + sort order.
    fn drawDir(self: *Desktop, g: *gui.Gui, dir: i16, v: View) void {
        const nf = self.dirFileCount(dir);
        if (dir == WIN_ROOT) {
            const ord = self.fileOrder();
            var p: usize = 0;
            while (p < self.n_disk) : (p += 1) {
                const a = ord[p];
                if (self.view == .icons) {
                    var ic = self.fileIconSlot(p, a, v);
                    ic.draw(g, self.fileSelected(a));
                } else self.drawFileRow(g, p, a, v);
            }
        }
        const fc = self.dirFolderCount(dir);
        var rank: usize = 0;
        while (rank < fc) : (rank += 1) {
            const fidx = self.dirNthFolder(dir, rank);
            const sel = self.folderSelected(fidx);
            if (self.view == .icons) {
                var ic = self.folderIconSlot(nf + rank, fidx, v);
                ic.draw(g, sel);
            } else self.drawFolderRow(g, nf + rank, fidx, v, sel);
        }
    }

    fn drawFolderRow(self: *Desktop, g: *gui.Gui, slot: usize, fidx: u8, v: View, sel: bool) void {
        const r = fileRowRect(slot, v);
        if (!rowVisible(r, v)) return;
        if (sel) g.rect(r, gui.BLACK);
        const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
        const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
        g.text(self.folderName(fidx), v.clip.x + 4, r.y + 1, ink, paper);
        g.text("<DIR>", v.clip.x + v.clip.w - 6 * 8 - 2, r.y + 1, ink, paper);
    }

    // Is a text row inside the window? Rows scrolled off the top or bottom are
    // simply not drawn (the row text itself is not pixel-clipped).
    fn rowVisible(r: Rect, v: View) bool {
        return r.y >= v.clip.y and r.y + TROW_H <= v.clip.y + v.clip.h;
    }

    // One text-view row, TOS columns: NAME(8) EXT(3) SIZE DATE(MM-DD-YY) TIME.
    // Columns sit at fixed cell offsets; each is drawn only if it fits the window,
    // so a narrow window drops the right columns instead of overflowing.
    fn drawFileRow(self: *Desktop, g: *gui.Gui, slot: usize, fidx: u8, v: View) void {
        const r = fileRowRect(slot, v);
        if (!rowVisible(r, v)) return;
        const sel = self.fileSelected(fidx);
        if (sel) g.rect(r, gui.BLACK);
        const ink: u8 = if (sel) gui.WHITE else gui.BLACK;
        const paper: u8 = if (sel) gui.BLACK else gui.WHITE;
        const y = r.y + 1;
        const cx = v.org.x + 4; // column 0, scrolled

        const name = self.diskName(fidx);
        var base = name;
        var ext: []const u8 = "";
        if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
            base = name[0..dot];
            ext = name[dot + 1 ..];
        }
        var sb: [12]u8 = undefined;
        var db: [16]u8 = undefined;
        const size = fmtSize(&sb, self.diskSize(fidx));
        textCol(g, v, base[0..@min(base.len, 8)], cx, y, ink, paper); // NAME (8)
        textCol(g, v, ext[0..@min(ext.len, 3)], cx + 9 * 8, y, ink, paper); // EXT (3)
        textCol(g, v, size, cx + 20 * 8 - @as(i16, @intCast(size.len)) * 8, y, ink, paper); // SIZE, right-aligned
        textCol(g, v, stamp.date(&db, self.diskDate(fidx)), cx + 22 * 8, y, ink, paper); // DATE
        textCol(g, v, stamp.DEFAULT_TIME, cx + 31 * 8, y, ink, paper); // TIME (host FAT has none)
    }

    // One text-view column, clipped to the window's content span.
    fn textCol(g: *gui.Gui, v: View, s: []const u8, x: i16, y: i16, ink: u8, paper: u8) void {
        g.textIn(s, x, y, ink, paper, v.clip.x, v.clip.x + v.clip.w);
    }

    // Menu bar + modal alert + Set Preferences, drawn last (over everything).
    // Build the desktop menus for THIS frame so ticks (view/sort) and disabled
    // states (no selection, Format) reflect live desktop state.
    fn buildMenus(self: *Desktop, buf: *MenuBuf) [4]gui.Menu {
        const has_sel = self.sel_icon >= 0 or self.sel_file >= 0 or self.sel_folder >= 0;
        // New Folder / Close / Close Window act ON a window, so they need one to
        // be the current thing: no open window, or a DESKTOP icon selected (the
        // selection has moved off the window), greys all three.
        const no_win = self.wm.topOpen() == null or self.sel_icon >= 0;
        buf.desk = .{.{ .label = "Desktop Info..." }};
        buf.file = .{
            .{ .label = "Open", .disabled = !has_sel },
            .{ .label = "Show Info...", .disabled = !has_sel },
            .{ .label = "----------" },
            .{ .label = "New Folder...", .disabled = no_win },
            .{ .label = "Close", .disabled = no_win },
            .{ .label = "Close Window", .disabled = no_win },
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
        buf.opt = .{ .{ .label = "Set Preferences" }, .{ .label = "----------" }, .{ .label = "Save Desktop" } };
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
        switch (self.info.process(g)) { // Show Info... + NEW FOLDER share the box
            .ok => if (self.info.kind == .new_folder) self.createFolder() else self.applyRename(),
            else => {},
        }
        _ = self.copy.process(g); // COPY FOLDERS / ITEMS (cosmetic; disk is read-only)
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
                3 => self.newFolder(), // New Folder... -> the NEW FOLDER name dialog
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
            MENU_OPTIONS => switch (p.item) {
                0 => self.prefs.open(self.bg_r, self.bg_g, self.bg_b, self.g.screen_w == 640),
                2 => self.saveDesktop(), // Save Desktop -> A:\DESKTOP.INF
                else => {},
            },
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
            self.launch_file = self.sel_file;
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
        const nm = self.info.name.text();
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
        const id = self.wm.topOpen() orelse return;
        self.wm.close(id);
        self.sel_file = -1;
    }

    // Directional input from the host (0=up 1=down 2=left 3=right). The desktop
    // only uses left/right, and only to walk the caret in the name field of an
    // open INFORMATION / NEW FOLDER box.
    pub fn input(self: *Desktop, dir: u32) void {
        if (!self.info.active) return;
        switch (dir) {
            2 => self.info.moveCaret(-1),
            3 => self.info.moveCaret(1),
            else => {},
        }
    }

    pub fn requestOpenAt(self: *Desktop, x: i32, y: i32) void {
        desk_icons.requestOpenAt(self, x, y);
    }
};

// A single pixel, clipped to the visible area (dotted overlays can run to an edge).
fn plot(g: *gui.Gui, x: i16, y: i16, c: u8) void {
    g.plot(x, y, c);
}
fn overlap(a: gui.Rect, b: gui.Rect) bool {
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y;
}
// A GEM drag ghost: ONE dotted contour around the whole icon+label unit — the
// narrow icon box sitting on the wider label field traces a single "hat"
// (inverse-T) outline, not two stacked rectangles. The label box is the full
// fixed-width label FIELD, so the ghost is the exact footprint the icon takes
// once dropped.
fn dragGhost(g: *gui.Gui, x: i16, y: i16, bmp: icons.Icon) void {
    const art = icon_mod.artBox(bmp);
    const ax = x + art.x;
    const iw = art.w;
    const lw = icon_mod.LABEL_W;
    const lh = icon_mod.LABEL_H;
    const lx = ax + @divTrunc(iw - lw, 2);
    const top = y + art.y;
    const shoulder = top + art.h; // the row where the icon box meets the label field
    const c = gui.BLACK;
    dotH(g, ax, ax + iw, top, c); // icon top
    dotV(g, top, shoulder, ax, c); // icon left
    dotV(g, top, shoulder, ax + iw - 1, c); // icon right
    dotH(g, lx, ax, shoulder, c); // left shoulder
    dotH(g, ax + iw, lx + lw, shoulder, c); // right shoulder
    dotV(g, shoulder, shoulder + lh, lx, c); // label left
    dotV(g, shoulder, shoulder + lh, lx + lw - 1, c); // label right
    dotH(g, lx, lx + lw, shoulder + lh - 1, c); // label bottom
}

// Dotted segments (every other pixel), the pieces a GEM outline is built from.
fn dotH(g: *gui.Gui, x0: i16, x1: i16, y: i16, c: u8) void {
    var x: i16 = x0;
    while (x < x1) : (x += 2) plot(g, x, y, c);
}
fn dotV(g: *gui.Gui, y0: i16, y1: i16, x: i16, c: u8) void {
    var y: i16 = y0;
    while (y < y1) : (y += 2) plot(g, x, y, c);
}

// A GEM dotted rectangle outline — zoom-box + drag ghost + marquee.
fn dottedFrame(g: *gui.Gui, r: gui.Rect, c: u8) void {
    g.dotted(r, c);
}

fn fmtSize(buf: []u8, n: u32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{n}) catch "?";
}
