// --------------------------------------------------------------------------
// ZigGEM Desktop — the GEM-style desktop shell. This file owns the Desktop
// STATE and the per-frame render loop; the behaviour sits beside it as free
// functions over *Desktop:
//   dirmodel.zig   the disk FAT + in-RAM folders (pure, natively tested)
//   dirview.zig    a directory drawn in a window: icon/text layout, hit-tests
//   deskwin.zig    directory windows: open/close, remembered geometry, scrolling
//   desksel.zig    pointer routing + selection: press, rubber-band, file drag
//   deskdraw.zig   the scene: desktop, windows, drag ghosts, zoom-box
//   deskmenu.zig   the menu bar and the dialogs it opens
//   deskops.zig    the File / Options commands those menus run
//   desk_icons.zig desktop icons: select / drag / open
// --------------------------------------------------------------------------
const zsrc = @import("zigos");
const gui = @import("../gui.zig");
const icons = @import("../gem_icons.zig");
const prefs = @import("prefs.zig");
const about_mod = @import("about.zig");
const trash_mod = @import("trash.zig");
const info_mod = @import("info.zig");
const icon_mod = @import("icon.zig");
const deskinf = @import("deskinf.zig");
const dirmodel = @import("dirmodel.zig");
const desk_icons = @import("desk_icons.zig");
const deskwin = @import("deskwin.zig");
const desksel = @import("desksel.zig");
const deskdraw = @import("deskdraw.zig");
const deskmenu = @import("deskmenu.zig");

const Rect = gui.Rect;
const Icon = icon_mod.Icon;
const NO_RECT: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

pub const Action = enum { none, launch, res_low, res_medium };
pub const ViewMode = enum { icons, text }; // View menu: FLOPPY contents as icons or text
pub const SortKey = dirmodel.SortKey;
pub const MAX_FILES = dirmodel.MAX_FILES;
pub const FILE_ENT = dirmodel.FILE_ENT;

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
    dir: dirmodel.DirModel = .{}, // the mounted disk's FAT (host-filled) + in-RAM folders
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
    file_gx: i16 = 0, // grab offset inside the dragged file's icon (see desksel.armFileGrab)
    file_gy: i16 = 0,
    trash_target: i16 = -1, // file awaiting the DELETE FILE(S) confirm
    bg_r: u8 = 1, // desktop background colour (Prefs); GEM default here is a teal
    bg_g: u8 = 160,
    bg_b: u8 = 164,
    view: ViewMode = .icons,
    sort: SortKey = .name, // View menu: sort order for FLOPPY contents
    win_dir: [gui.MAX_WIN]i16 = [_]i16{deskwin.WIN_NONE} ** gui.MAX_WIN, // per-window directory
    win_cols: [gui.MAX_WIN]i16 = [_]i16{1} ** gui.MAX_WIN, // icon grid width, fixed at open
    inf_buf: [deskinf.MAX_BYTES]u8 = [_]u8{0} ** deskinf.MAX_BYTES, // DESKTOP.INF text
    // Each DIRECTORY remembers where its window was and how big, so closing and
    // reopening it puts it back rather than restarting the cascade. Indexed by
    // dir + 1 (the root is -1); w == 0 means "never opened".
    win_geom: [dirmodel.MAX_FOLDERS + 1]Rect = [_]Rect{NO_RECT} ** (dirmodel.MAX_FOLDERS + 1),
    // Backing store for each window's GEM info line ("N bytes used in M items.").
    // Window.info is a slice, and Desktop is static, so it may point in here.
    win_info: [gui.MAX_WIN][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** gui.MAX_WIN,
    sel_folder: i16 = -1, // selected folder in the top window, -1 = none
    sel_files: u16 = 0, // rubber-band multi-select: bit per file
    sel_folders: u16 = 0, // rubber-band multi-select: bit per folder
    band: bool = false, // rubber-band marquee in progress
    band_x: i16 = 0,
    band_y: i16 = 0,
    grow_a: Rect = NO_RECT, // zoom-box: from
    grow_b: Rect = NO_RECT, // zoom-box: to
    grow_t: u8 = 0, // zoom-box frames remaining (0 = idle)
    open_src: Rect = NO_RECT, // source rect for the next window open

    pub fn init(self: *Desktop, os: *zsrc.ZigOS, fb: *zsrc.LogicalFB, blit: *zsrc.Blitter) void {
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
        self.dir.n_folders = 0; // the disk's FAT is the host's; folders are ours
        self.dir.new_seq = 0;
        self.win_dir = [_]i16{deskwin.WIN_NONE} ** gui.MAX_WIN;
        desk_icons.placeDefaultIcons(self);
        self.applyBg(); // paint the desktop palette with the configured background
    }

    pub fn applyBg(self: *Desktop) void {
        self.g.fb.setPaletteEntry(gui.DESK, .{ .r = self.bg_r, .g = self.bg_g, .b = self.bg_b, .a = 255 });
    }

    // An open dialog owns all input: the icons, the windows AND the menu bar.
    // ONE list, read by both render and runDialogs — two copies once drifted and
    // left the menu bar live under the COPY box.
    pub fn isModal(self: *const Desktop) bool {
        return self.dlg.active or self.prefs.active or self.about.active or
            self.trash.active or self.info.active or self.copy.active;
    }

    // Draw the desktop (res-adaptive) + windows; handle icon drag/click; return action.
    pub fn render(self: *Desktop) Action {
        const g = &self.g;
        var action: Action = .none;
        const modal = self.isModal();
        const menu_open = self.menubar.open >= 0;
        // Windows sit above icons and take input first; a press the windows (or
        // an open drop-down menu) consumed never reaches the icons.
        const consumed = !modal and self.wm.handle(g);
        const busy = modal or consumed or menu_open or self.wm.drag != null or self.wm.resize != null or deskwin.overWindow(self);
        // A native double-click (routed via requestOpenAt) opens/launches now.
        if (self.pending_open >= 0) {
            desk_icons.openIcon(self, @intCast(self.pending_open), &action);
            self.pending_open = -1;
        }
        desksel.routePointer(self, g, modal, busy);
        deskdraw.drawScene(self, g);
        deskmenu.runDialogs(self, g, &action);
        if (self.launch_req) { // a program file in a FLOPPY window was double-clicked
            self.launch_req = false;
            action = .launch;
        }
        return action;
    }

    // The program a .launch action refers to. Empty when the disk holds none, so
    // the caller can report "no program on this disk" instead of booting nothing.
    pub fn launchName(self: *const Desktop) []const u8 {
        return self.dir.launchName(self.launch_file);
    }

    pub fn setPointer(self: *Desktop, x: i32, y: i32, buttons: u32) void {
        self.g.setPointer(x, y, buttons);
    }
    pub fn requestOpenAt(self: *Desktop, x: i32, y: i32) void {
        desk_icons.requestOpenAt(self, x, y);
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

    // Character keyboard: feeds the Show Info rename field while it's open.
    pub fn key(self: *Desktop, cp: u32) void {
        if (self.info.active) self.info.key(cp);
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
};
