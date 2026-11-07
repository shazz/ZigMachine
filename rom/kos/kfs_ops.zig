// --------------------------------------------------------------------------
// The image writer's operations (kfs.zig), each over a checked path whose folder exists. TOS's
// refusals: a folder where a file is wanted, a read-only file, a name taken, a folder not empty or
// moved into itself: EACCDN; a missing file EFILNF, a missing folder EPTHNF.
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");
const abi = @import("kfs_abi.zig");
const kp = @import("kfs_path.zig");
const kf = @import("kfs_fat.zig");
const kd = @import("kfs_dir.zig");
const kfile = @import("kfs_file.zig");

pub const Fail = kf.Error || error{ PathNotFound, FileNotFound, AccessDenied, BadHandle, Range, InvalidFunction };

const RDONLY: u8 = 0x01;
const ARCHIVE: u8 = 0x20;
const SETTABLE: u32 = 0x27; // read-only, hidden, system, archive

pub const Ctx = struct {
    d: *kf.Disk,
    top: fat.Dir,
    stamp: [2]u16,
    parent: fat.Dir, // the folder the path's last name is in
    p: *const kp.Path,

    fn name(c: *const Ctx) kd.Name {
        return kd.nameOf(c.p.last());
    }
    fn target(c: *const Ctx) Fail!?kd.Slot {
        const n = c.name();
        return kd.find(c.d, c.parent, &n);
    }
    fn temp(_: *const Ctx, slot: u32) kd.Name {
        var b: [9]u8 = undefined;
        return kd.nameOf(abi.tempName(slot, &b));
    }
};

/// A save's step: FIRST makes the temp file afresh, the data lands at `offset`, LAST renames it over
/// the file (one sector when both entries share one; else the old entry goes first, then the new
/// takes its name, then the old clusters are freed).
pub fn write(c: *Ctx, flags: u32, slot: u32, attr: u32, offset: u32, data: []const u8) Fail!i32 {
    if (slot >= abi.SLOTS) return error.BadHandle;
    if (data.len > abi.DATA_MAX) return error.Range;
    const old = try c.target();
    if (old) |o| if (o.isDir() or o.attr() & RDONLY != 0) return error.AccessDenied;
    const tn = c.temp(slot);
    var t = if (flags & abi.FIRST != 0) blk: {
        try dropTemp(c, &tn);
        break :blk kd.add(c.d, c.parent, kd.entry(&tn, ARCHIVE, 0, 0, c.stamp)) catch |x| return if (x == error.Full) error.AccessDenied else x;
    } else (try kd.find(c.d, c.parent, &tn)) orelse return error.BadHandle;
    if (offset > t.size()) return error.Range;
    try kfile.writeAt(c.d, &t, offset, data);
    if (flags & abi.LAST == 0) return 0;
    t.raw[0..11].* = c.name();
    t.raw[11] = @as(u8, @truncate(attr & SETTABLE)) | ARCHIVE;
    const o = old orelse {
        try kd.write(c.d, &t);
        return 0;
    };
    try kd.killLongNames(c.d, c.parent, o.index);
    if (o.sector == t.sector) { // one sector write: the old entry gone and the new named, together
        const b = try c.d.get(t.sector);
        b[(o.index % 16) * 32] = 0xE5;
        b[(t.index % 16) * 32 ..][0..32].* = t.raw;
        try c.d.put(t.sector, b);
    } else {
        var dead = o;
        dead.raw[0] = 0xE5;
        try kd.write(c.d, &dead);
        try kd.write(c.d, &t);
    }
    if (o.cluster() >= 2) try c.d.freeChain(o.cluster());
    return 0;
}

fn dropTemp(c: *Ctx, tn: *const kd.Name) Fail!void {
    const t = (try kd.find(c.d, c.parent, tn)) orelse return;
    try kd.kill(c.d, c.parent, &t);
    if (t.cluster() >= 2) try c.d.freeChain(t.cluster());
}

pub fn abort(c: *Ctx, slot: u32) Fail!i32 {
    if (slot >= abi.SLOTS) return error.BadHandle;
    const tn = c.temp(slot);
    try dropTemp(c, &tn);
    return 0;
}

