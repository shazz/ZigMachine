// --------------------------------------------------------------------------
// GEMDOS's one-request writes (docs/KOS_GEMDOS.md §7), methods of gemdos.Dos: Fdelete, Frename,
// Dcreate, Ddelete, and Fattrib's set. Each is checked here first, as TOS would answer it (the host
// checks again: a cart is not trusted), then sent whole through the drive's env.kosFileOp. A drive
// with no host writes (A:, a host that serves none) answers EWRPRO.
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("gemdos.zig");
const gp = @import("gemdos_path.zig");
const abi = @import("kfs_abi.zig");
const kp = @import("kfs_path.zig");
const err = @import("gemdos_err.zig");
const fat = @import("fat.zig");
const Dos = gemdos.Dos;
const E = err.Error;

/// A path a write names: its drive, its C: form (`A\B\NAME.EXT`, what the host gets) and what is
/// there now (null: nothing). Its folder exists (else PathNotFound).
pub const Target = struct {
    letter: u8,
    path: [abi.PATH_MAX + 1]u8,
    len: usize,
    depth: usize, // names from the drive's root, the last included
    names: [gp.MAX_DEPTH * 2 + 1]gp.Fcb,
    entry: ?fat.Entry,

    pub fn str(t: *const Target) []const u8 {
        return t.path[0..t.len];
    }
};

pub fn resolve(dos: *Dos, path: []const u8, t: *Target) E!void {
    const p = gp.parse(path) catch return error.PathNotFound;
    t.letter = if (p.drive == gp.NO_DRIVE) dos.current else p.drive;
    const d = try dos.drive(t.letter);
    if (d.op_fn == null) return error.WriteProtect;
    const names = d.absolute(&p, &t.names) orelse return error.PathNotFound;
    if (names.len == 0) return error.AccessDenied; // the drive's root itself
    if (names.len > gp.MAX_DEPTH + 1) return error.PathNotFound;
    t.depth = names.len;
    t.len = 0;
    for (names, 0..) |*f, i| {
        if (gp.hasWild(f)) return error.FileNotFound;
        var name: [12]u8 = undefined;
        const k = gp.show(f, &name);
        if (!kp.validName(name[0..k])) return error.AccessDenied; // a name FAT cannot hold
        if (i > 0) {
            t.path[t.len] = '\\';
            t.len += 1;
        }
        @memcpy(t.path[t.len..][0..k], name[0..k]);
        t.len += k;
    }
    const folder = (d.walk(d.top, names[0 .. names.len - 1]) catch return error.ReadFault) orelse return error.PathNotFound;
    t.entry = d.lookup(folder, &names[names.len - 1]) catch return error.ReadFault;
}

/// One request to `letter`'s host: its TOS answer.
pub fn send(dos: *Dos, letter: u8, req: *abi.Req, path: []const u8, path2: []const u8, data: []const u8) i32 {
    const d = dos.drives[letter] orelse return err.EDRIVE;
    return d.send(req, path, path2, data);
}

fn one(dos: *Dos, t: *const Target, op: abi.Op, attr: u32, path2: []const u8) i32 {
    var req = abi.Req{ .op = @intFromEnum(op), .attr = attr };
    return send(dos, t.letter, &req, t.str(), path2, "");
}

pub fn Fdelete(dos: *Dos, path: []const u8) i32 {
    var t: Target = undefined;
    resolve(dos, path, &t) catch |x| return err.code(x);
    const e = t.entry orelse return err.EFILNF;
    if (e.isDir()) return err.EFILNF; // a folder goes with Ddelete
    if (e.attr & 0x01 != 0) return err.EACCDN;
    return one(dos, &t, .delete, 0, "");
}

/// A file or a folder from `old` to `new` (a new name, another folder, or both) on the same drive.
pub fn Frename(dos: *Dos, reserved: i32, old: []const u8, new: []const u8) i32 {
    _ = reserved; // TOS's first argument, always 0
    var a: Target = undefined;
    var b: Target = undefined;
    resolve(dos, old, &a) catch |x| return err.code(x);
    resolve(dos, new, &b) catch |x| return if (x == error.NoDrive or x == error.WriteProtect) err.ENSAME else err.code(x);
    if (a.letter != b.letter) return err.ENSAME;
    if (a.entry == null) return err.EFILNF;
    if (b.entry != null) return err.EACCDN;
    if (a.entry.?.isDir() and b.depth > a.depth and std.mem.eql(gp.Fcb, b.names[0..a.depth], a.names[0..a.depth])) return err.EACCDN; // into itself
    return one(dos, &a, .rename, 0, b.str());
}

pub fn Dcreate(dos: *Dos, path: []const u8) i32 {
    var t: Target = undefined;
    resolve(dos, path, &t) catch |x| return err.code(x);
    if (t.depth > gp.MAX_DEPTH) return err.EPTHNF;
    if (t.entry != null) return err.EACCDN;
    return one(dos, &t, .mkdir, 0, "");
}

/// An empty folder removed; not the drive's current folder nor one it is in (TOS).
pub fn Ddelete(dos: *Dos, path: []const u8) i32 {
    var t: Target = undefined;
    resolve(dos, path, &t) catch |x| return err.code(x);
    const e = t.entry orelse return err.EPTHNF;
    if (!e.isDir()) return err.EPTHNF;
    const d = dos.drives[t.letter].?;
    if (d.depth >= t.depth and std.mem.eql(gp.Fcb, d.cwd[0..t.depth], t.names[0..t.depth])) return err.EACCDN;
    return one(dos, &t, .rmdir, 0, "");
}

/// Fattrib(path, 1, attr): read-only, hidden, system and archive set; the new attributes.
pub fn setattr(dos: *Dos, path: []const u8, attr: i32) i32 {
    var t: Target = undefined;
    resolve(dos, path, &t) catch |x| return err.code(x);
    if (t.entry == null) return err.EFILNF;
    if (attr & ~@as(i32, 0x37) != 0) return err.EACCDN; // no volume label; the folder bit is kept
    return one(dos, &t, .setattr, @intCast(attr & 0x27), "");
}
