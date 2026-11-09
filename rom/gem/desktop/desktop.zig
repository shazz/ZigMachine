// --------------------------------------------------------------------------
// ZigGEM Desktop — the desktop shell: the Desktop STATE and the per-frame loop;
// the behaviour sits beside it as free functions over *Desktop:
//   dirmodel.zig   the disk FAT + in-RAM folders (pure, natively tested)
//   dirview.zig    a directory drawn in a window: icon/text layout, hit-tests
//   deskwin.zig    directory windows: open/close, geometry, scrolling; desknav.zig folders in them
//   desksel.zig    pointer routing + selection: press, rubber-band, file drag
//   deskdraw.zig   the scene: desktop, windows, drag ghosts, zoom-box
//   deskmenu.zig   the menu bar and the dialogs it opens
//   deskops.zig    the File / Options commands those menus run
//   desk_icons.zig desktop icons: select / drag / open; deskdrive.zig A: and C: (KOS)
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
const deskdrive = @import("deskdrive.zig");
const desk_icons = @import("desk_icons.zig");
const deskwin = @import("deskwin.zig");
const desknav = @import("desknav.zig");
const desksel = @import("desksel.zig");
const deskdraw = @import("deskdraw.zig");
const deskmenu = @import("deskmenu.zig");
const deskdirty = @import("deskdirty.zig");
const deskmode = @import("deskmode.zig");
const deskeng = @import("eng/engine.zig");

const Rect = gui.Rect;
const Icon = icon_mod.Icon;
const NO_RECT: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

pub const Action = enum { none, launch, res_low, res_medium, res_desk };
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
    // No app icon: GEM is generic. A mounted app-disk (e.g. ST Replay) turns the FLOPPY icon into
    // that app's launcher (disk_app + desk_icons.openIcon); init() places them (placeDefaultIcons).
    items: [3]Icon = .{
        .{ .x = 0, .y = 0, .bmp = icons.FLOPPY, .label = "FLOPPY DISK", .is_app = false },
        .{ .x = 0, .y = 0, .bmp = icons.TRASH, .label = "TRASH", .is_app = false },
        .{ .x = 0, .y = 0, .bmp = icons.HARD, .label = "SD CARD", .is_app = false }, // KOS's C:, shown once it mounts
    },
    disk_app: bool = false, // a disk is in drive A (host sets it): its icon shows only then (KOS)
    drives: [2]dirmodel.DirModel = .{ .{}, .{ .letter = 'C' } }, // A: (host-filled FAT + in-RAM folders), C: (KOS F5)
    dir: *dirmodel.DirModel = undefined, // drives[drv.cur], the drive in focus (deskdrive.zig): init() sets it
    drv: deskdrive.State = .{},
    dirty: deskdirty.State = .{}, // repaint only what changed (deskdirty.zig)
    mode: deskmode.State = .{}, // the screen modes: desk capability, DESKTOP.INF read back (deskmode.zig)
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
    sel_files: u32 = 0, // rubber-band multi-select: bit per file (MAX_FILES = 32)
    sel_folders: u16 = 0, // rubber-band multi-select: bit per folder
    band: bool = false, // rubber-band marquee in progress
    band_x: i16 = 0,
    band_y: i16 = 0,
    grow_a: Rect = NO_RECT, // zoom-box: from
    grow_b: Rect = NO_RECT, // zoom-box: to
    grow_t: u8 = 0, // zoom-box frames remaining (0 = idle)
    open_src: Rect = NO_RECT, // source rect for the next window open
    grow_drawn: ?Rect = null, // the zoom-box frame drawn this frame (the GEM 5 engine's overlay)
    eng: ?*deskeng.Engine = null, // GEM 5's engine, when the ROM handed one (eng/engine.zig)
    eng_dlg: ?Rect = null, // engine frame: the clip the dialogs paint in (null: the old path)
    eng_rec: ?Rect = null, // engine frame: the box the dialogs painted (deskmenu.runDialogs)

    pub fn init(self: *Desktop, os: *zsrc.ZigOS, fb: *zsrc.LogicalFB, blit: *zsrc.Blitter) void {
        self.g = .{ .os = os, .fb = fb, .blit = blit, .screen = gui.Screen.of(.medium) };
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
        deskdrive.reset(self); // the disk's FAT is the host's; folders are ours
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
        if (!deskdirty.mustDraw(self)) return .none; // nothing changed: the plane holds this frame
        defer deskdirty.drew(self);
        if (self.eng) |e| if (e.active(self)) return e.frame(self); // GEM 5: the same step, painted from trees
        return self.step();
    }

    // One frame of the desktop: input, logic and (immediate-mode) drawing in one pass.
    pub fn step(self: *Desktop) Action {
        const g = &self.g;
        var action: Action = .none;
        const modal = self.isModal();
        const menu_open = self.menubar.open >= 0;
        // Windows take input before icons: a press they (or an open menu) consumed never reaches them.
        const consumed = !modal and self.wm.handle(g);
        desknav.afterWm(self); // a folder window's close box goes up a level (TOS); the top window's drive in focus
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
        deskdraw.drawPointer(g); // last: over the menus and the dialogs (the desk only)
        return action;
    }

    // The program a .launch action refers to; empty when the disk holds none (no boot of nothing).
    pub fn launchName(self: *const Desktop) []const u8 {
        return self.drives[0].launchName(self.launch_file); // only drive A launches: C: is data (KOS F5)
    }

    pub fn setPointer(self: *Desktop, x: i32, y: i32, buttons: u32) void {
        if (x != self.g.px or y != self.g.py or (buttons != 0) != self.g.down) deskdirty.touch(self);
        self.g.setPointer(x, y, buttons);
    }
    pub fn requestOpenAt(self: *Desktop, x: i32, y: i32) void {
        deskdirty.touch(self);
        desk_icons.requestOpenAt(self, x, y);
    }
    pub fn beginFrame(self: *Desktop) void {
        self.g.beginFrame();
    }
    pub fn endFrame(self: *Desktop) void {
        self.g.endFrame();
    }
    pub fn setScreen(self: *Desktop, s: gui.Screen) void {
        deskmode.setScreen(self, s); // the screen was re-bound (deskSetScreen): every pixel moved
    }

    // Character keyboard: feeds the Show Info rename field while it's open.
    pub fn key(self: *Desktop, cp: u32) void {
        deskdirty.touch(self);
        if (self.info.active) self.info.key(cp);
    }
    // Directional input from the host (0=up 1=down 2=left 3=right). The desktop
    // only uses left/right, and only to walk the caret in the name field of an
    // open INFORMATION / NEW FOLDER box.
    pub fn input(self: *Desktop, dir: u32) void {
        deskdirty.touch(self);
        if (!self.info.active) return;
        switch (dir) {
            2 => self.info.moveCaret(-1),
            3 => self.info.moveCaret(1),
            else => {},
        }
    }
};
