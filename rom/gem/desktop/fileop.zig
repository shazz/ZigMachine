// --------------------------------------------------------------------------
// Real file operations on C: (docs/GEM5_PLAN.md P1.1): the ROM's half. The desktop decides what
// to copy, move, delete, rename or create and posts it in the mailbox (rom/sdk/deskop.zig); the
// shell cart does it through KOS GEMDOS, a step a frame, and writes the counts back. Here: the
// requests, the frame hook that repaints on the shell's changes, and the end (C:'s windows
// re-pointed by path, since the shell re-read C: and its folder indices moved). The boxes are
// fileop_ui.zig. Drive A: keeps its in-memory behaviour (deskops.zig): only C: reaches a disk.
// --------------------------------------------------------------------------
const std = @import("std");
const gui = @import("../gui.zig");
const op = @import("../../sdk/deskop.zig");
const dt = @import("desktop.zig");
const dirmodel = @import("dirmodel.zig");
const deskdrive = @import("deskdrive.zig");
const deskdirty = @import("deskdirty.zig");
const deskwin = @import("deskwin.zig");
const desknav = @import("desknav.zig");
const conflict = @import("conflict.zig");
const Desktop = dt.Desktop;
pub const Op = op.Op;

const TITLE_MAX = 40; // dirmodel.Folder.title

pub const State = struct {
    box: op.Box = .{},
    seen: u32 = 0, // box.seq at the last repaint
    ctrl: bool = false, // Control held (deskkey.zig): a drag MOVES
    drag_folder: bool = false, // the item dragged (Desktop.file_drag) is a folder, not a file
    confirm: bool = false, // the confirm box is up for the counted operation
    conflict: conflict.Conflict = .{},
    // C:'s windows' paths when the operation started: after the shell re-read C: they are found again by path.
    titles: [gui.MAX_WIN][TITLE_MAX]u8 = undefined,
    tlens: [gui.MAX_WIN]u8 = [_]u8{0} ** gui.MAX_WIN,

    /// An operation is in flight: the desktop is modal until it ends.
    pub fn busy(s: *const State) bool {
        return s.box.phase != op.IDLE;
    }
};

/// What a drag or the TRASH acts on: items of one directory of one drive.
pub const Items = struct {
    drv: u1,
    dir: i16,
    files: u32 = 0, // bit per file record of that drive's model
    folders: u16 = 0, // bit per folder
};

/// `dir` of model `m` as GEMDOS spells a folder: "C:\A\B\" (the root: "C:\").
pub fn dirPath(m: *const dirmodel.DirModel, dir: i16, out: *[op.PATH_MAX]u8) []const u8 {
    var chain: [dirmodel.MAX_FOLDERS]u8 = undefined;
    var n: usize = 0;
    var at = dir;
    while (at != dirmodel.ROOT and n < chain.len) : (n += 1) {
        chain[n] = @intCast(at);
        at = m.folders[@intCast(at)].parent;
    }
    var len: usize = 3;
    out[0..3].* = .{ m.letter, ':', '\\' };
    while (n > 0) {
        n -= 1;
        const nm = m.folderName(chain[n]);
        if (len + nm.len + 1 > op.PATH_MAX) break;
        @memcpy(out[len..][0..nm.len], nm);
        out[len + nm.len] = '\\';
        len += nm.len + 1;
    }
    return out[0..len];
}

/// Copy (or, `move`, move) `it` into directory `to` of drive `to_drv`: counted first, then the box.
pub fn copy(d: *Desktop, it: Items, to_drv: u1, to: i16, move: bool) void {
    const b = begin(d, if (move) .move else .copy) orelse return;
    setSource(d, b, it);
    var p: [op.PATH_MAX]u8 = undefined;
    setPath(&b.dst, &b.dst_len, dirPath(&d.drives[to_drv], to, &p));
    post(d, op.COUNT);
}

/// Delete `it` (the TRASH): counted first, then the DELETE FILE(S) box.
pub fn delete(d: *Desktop, it: Items) void {
    const b = begin(d, .delete) orelse return;
    setSource(d, b, it);
    post(d, op.COUNT);
}

