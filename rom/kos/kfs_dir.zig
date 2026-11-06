// --------------------------------------------------------------------------
// The image writer's directories (kfs.zig): 32-byte slots by index, so an entry can be found, written
// back in place and deleted with the long-name slots in front of it (a card a PC wrote has them: left
// behind, fsck.fat calls them orphans). A folder that is full grows by a zeroed cluster, linked last.
// Names are FAT's 11 bytes ("NAME    EXT"); only short entries are ever written.
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");
const kf = @import("kfs_fat.zig");

const S = fat.SECTOR;
const PER = S / 32;
pub const Name = [11]u8;

pub const Slot = struct {
    index: u32,
    sector: u32,
    raw: [32]u8,

    pub fn cluster(s: *const Slot) u32 {
        return std.mem.readInt(u16, s.raw[26..28], .little) | @as(u32, std.mem.readInt(u16, s.raw[20..22], .little)) << 16;
    }
    pub fn size(s: *const Slot) u32 {
        return std.mem.readInt(u32, s.raw[28..32], .little);
    }
    pub fn attr(s: *const Slot) u8 {
        return s.raw[11];
    }
    pub fn isDir(s: *const Slot) bool {
        return s.raw[11] & fat.ATTR_DIR != 0;
    }
    pub fn setCluster(s: *Slot, c: u32) void {
        std.mem.writeInt(u16, s.raw[26..28], @truncate(c), .little);
        std.mem.writeInt(u16, s.raw[20..22], @truncate(c >> 16), .little);
    }
    pub fn setSize(s: *Slot, n: u32) void {
        std.mem.writeInt(u32, s.raw[28..32], n, .little);
    }
};

/// A new short entry: `name`, `attr`, its first cluster and size, stamped `stamp` (DOS time, date).
pub fn entry(name: *const Name, attr: u8, c: u32, size: u32, stamp: [2]u16) [32]u8 {
    var r = [_]u8{0} ** 32;
    r[0..11].* = name.*;
    r[11] = attr;
    for ([_]usize{ 14, 22 }) |at| std.mem.writeInt(u16, r[at..][0..2], stamp[0], .little); // created, written
    for ([_]usize{ 16, 18, 24 }) |at| std.mem.writeInt(u16, r[at..][0..2], stamp[1], .little); // + accessed
    var s = Slot{ .index = 0, .sector = 0, .raw = r };
    s.setCluster(c);
    s.setSize(size);
    return s.raw;
}

/// The sector holding slot `index` of `dir`, or null past the folder's end.
fn sectorOf(d: *kf.Disk, dir: fat.Dir, index: u32) kf.Error!?u32 {
    return d.v.dirSector(dir, index / PER);
}

pub fn read(d: *kf.Disk, dir: fat.Dir, index: u32) kf.Error!?Slot {
    const n = (try sectorOf(d, dir, index)) orelse return null;
    const b = try d.v.sector(n);
    return .{ .index = index, .sector = n, .raw = b[(index % PER) * 32 ..][0..32].* };
}

pub fn write(d: *kf.Disk, s: *const Slot) kf.Error!void {
    const b = try d.get(s.sector);
    b[(s.index % PER) * 32 ..][0..32].* = s.raw;
    try d.put(s.sector, b);
}

/// The live short entry named `name` (no `.`/`..`, no volume label), or null.
pub fn find(d: *kf.Disk, dir: fat.Dir, name: *const Name) kf.Error!?Slot {
    var i: u32 = 0;
    while (try read(d, dir, i)) |s| : (i += 1) {
        if (s.raw[0] == 0) return null;
        if (s.raw[0] == 0xE5 or s.raw[11] == 0x0F or s.raw[11] & fat.ATTR_VOLUME != 0 or s.raw[0] == '.') continue;
        if (std.mem.eql(u8, s.raw[0..11], name)) return s;
    }
    return null;
}

/// True if the folder holds nothing but `.`, `..` and deleted slots.
pub fn isEmpty(d: *kf.Disk, dir: fat.Dir) kf.Error!bool {
    var i: u32 = 0;
    while (try read(d, dir, i)) |s| : (i += 1) {
        if (s.raw[0] == 0) return true;
        if (s.raw[0] == 0xE5 or s.raw[0] == '.') continue;
        return false;
    }
    return true;
}

/// `raw` written into the folder's first free slot (growing a cluster folder when it is full).
pub fn add(d: *kf.Disk, dir: fat.Dir, raw: [32]u8) kf.Error!Slot {
    var i: u32 = 0;
    while (try read(d, dir, i)) |s| : (i += 1) {
        if (s.raw[0] == 0 or s.raw[0] == 0xE5) {
            var out = s;
            out.raw = raw;
            try write(d, &out);
            return out;
        }
    }
    if (dir.cluster == 0) return error.Full; // FAT12/16's fixed root holds what it holds
    var last = dir.cluster;
    while (try d.v.next(last)) |nx| last = nx; // dirSector walked this chain already: it ends
    const c = try d.free(last + 1);
    try d.zeroCluster(c);
    try d.set(c, d.endMark());
    try d.set(last, c);
    var out = Slot{ .index = i, .sector = d.v.clusterSector(c), .raw = raw };
    try write(d, &out);
    return out;
}

/// The entry deleted, and the long-name slots in front of it (they name it; alone they are orphans).
/// The long names first: a cut after them leaves a plain short entry, which is a clean file.
pub fn kill(d: *kf.Disk, dir: fat.Dir, s: *const Slot) kf.Error!void {
    try killLongNames(d, dir, s.index);
    var dead = s.*;
    dead.raw[0] = 0xE5;
    try write(d, &dead);
}

/// The long-name slots right in front of slot `index` deleted.
pub fn killLongNames(d: *kf.Disk, dir: fat.Dir, index: u32) kf.Error!void {
    var i = index;
    while (i > 0) {
        i -= 1;
        var p = (try read(d, dir, i)) orelse return;
        if (p.raw[11] != 0x0F or p.raw[0] == 0xE5) return;
        p.raw[0] = 0xE5;
        try write(d, &p);
    }
}

/// "NAME.EXT" (checked by kfs_path) as FAT's 11 bytes.
pub fn nameOf(s: []const u8) Name {
    var out: Name = [_]u8{' '} ** 11;
    const dot = std.mem.indexOfScalar(u8, s, '.');
    const base = if (dot) |k| s[0..k] else s;
    @memcpy(out[0..base.len], base);
    if (dot) |k| @memcpy(out[8..][0 .. s.len - k - 1], s[k + 1 ..]);
    return out;
}