pub fn delete(c: *Ctx) Fail!i32 {
    const s = (try c.target()) orelse return error.FileNotFound;
    if (s.isDir()) return error.FileNotFound; // Fdelete finds files only (Ddelete removes folders)
    if (s.attr() & RDONLY != 0) return error.AccessDenied;
    try kd.kill(c.d, c.parent, &s);
    if (s.cluster() >= 2) try c.d.freeChain(s.cluster());
    return 0;
}

/// `p` -> `p2` (in folder `to`): a file or a folder; in place within a folder, else a new entry
/// first and the old one deleted after (a folder's `..` then names its new parent).
pub fn rename(c: *Ctx, p2: *const kp.Path, to: fat.Dir) Fail!i32 {
    var s = (try c.target()) orelse return error.FileNotFound;
    const n2 = kd.nameOf(p2.last());
    if (try kd.find(c.d, to, &n2) != null) return error.AccessDenied;
    if (s.isDir() and kp.isPrefix(c.p.slice(), p2.parent())) return error.AccessDenied; // into itself
    if (to.cluster == c.parent.cluster) {
        try kd.killLongNames(c.d, c.parent, s.index); // they would name the old name
        s.raw[0..11].* = n2;
        try kd.write(c.d, &s);
        return 0;
    }
    var moved = s.raw;
    moved[0..11].* = n2;
    _ = kd.add(c.d, to, moved) catch |x| return if (x == error.Full) error.AccessDenied else x;
    try kd.kill(c.d, c.parent, &s);
    if (s.isDir()) {
        var up = (try kd.read(c.d, .{ .cluster = s.cluster() }, 1)) orelse return error.Corrupt;
        if (up.raw[0] == '.' and up.raw[1] == '.') {
            up.setCluster(to.cluster);
            try kd.write(c.d, &up);
        }
    }
    return 0;
}

/// A new folder: its cluster (`.`, `..`) written and linked before its entry appears.
pub fn mkdir(c: *Ctx) Fail!i32 {
    if (c.p.n > kp.MAX_NAMES - 1) return error.PathNotFound; // 8 folders below C:\ at most
    if (try c.target() != null) return error.AccessDenied;
    const cl = try c.d.free(2);
    try c.d.zeroCluster(cl);
    const b = try c.d.get(c.d.v.clusterSector(cl));
    b[0..32].* = kd.entry(&kd.nameOf("."), fat.ATTR_DIR, cl, 0, c.stamp);
    b[32..64].* = kd.entry(&kd.nameOf(".."), fat.ATTR_DIR, c.parent.cluster, 0, c.stamp);
    b[0..11].* = ".          ".*;
    b[32..43].* = "..         ".*;
    try c.d.put(c.d.v.clusterSector(cl), b);
    try c.d.set(cl, c.d.endMark());
    const n = c.name();
    _ = kd.add(c.d, c.parent, kd.entry(&n, fat.ATTR_DIR, cl, 0, c.stamp)) catch |x| {
        try c.d.set(cl, 0);
        return if (x == error.Full) error.AccessDenied else x;
    };
    return 0;
}

pub fn rmdir(c: *Ctx) Fail!i32 {
    const s = (try c.target()) orelse return error.PathNotFound;
    if (!s.isDir()) return error.PathNotFound;
    if (!try kd.isEmpty(c.d, .{ .cluster = s.cluster() })) return error.AccessDenied;
    try kd.kill(c.d, c.parent, &s);
    if (s.cluster() >= 2) try c.d.freeChain(s.cluster());
    return 0;
}

/// A file's read-only, hidden, system and archive bits := `attr`; a folder keeps its own. The new attributes.
pub fn setattr(c: *Ctx, attr: u32) Fail!i32 {
    var s = (try c.target()) orelse return error.FileNotFound;
    if (attr & ~SETTABLE != 0) return error.AccessDenied;
    s.raw[11] = (s.attr() & fat.ATTR_DIR) | @as(u8, @truncate(attr));
    try kd.write(c.d, &s);
    return s.raw[11];
}

comptime {
    std.debug.assert(fat.SECTOR / 32 == 16);
}
