// --------------------------------------------------------------------------
// What the shell's file operations (gem_fileop.zig) do to ONE entry the walk reached: delete it,
// create its folder where it goes, start its copy, rename it into place (a move on one drive), or
// leave it out; and what they do to a folder whose entries are all done. Each answers 0, or a
// GEMDOS error that stops the operation, and counts the box's folders_left / files_left down.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");
const op = @import("rom_sdk").deskop;
const fp = @import("gem_fileop_path.zig");
const count = @import("gem_fileop_count.zig");
const walk = @import("gem_fileop_walk.zig");
const copy = @import("gem_fileop_copy.zig");
const err = gemdos.err;

pub fn delete(b: *op.Box, e: *const fp.Entry, from: []const u8) i32 {
    if (e.dir) return if (walk.down(e.slice(), e.slice())) 0 else err.EPTHNF; // its Ddelete once empty (folderDone)
    const r = gemdos.dos().Fdelete(from);
    if (r == 0) b.files_left -|= 1;
    return r;
}

/// `replace`: the NAME CONFLICT kept the name: a folder is copied INTO the one there, a file over it.
pub fn copyTo(b: *op.Box, e: *const fp.Entry, name: []const u8, from: []const u8, to: []const u8, replace: bool) i32 {
    if (std.mem.eql(u8, from, to)) return skip(b, e, from); // onto itself: nothing to do
    if (!e.dir) return copy.start(from, to, e.size);
    const r = gemdos.dos().Dcreate(to);
    if (r < 0 and !(r == err.EACCDN and replace)) return r;
    if (!walk.down(e.slice(), name)) return err.EPTHNF;
    b.folders_left -|= 1;
    return 0;
}

/// A move on one drive: the item renamed into place, whole (a folder with all it holds): one
/// request, and the source is never at risk (it is the same entry).
pub fn rename(b: *op.Box, from: []const u8, to: []const u8, replace: bool) i32 {
    const c = count.item(from);
    const dos = gemdos.dos();
    if (replace and c.folders > 0) return err.EACCDN; // a folder cannot replace one by a rename
    if (replace) _ = dos.Fdelete(to);
    const r = dos.Frename(0, from, to);
    if (r < 0) return r;
    b.folders_left -|= c.folders;
    b.files_left -|= c.files;
    return 0;
}

/// Leaving a folder whose entries are all done: a delete removes it; a move to another drive too
/// (a folder still holding a source it could not delete stays, counted as kept). 1: a write was
/// made (the frame ends there), 0 none, < 0 the delete's error.
pub fn folderDone(b: *op.Box, folder: []const u8) i32 {
    const dos = gemdos.dos();
    if (b.op == @intFromEnum(op.Op.delete)) {
        const r = dos.Ddelete(folder);
        if (r == 0) b.folders_left -|= 1;
        b.seq +%= 1;
        return if (r < 0) r else 1;
    }
    if (b.op != @intFromEnum(op.Op.move)) return 0;
    if (dos.Ddelete(folder) < 0) b.kept += 1;
    return 1;
}

/// The entry left out: what it holds is no longer to do.
pub fn skip(b: *op.Box, e: *const fp.Entry, from: []const u8) i32 {
    const c = if (e.dir) count.item(from) else count.Counts{ .files = 1 };
    b.folders_left -|= c.folders;
    b.files_left -|= c.files;
    return 0;
}

pub fn sameDrive(b: *const op.Box) bool {
    return b.src_len > 0 and b.dst_len > 0 and b.src[0] == b.dst[0];
}