/// File > New Folder on C: `name` under `parent`; no box, the shell creates it at once.
pub fn mkdir(d: *Desktop, parent: i16, name: []const u8) void {
    const b = begin(d, .mkdir) orelse return;
    var p: [op.PATH_MAX]u8 = undefined;
    setPath(&b.dst, &b.dst_len, dirPath(d.dir, parent, &p));
    b.setName(name);
    post(d, op.RUN);
}

/// Show Info's OK on C: item `old` of `dir` becomes `new`.
pub fn rename(d: *Desktop, dir: i16, old: []const u8, new: []const u8) void {
    const b = begin(d, .rename) orelse return;
    var p: [op.PATH_MAX]u8 = undefined;
    setPath(&b.src, &b.src_len, dirPath(d.dir, dir, &p));
    _ = b.addItem(old);
    b.setName(new);
    post(d, op.RUN);
}

fn begin(d: *Desktop, kind: Op) ?*op.Box {
    const s = &d.fop;
    if (s.busy()) return null; // one at a time: the desktop is modal while one runs
    s.box = .{ .op = @intFromEnum(kind) };
    s.confirm = false;
    snapshotWindows(d);
    return &s.box;
}

fn post(d: *Desktop, phase: u32) void {
    d.fop.box.phase = phase;
    deskdirty.touch(d);
}

fn setPath(dst: *[op.PATH_MAX]u8, len: *u32, p: []const u8) void {
    @memcpy(dst[0..p.len], p);
    len.* = @intCast(p.len);
}

fn setSource(d: *Desktop, b: *op.Box, it: Items) void {
    const m = &d.drives[it.drv];
    var p: [op.PATH_MAX]u8 = undefined;
    setPath(&b.src, &b.src_len, dirPath(m, it.dir, &p));
    for (0..m.n_disk) |i| if ((it.files >> @intCast(i)) & 1 != 0) {
        _ = b.addItem(m.name(i));
    };
    for (0..m.n_folders) |f| if ((it.folders >> @intCast(f)) & 1 != 0) {
        _ = b.addItem(m.folderName(@intCast(f)));
    };
}

fn snapshotWindows(d: *Desktop) void {
    for (0..gui.MAX_WIN) |id| {
        const w = &d.wm.wins[id];
        const keep = id < d.wm.n and w.open and deskwin.isFloppyWin(d, @intCast(id)) and d.drv.win[id] == deskdrive.C;
        const n: usize = if (keep) @min(w.title.len, TITLE_MAX) else 0;
        if (keep) @memcpy(d.fop.titles[id][0..n], w.title[0..n]);
        d.fop.tlens[id] = @intCast(n);
    }
}

/// Every frame, before the desktop decides whether to draw: the shell's changes repaint, and a
/// finished operation ends here, before anything is drawn from C:'s re-read model.
pub fn watch(d: *Desktop) void {
    const s = &d.fop;
    if (s.box.seq != s.seen) {
        s.seen = s.box.seq;
        deskdirty.touch(d);
    }
    if (s.box.phase == op.DONE) finish(d);
}

fn finish(d: *Desktop) void {
    const s = &d.fop;
    repoint(d);
    @import("fileop_ui.zig").report(d, &s.box);
    s.box.phase = op.IDLE;
    s.confirm = false;
    d.trash.active = false;
    d.copy.active = false;
    s.conflict.active = false;
    deskdirty.touch(d);
}

/// C:'s windows show the folders they showed, found by path in the re-read model (one gone: C:\).
fn repoint(d: *Desktop) void {
    const keep = d.drv.cur;
    for (0..gui.MAX_WIN) |id| {
        const n = d.fop.tlens[id];
        if (n == 0 or !d.wm.wins[id].open) continue;
        deskdrive.use(d, deskdrive.C);
        desknav.show(d, @intCast(id), folderByTitle(d.dir, d.fop.titles[id][0..n]));
    }
    deskdrive.use(d, keep);
    deskdrive.focusTop(d);
    d.sel_file = -1;
    d.sel_folder = -1;
    d.sel_files = 0;
    d.sel_folders = 0;
}

fn folderByTitle(m: *const dirmodel.DirModel, title: []const u8) i16 {
    for (0..m.n_folders) |f| {
        const fd = &m.folders[f];
        if (std.mem.eql(u8, fd.title[0..fd.tlen], title)) return @intCast(f);
    }
    return dirmodel.ROOT;
}
