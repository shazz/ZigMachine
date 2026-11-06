// --------------------------------------------------------------------------
// A directory walked one entry at a time (KOS GEMDOS, docs/KOS_GEMDOS.md): fat.zig's `list` fills an
// array, which a folder of hundreds of files would need whole; GEMDOS's Fsfirst/Fsnext and a POSIX
// readdir need "the entry after this one" and "the entry named X" with no buffer at all. A cursor
// is the raw 32-byte slot index in the directory, so it survives between calls (the DTA keeps it).
// --------------------------------------------------------------------------
const std = @import("std");
const fat = @import("fat.zig");

const SLOTS_PER_SECTOR = fat.SECTOR / 32;

/// The DOS time and date words of the entry `next` returned last (GEMDOS's DTA carries them; fat_entry's
/// Entry keeps the desktop's YYYYMMDD only, and growing it would change every cart that lists a disk).
pub var stamp: [2]u16 = .{ 0, 0 };

/// The next entry GEMDOS shows from slot `slot.*` on (deleted, long-name, volume, `.` and `..`
/// entries skipped), the cursor moved past it; null at the directory's end.
pub fn next(v: *fat.Volume, d: fat.Dir, slot: *u32) fat.Error!?fat.Entry {
    const limit = (v.clusters * v.spc + v.root_sectors) * SLOTS_PER_SECTOR;
    while (slot.* < limit) {
        const s = (try v.dirSector(d, slot.* / SLOTS_PER_SECTOR)) orelse return null;
        const b = try v.sector(s);
        const r = b[(slot.* % SLOTS_PER_SECTOR) * 32 ..][0..32];
        if (r[0] == 0) return null; // the directory's end
        slot.* += 1;
        if (r[0] == 0xE5 or r[11] == 0x0F or r[11] & fat.ATTR_VOLUME != 0 or r[0] == '.') continue;
        stamp = .{ std.mem.readInt(u16, r[22..24], .little), std.mem.readInt(u16, r[24..26], .little) };
        return @import("fat_entry.zig").entryOf(r);
    }
    return error.Corrupt; // a directory longer than the disk
}

/// The entry of `d` named `name` ("NAME.EXT" as fat_entry shows it, upper case), or null.
pub fn find(v: *fat.Volume, d: fat.Dir, name: []const u8) fat.Error!?fat.Entry {
    var slot: u32 = 0;
    while (try next(v, d, &slot)) |e| {
        if (eqlUpper(e.nameSlice(), name)) return e;
    }
    return null;
}

fn eqlUpper(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (upper(x) != upper(y)) return false;
    return true;
}

pub fn upper(c: u8) u8 {
    return if (c >= 'a' and c <= 'z') c - 32 else c;
}
