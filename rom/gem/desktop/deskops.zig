// --------------------------------------------------------------------------
// The commands behind the File and Options menus and their dialogs' OK
// buttons: open, show info, new folder, rename, delete, Save Desktop. They act
// on the selection and the directory model; the menus only route to them.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const dt = @import("desktop.zig");
const fileop = @import("fileop.zig");
const dirmodel = @import("dirmodel.zig");
const deskwin = @import("deskwin.zig");
const desknav = @import("desknav.zig");
const deskinf = @import("deskinf.zig");
const deskmode = @import("deskmode.zig");
const desk_icons = @import("desk_icons.zig");
const deskdrive = @import("deskdrive.zig");
const Desktop = dt.Desktop;
const Action = dt.Action;

// Open the current selection: a folder opens its window, a desktop icon its
// window/app, a program file launches (GEM: no-op with nothing selected).
pub fn openSelection(d: *Desktop, action: *Action) void {
    if (d.sel_folder >= 0) {
        desknav.enterFolder(d, @intCast(d.sel_folder));
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
        const a = &d.drives[0];
        const used = a.usedBytes(); // DISK INFORMATION for drive A: (ref: real TOS)
        const cap: u32 = 726528; // a 3.5" DS floppy
        d.info.openDisk(@intCast(a.folderCount(dirmodel.ROOT)), a.n_disk, used, if (cap > used) cap - used else 0);
        d.info.source = d.items[desk_icons.IC_FLOPPY].label; // KOS: FLOPPY or SD IMAGE
    } else if (d.sel_icon == desk_icons.IC_HARD) {
        const c = &d.drives[1]; // KOS's C: (F5): what the model holds of the card, its free space unknown
        d.info.openDisk(@intCast(c.folderCount(dirmodel.ROOT)), c.n_disk, c.usedBytes(), 0);
        d.info.source = d.items[desk_icons.IC_HARD].label;
    } else if (d.sel_icon >= 0) {
        d.dlg.alert(d.items[@intCast(d.sel_icon)].label, "Kind: Desktop icon");
    }
}

// File > New Folder: TOS asks for the name first (NEW FOLDER box with an 8.3
// field); the folder is only created when that dialog is confirmed.
pub fn newFolder(d: *Desktop) void {
    if (d.drv.cur != deskdrive.C and d.dir.n_folders >= dirmodel.MAX_FOLDERS) { // C:'s folders are the card's
        d.dlg.alert("Too many folders.", "Delete one and try again.");
        return;
    }
    d.info.openNewFolder();
}

// OK on the NEW FOLDER box: create it under the top window's directory.
// On C: the shell makes it (Dcreate, fileop.zig); C:'s model only follows the re-read.
pub fn createFolder(d: *Desktop) void {
    const parent: i16 = if (deskwin.topFloppy(d)) |w| w.dir else dirmodel.ROOT;
    if (d.drv.cur == deskdrive.C) return fileop.mkdir(d, parent, autoName(d));
    d.dir.addFolder(parent, d.info.name.text());
}

// An empty name is TOS's auto-name on drive A (dirmodel.addFolder); on C: the same NEWDIRn.
fn autoName(d: *Desktop) []const u8 {
    const typed = d.info.name.text();
    if (typed.len > 0) return typed;
    d.dir.new_seq += 1;
    return std.fmt.bufPrint(&d.info.name.buf, "NEWDIR{d}", .{d.dir.new_seq}) catch "NEWDIR";
}

// OK on Show Info...: apply the (keyboard-edited) name to the selection.
pub fn applyRename(d: *Desktop) void {
    const nm = d.info.name.text();
    if (nm.len == 0) return;
    if (d.drv.cur == deskdrive.C) return renameOnC(d, nm);
    if (d.sel_folder >= 0) {
        d.dir.renameFolder(@intCast(d.sel_folder), nm);
    } else if (d.sel_file >= 0) {
        d.dir.renameFile(@intCast(d.sel_file), nm);
    }
}

// Show Info's rename on C: Frename through the shell, the window re-read after it.
fn renameOnC(d: *Desktop, nm: []const u8) void {
    const dir: i16 = if (deskwin.topFloppy(d)) |w| w.dir else dirmodel.ROOT;
    const old = if (d.sel_folder >= 0) d.dir.folderName(@intCast(d.sel_folder)) else if (d.sel_file >= 0) d.dir.name(@intCast(d.sel_file)) else return;
    if (std.mem.eql(u8, old, nm)) return; // unchanged: nothing to write
    fileop.rename(d, dir, old, nm);
}

// OK on DELETE FILE(S): the file leaves the in-memory FAT (the disk is read-only).
pub fn removeFile(d: *Desktop, idx: usize) void {
    d.dir.remove(idx);
    d.sel_file = -1;
}

// Options > Save Desktop: serialise the desktop (icon cells, open windows,
// resolution, background) into DESKTOP.INF, the way TOS does. The ROM reaches
// no disk: the text stays in inf_buf and the caller reports `.save_inf`, on
// which the shell writes it to C:\DESKTOP.INF (apps/zig/scenes/gem_inf.zig)
// and reads it back at every start. The file is listed on C: when it is
// mounted, else in drive A's in-memory FAT (read-only: nowhere to keep it).
// False: not saved (the listing is full).
pub fn saveDesktop(d: *Desktop) bool {
    var open_wins: [gui.MAX_WIN]deskinf.Win = undefined;
    const n = collectWindows(d, &open_wins);
    const drive = &d.items[desk_icons.IC_FLOPPY];
    const trash = &d.items[desk_icons.IC_TRASH];
    const text = deskinf.write(&d.inf_buf, .{
        .res = deskmode.resOf(d.g.screen),
        .bg = .{ d.bg_r, d.bg_g, d.bg_b },
        .drive = .{ .col = drive.cellCol(), .row = drive.cellRow(), .label = "FLOPPY DISK" }, // not the source
        .trash = .{ .col = trash.cellCol(), .row = trash.cellRow(), .label = trash.label },
        .wins = open_wins[0..n],
    });
    d.mode.inf_len = @intCast(text.len); // deskInfPtr / deskInfLen: the shell's (and a harness's) copy
    if (d.drv.c_mounted) {
        // The file goes to the card whatever the listing holds: C:'s model is capped at MAX_FILES
        // over the whole /HD tree, so a full listing only means it shows at the next start.
        _ = d.drives[deskdrive.C].put(deskinf.NAME, @intCast(text.len));
        return true;
    }
    if (d.drives[deskdrive.A].put(deskinf.NAME, @intCast(text.len))) return true; // A: in memory only
    d.dlg.alert("Cannot save the desktop.", "The disk directory is full.");
    return false;
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
