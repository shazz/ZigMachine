// --------------------------------------------------------------------------
// The desktop's menu bar and the dialogs it opens. Menus are rebuilt every
// frame so ticks (view/sort) and greyed items track live desktop state; the
// dialogs run after it, drawn last, over everything.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const deskwin = @import("deskwin.zig");
const deskops = @import("deskops.zig");
const Desktop = dt.Desktop;
const Action = dt.Action;

const MENU_DESK = 0;
const MENU_FILE = 1;
const MENU_VIEW = 2;
const MENU_OPTIONS = 3;

// Stack storage for the per-frame menu items (their slices are handed to the
// menu bar within the same frame).
const MenuBuf = struct {
    desk: [1]gui.MenuItem = undefined,
    file: [8]gui.MenuItem = undefined,
    view: [7]gui.MenuItem = undefined,
    opt: [3]gui.MenuItem = undefined,
};

pub fn runDialogs(d: *Desktop, g: *gui.Gui, action: *Action) void {
    var buf: MenuBuf = undefined;
    const menus = buildMenus(d, &buf);
    // Only a modal dialog locks the bar. (Don't lock on overWindow: a drop-down
    // that overlaps a window must still accept item clicks — the drop-on-hover
    // guard already blocks menus opening mid window-drag.)
    if (d.menubar.process(g, &menus, g.screen_w, d.isModal())) |p| menuPick(d, p, action);
    _ = d.dlg.process(g);
    _ = d.about.process(g); // Desktop Info... (modal while active)
    switch (d.trash.process(g)) { // DELETE FILE(S) confirm
        .ok => {
            if (d.trash_target >= 0) deskops.removeFile(d, @intCast(d.trash_target));
            d.trash_target = -1;
        },
        .cancel => d.trash_target = -1,
        .none => {},
    }
    switch (d.info.process(g)) { // Show Info... + NEW FOLDER share the box
        .ok => if (d.info.kind == .new_folder) deskops.createFolder(d) else deskops.applyRename(d),
        else => {},
    }
    _ = d.copy.process(g); // COPY FOLDERS / ITEMS (cosmetic; disk is read-only)
    if (d.prefs.active) runPrefs(d, g, action);
}

// Set Preferences (live-previews the background colour while open).
fn runPrefs(d: *Desktop, g: *gui.Gui, action: *Action) void {
    switch (d.prefs.process(g)) {
        .ok => {
            d.bg_r = d.prefs.cr;
            d.bg_g = d.prefs.cg;
            d.bg_b = d.prefs.cb;
            action.* = if (d.prefs.medium) .res_medium else .res_low;
            d.prefs.active = false;
        },
        .cancel => {
            d.applyBg(); // restore the saved colour (process previewed a new one)
            d.prefs.active = false;
        },
        .none => {},
    }
}

fn buildMenus(d: *Desktop, buf: *MenuBuf) [4]gui.Menu {
    const has_sel = d.sel_icon >= 0 or d.sel_file >= 0 or d.sel_folder >= 0;
    // New Folder / Close / Close Window act ON a window, so they need one to
    // be the current thing: no open window, or a DESKTOP icon selected (the
    // selection has moved off the window), greys all three.
    const no_win = d.wm.topOpen() == null or d.sel_icon >= 0;
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
        .{ .label = "Show as Icons", .tick = d.view == .icons },
        .{ .label = "Show as Text", .tick = d.view == .text },
        .{ .label = "----------" },
        .{ .label = "Sort by Name", .tick = d.sort == .name },
        .{ .label = "Sort by Date", .tick = d.sort == .date },
        .{ .label = "Sort by Size", .tick = d.sort == .size },
        .{ .label = "Sort by Type", .tick = d.sort == .type },
    };
    buf.opt = .{ .{ .label = "Set Preferences" }, .{ .label = "----------" }, .{ .label = "Save Desktop" } };
    return .{
        .{ .title = "Desk", .items = &buf.desk },
        .{ .title = "File", .items = &buf.file },
        .{ .title = "View", .items = &buf.view },
        .{ .title = "Options", .items = &buf.opt },
    };
}

fn menuPick(d: *Desktop, p: gui.MenuPick, action: *Action) void {
    switch (p.menu) {
        MENU_DESK => d.about.open(), // Desktop Info...
        MENU_FILE => switch (p.item) {
            0 => deskops.openSelection(d, action), // Open
            1 => deskops.showInfo(d), // Show Info...
            3 => deskops.newFolder(d), // New Folder... -> the NEW FOLDER name dialog
            4, 5 => deskwin.closeTopWindow(d), // Close / Close Window
            else => {}, // separators + Format... (disabled)
        },
        MENU_VIEW => switch (p.item) {
            0 => d.view = .icons,
            1 => d.view = .text,
            3 => d.sort = .name,
            4 => d.sort = .date,
            5 => d.sort = .size,
            6 => d.sort = .type,
            else => {}, // separator
        },
        MENU_OPTIONS => switch (p.item) {
            0 => d.prefs.open(d.bg_r, d.bg_g, d.bg_b, d.g.screen_w == 640),
            2 => deskops.saveDesktop(d), // Save Desktop -> A:\DESKTOP.INF
            else => {},
        },
        else => {},
    }
}
