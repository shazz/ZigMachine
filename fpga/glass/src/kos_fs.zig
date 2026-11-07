// KOS's C: writes on the board (docs/KOS_GEMDOS.md §7): the file operations glass makes on the card's
// /HD through Linux's own FAT driver, for kos_file.zig. Every path is a CHECKED one (kos_kfs_path:
// 8.3 names under C:\, nothing else), and it is walked from an fd on /HD one folder at a time with
// O_NOFOLLOW | O_DIRECTORY, so nothing reaches outside /HD: no `..` gets here, an absolute path cannot
// be written, and a symbolic link (none on FAT; a test plants one) is refused, never followed. The
// answers are TOS's, as KFS gives them over an image (rom/kos/kfs_ops.zig).
const std = @import("std");
const linux = std.os.linux;
const kp = @import("kos_kfs_path");

pub const EWRITF: i32 = -10;
pub const EFILNF: i32 = -33;
pub const EPTHNF: i32 = -34;
pub const EACCDN: i32 = -36;
pub const EIHNDL: i32 = -37;
pub const ERANGE: i32 = -64;

const RDONLY: u32 = 0x01;
const ARCHIVE: u32 = 0x20;
const SETTABLE: u32 = 0x27;
const FAT_IOCTL_GET_ATTRIBUTES: u32 = 0x8004_7210; // _IOR('r', 0x10, __u32)
const FAT_IOCTL_SET_ATTRIBUTES: u32 = 0x4004_7211; // _IOW('r', 0x11, __u32)

pub const Fail = error{ WriteFault, FileNotFound, PathNotFound, AccessDenied, BadHandle, Range };

pub fn code(e: Fail) i32 {
    return switch (e) {
        error.WriteFault => EWRITF,
        error.FileNotFound => EFILNF,
        error.PathNotFound => EPTHNF,
        error.AccessDenied => EACCDN,
        error.BadHandle => EIHNDL,
        error.Range => ERANGE,
    };
}

fn ok(rc: usize) bool {
    return linux.errno(rc) == .SUCCESS;
}

/// `name` NUL-terminated (a checked 8.3 name: at most 12 bytes).
pub fn z(name: []const u8, buf: *[16]u8) [*:0]const u8 {
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    return buf[0..name.len :0];
}

/// The folder `names` lead to from `root` (an fd the caller closes), never through a link.
pub fn walk(root: i32, names: []const []const u8) Fail!i32 {
    var at = root;
    for (names) |n| {
        var b: [16]u8 = undefined;
        const rc = linux.openat(at, z(n, &b), .{ .DIRECTORY = true, .NOFOLLOW = true, .CLOEXEC = true }, 0);
        if (at != root) _ = linux.close(at);
        if (!ok(rc)) return error.PathNotFound;
        at = @intCast(rc);
    }
    return if (at == root) dup(root) else at;
}

fn dup(fd: i32) Fail!i32 {
    const rc = linux.openat(fd, ".", .{ .DIRECTORY = true, .CLOEXEC = true }, 0);
    return if (ok(rc)) @intCast(rc) else error.PathNotFound;
}

pub const Kind = enum { none, file, dir, other };

/// What `name` is in `dir` (a link is `other`: refused by every operation); a file's size and mode.
pub fn kind(dir: i32, name: []const u8, size: ?*u64, mode: ?*u32) Kind {
    var b: [16]u8 = undefined;
    var st: linux.Statx = undefined;
    const rc = linux.statx(dir, z(name, &b), linux.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true, .MODE = true, .SIZE = true }, &st);
    if (!ok(rc)) return .none;
    if (size) |s| s.* = st.size;
    if (mode) |m| m.* = st.mode;
    if (linux.S.ISDIR(st.mode)) return .dir;
    return if (linux.S.ISREG(st.mode)) .file else .other;
}

/// Read-only: no write permission (vfat maps FAT's read-only bit onto the mode).
pub fn readOnly(dir: i32, name: []const u8) bool {
    var mode: u32 = 0;
    return kind(dir, name, null, &mode) == .file and mode & 0o222 == 0;
}

/// `len` bytes of `data` at `offset` of `name` (created empty first when `create`), synced.
pub fn writeAt(dir: i32, name: []const u8, create: bool, offset: u32, data: []const u8) Fail!void {
    var b: [16]u8 = undefined;
    if (kind(dir, name, null, null) == .other) return error.AccessDenied;
    const flags: linux.O = .{ .ACCMODE = .WRONLY, .CREAT = create, .TRUNC = create, .NOFOLLOW = true, .CLOEXEC = true };
    const rc = linux.openat(dir, z(name, &b), flags, 0o644);
    if (!ok(rc)) return if (create) error.WriteFault else error.BadHandle;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var size: u64 = 0;
    _ = kind(dir, name, &size, null);
    if (offset > size) return error.Range;
    var done: usize = 0;
    while (done < data.len) {
        const w = linux.pwrite(fd, data[done..].ptr, data.len - done, @as(i64, offset) + @as(i64, @intCast(done)));
        if (!ok(w) or w == 0) return error.WriteFault;
        done += w;
    }
    if (!ok(linux.fsync(fd))) return error.WriteFault;
}

/// Attributes: read-only through the mode (any filesystem), the rest through FAT's own ioctl (vfat
/// only; elsewhere, a test's tmpfs, they are not kept). The attributes the file has now.
pub fn setAttr(dir: i32, name: []const u8, attr: u32) Fail!u32 {
    var b: [16]u8 = undefined;
    const rc = linux.openat(dir, z(name, &b), .{ .NOFOLLOW = true, .CLOEXEC = true }, 0);
    if (!ok(rc)) return error.FileNotFound;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var have: u32 = 0;
    const fat = ok(linux.ioctl(fd, FAT_IOCTL_GET_ATTRIBUTES, @intFromPtr(&have)));
    const want: u32 = (have & 0x10) | (attr & SETTABLE);
    if (fat) {
        if (!ok(linux.ioctl(fd, FAT_IOCTL_SET_ATTRIBUTES, @intFromPtr(&want)))) return error.AccessDenied;
        return want;
    }
    var mode: u32 = 0;
    _ = kind(dir, name, null, &mode);
    const perm: u32 = if (attr & RDONLY != 0) mode & 0o555 else (mode & 0o777) | 0o200;
    if (!ok(linux.fchmod(fd, perm))) return error.AccessDenied;
    return (have & 0x10) | (attr & RDONLY) | ARCHIVE;
}

pub fn rename(from: i32, a: []const u8, to: i32, b2: []const u8) Fail!void {
    var x: [16]u8 = undefined;
    var y: [16]u8 = undefined;
    if (!ok(linux.renameat(from, z(a, &x), to, z(b2, &y)))) return error.WriteFault;
}

pub fn unlink(dir: i32, name: []const u8, folder: bool) Fail!void {
    var b: [16]u8 = undefined;
    const rc = linux.unlinkat(dir, z(name, &b), if (folder) linux.AT.REMOVEDIR else 0);
    if (ok(rc)) return;
    return if (linux.errno(rc) == .NOTEMPTY or linux.errno(rc) == .EXIST) error.AccessDenied else error.WriteFault;
}

pub fn mkdir(dir: i32, name: []const u8) Fail!void {
    var b: [16]u8 = undefined;
    if (!ok(linux.mkdirat(dir, z(name, &b), 0o755))) return error.WriteFault;
}

/// The folder's own entries on the disk (a rename, a new file) flushed.
pub fn syncDir(dir: i32) void {
    _ = linux.fsync(dir);
}
