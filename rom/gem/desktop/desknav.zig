// --------------------------------------------------------------------------
// Walking the folder tree INSIDE a directory window, as TOS 1.00's desktop does (Matt on the
// board, 6 Nov 2026: C:\, PICTURES, then PLASMA opened a third window). On TOS a window is a
// drive's: opening a folder in it shows that folder in the SAME window (its title becomes the
// longer path), the close box goes back up one level and only closes the window at the drive's
// root, and File > Close does what the close box does while File > Close Window closes it
// outright. A new window only comes from a drive icon on the desktop (desk_icons.openIcon).
// --------------------------------------------------------------------------
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const deskwin = @import("deskwin.zig");
const deskdrive = @import("deskdrive.zig");
const Desktop = dt.Desktop;

/// Open folder `fidx` of the focused drive: in the top directory window, which is the one it
/// was double-clicked or selected in (a new window only when none is open).
pub fn enterFolder(d: *Desktop, fidx: u8) void {
    const w = deskwin.topFloppy(d) orelse return deskwin.openFolderWindow(d, fidx);
    show(d, w.id, @intCast(fidx));
}

/// File > Close: the top directory window goes up one level, or closes at its drive's root.
pub fn closeFolder(d: *Desktop) void {
    const w = deskwin.topFloppy(d) orelse return deskwin.closeTopWindow(d);
    if (d.wm.topOpen() != w.id or w.dir == dirmodel.ROOT) return deskwin.closeTopWindow(d);
    up(d, w.id);
}

/// Right after the window manager took the frame's press: a close box on a FOLDER's window
/// goes up a level instead (the window stays open, raised); at the root the close stands and
/// deskwin.shrinkClosed zooms it back to its drive icon. Then the top window's drive is in
/// focus (KOS F5): the press may have raised another one.
pub fn afterWm(d: *Desktop) void {
    if (d.wm.closed) |id| {
        if (deskwin.isFloppyWin(d, id) and d.win_dir[id] != dirmodel.ROOT) {
            d.wm.closed = null;
            d.wm.wins[id].open = true;
            d.wm.toFront(id);
            up(d, id);
        }
    }
    deskdrive.focusTop(d);
}

fn up(d: *Desktop, id: u8) void {
    deskdrive.use(d, d.drv.win[id]);
    show(d, id, d.dir.folders[@intCast(d.win_dir[id])].parent);
}

/// Window `id` shows directory `dir` of its drive (d.dir): its path as the title, scrolled to
/// the top, nothing selected. Its rect and frozen icon grid stay: it is the same window.
fn show(d: *Desktop, id: u8, dir: i16) void {
    d.win_dir[id] = dir;
    const w = &d.wm.wins[id];
    w.title = if (dir == dirmodel.ROOT) rootTitle(d) else blk: {
        const f = &d.dir.folders[@intCast(dir)];
        break :blk f.title[0..f.tlen];
    };
    w.vscroll = 0;
    w.hscroll = 0;
    d.sel_icon = -1;
    d.sel_file = -1;
    d.sel_folder = -1;
    d.sel_files = 0;
    d.sel_folders = 0;
}

fn rootTitle(d: *const Desktop) []const u8 {
    return if (d.drv.cur == deskdrive.C) "C:\\" else "A:\\";
}
