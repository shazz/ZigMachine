// --------------------------------------------------------------------------
// The commands behind the File and Options menus and their dialogs' OK
// buttons: open, show info, new folder, rename, delete, Save Desktop. They act
// on the selection and the directory model; the menus only route to them.
// --------------------------------------------------------------------------
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const deskwin = @import("deskwin.zig");
const deskinf = @import("deskinf.zig");
const desk_icons = @import("desk_icons.zig");
const Desktop = dt.Desktop;
const Action = dt.Action;

// Open the current selection: a folder opens its window, a desktop icon its
// window/app, a program file launches (GEM: no-op with nothing selected).
pub fn openSelection(d: *Desktop, action: *Action) void {
    if (d.sel_folder >= 0) {
        deskwin.openFolderWindow(d, @intCast(d.sel_folder));
    } else if (d.sel_icon >= 0) {
        desk_icons.openIcon(d, @intCast(d.sel_icon), action);
    } else if (d.sel_file >= 0 and d.dir.kind(@intCast(d.sel_file)) == 0) {
        d.launch_file = d.sel_file;
        d.launch_req = true;
    }
}

// Show Info... for the current selection. The name field is editable (rename).
pub fn showInfo(d: *Desktop) void {
    if (d.sel_folder >= 0) {
        d.info.openFile(d.dir.folderName(@intCast(d.sel_folder)), 0, 0, true);
    } else if (d.sel_file >= 0) {
        const f: u8 = @intCast(d.sel_file);
        d.info.openFile(d.dir.name(f), d.dir.size(f), d.dir.date(f), false);
    } else if (d.sel_icon == desk_icons.IC_FLOPPY) {
        const used = d.dir.usedBytes(); // DISK INFORMATION for drive A: (ref: real TOS)
        const cap: u32 = 726528; // a 3.5" DS floppy
        d.info.openDisk(@intCast(d.dir.folderCount(dirmodel.ROOT)), d.dir.n_disk, used, if (cap > used) cap - used else 0);
    } else if (d.sel_icon >= 0) {
        d.dlg.alert(d.items[@intCast(d.sel_icon)].label, "Kind: Desktop icon");
    }
}

// File > New Folder: TOS asks for the name first (NEW FOLDER box with an 8.3
// field); the folder is only created when that dialog is confirmed.
pub fn newFolder(d: *Desktop) void {
    if (d.dir.n_folders >= dirmodel.MAX_FOLDERS) {
        d.dlg.alert("Too many folders.", "Delete one and try again.");
        return;
    }
    d.info.openNewFolder();
}

// OK on the NEW FOLDER box: create it under the top window's directory.
pub fn createFolder(d: *Desktop) void {
    const parent: i16 = if (deskwin.topFloppy(d)) |w| w.dir else dirmodel.ROOT;
    d.dir.addFolder(parent, d.info.name.text());
}

// OK on Show Info...: apply the (keyboard-edited) name to the selection.
pub fn applyRename(d: *Desktop) void {
    const nm = d.info.name.text();
    if (nm.len == 0) return;
    if (d.sel_folder >= 0) {
        d.dir.renameFolder(@intCast(d.sel_folder), nm);
    } else if (d.sel_file >= 0) {
        d.dir.renameFile(@intCast(d.sel_file), nm);
    }
}

// OK on DELETE FILE(S): the file leaves the in-memory FAT (the disk is read-only).
pub fn removeFile(d: *Desktop, idx: usize) void {
    d.dir.remove(idx);
    d.sel_file = -1;
}

// Options > Save Desktop: serialise the desktop (icon cells, open windows,
// resolution, background) into DESKTOP.INF on the boot disk, the way TOS
// does. The mounted disk is read-only, so the file is written into the
// in-memory FAT — it shows up in the FLOPPY window like any other file.
pub fn saveDesktop(d: *Desktop) void {
    var open_wins: [gui.MAX_WIN]deskinf.Win = undefined;
    const n = collectWindows(d, &open_wins);
    const drive = &d.items[desk_icons.IC_FLOPPY];
    const trash = &d.items[desk_icons.IC_TRASH];
    const text = deskinf.write(&d.inf_buf, .{
        .medium = d.g.screen_w == 640,
        .bg = .{ d.bg_r, d.bg_g, d.bg_b },
        .drive = .{ .col = drive.cellCol(), .row = drive.cellRow(), .label = drive.label },
        .trash = .{ .col = trash.cellCol(), .row = trash.cellRow(), .label = trash.label },
        .wins = open_wins[0..n],
    });
    if (!d.dir.put(deskinf.NAME, @intCast(text.len)))
        d.dlg.alert("Cannot save the desktop.", "The disk directory is full.");
}

// The open directory windows, back to front, as DESKTOP.INF records them.
fn collectWindows(d: *Desktop, out: *[gui.MAX_WIN]deskinf.Win) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < d.wm.n) : (i += 1) {
        const id = d.wm.order[i];
        if (!d.wm.wins[id].open or !deskwin.isFloppyWin(d, id)) continue;
        const w = &d.wm.wins[id];
        out[n] = .{ .x = w.r.x, .y = w.r.y, .w = w.r.w, .h = w.r.h, .text_view = d.view == .text, .path = w.title };
        n += 1;
    }
    return n;
}
