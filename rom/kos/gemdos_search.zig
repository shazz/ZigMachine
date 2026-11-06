// --------------------------------------------------------------------------
// Fsfirst / Fsnext (docs/KOS_GEMDOS.md §2): the disk transfer address, TOS's 44 bytes. Its first
// 21 bytes are the search's own state (TOS keeps its own there too), so a search needs no table
// and as many run at once as the cart has DTAs. Multi-byte fields are in the cart's byte order
// (little-endian: KESTREL's carts are wasm), at TOS's offsets.
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");
const dir = @import("fat_dir.zig");
const gp = @import("gemdos_path.zig");

pub const FA_RDONLY: u8 = 0x01;
pub const FA_HIDDEN: u8 = 0x02;
pub const FA_SYSTEM: u8 = 0x04;
pub const FA_VOLUME: u8 = 0x08;
pub const FA_DIR: u8 = 0x10;
pub const FA_ARCHIVE: u8 = 0x20;

pub const Dta = extern struct {
    reserved: [21]u8 = [_]u8{0} ** 21, // drive, folder cluster (4), slot (4), attributes, pattern (11)
    attrib: u8 = 0,
    time: [2]u8 = .{ 0, 0 },
    date: [2]u8 = .{ 0, 0 },
    length: [4]u8 = .{ 0, 0, 0, 0 },
    name: [14]u8 = [_]u8{0} ** 14, // "NAME.EXT", NUL-terminated
};

comptime {
    std.debug.assert(@sizeOf(Dta) == 44);
    std.debug.assert(@offsetOf(Dta, "attrib") == 21 and @offsetOf(Dta, "name") == 30);
}

pub fn start(t: *Dta, drive: u8, folder: fat.Dir, attr: u8, pattern: gp.Fcb) void {
    t.reserved[0] = drive;
    std.mem.writeInt(u32, t.reserved[1..5], folder.cluster, .little);
    std.mem.writeInt(u32, t.reserved[5..9], 0, .little);
    t.reserved[9] = attr;
    t.reserved[10..21].* = pattern;
}

pub fn driveOf(t: *const Dta) u8 {
    return t.reserved[0];
}

/// The next match into the DTA: true, or false when there is none left (ENMFIL).
/// Files always match; folders, hidden and system files only when `attr` asks for them (TOS).
pub fn next(t: *Dta, v: *fat.Volume) fat.Error!bool {
    const folder: fat.Dir = .{ .cluster = std.mem.readInt(u32, t.reserved[1..5], .little) };
    var slot = std.mem.readInt(u32, t.reserved[5..9], .little);
    const attr = t.reserved[9];
    const pattern: gp.Fcb = t.reserved[10..21].*;
    defer std.mem.writeInt(u32, t.reserved[5..9], slot, .little);
    while (try dir.next(v, folder, &slot)) |e| {
        if (e.attr & (FA_DIR | FA_HIDDEN | FA_SYSTEM) & ~attr != 0) continue;
        const name = gp.fcbOfEntry(e.nameSlice());
        if (!gp.matches(&pattern, &name)) continue;
        fill(t, &e, dir.stamp);
        return true;
    }
    return false;
}

/// `stamp`: the entry's DOS time and date words, as stored.
pub fn fill(t: *Dta, e: *const fat.Entry, stamp: [2]u16) void {
    t.attrib = e.attr;
    std.mem.writeInt(u16, &t.time, stamp[0], .little);
    std.mem.writeInt(u16, &t.date, stamp[1], .little);
    std.mem.writeInt(u32, &t.length, if (e.isDir()) 0 else e.size, .little);
    t.name = [_]u8{0} ** 14;
    @memcpy(t.name[0..e.name_len], e.nameSlice());
}
