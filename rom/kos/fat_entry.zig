// A FAT directory entry as GEMDOS shows it (fat.zig): the 8.3 name, the attributes, the size,
// the first cluster, the DOS date as the desktop's YYYYMMDD.
const std = @import("std");

pub const ATTR_DIR: u8 = 0x10;
pub const ATTR_VOLUME: u8 = 0x08;
pub const ATTR_LFN: u8 = 0x0F;

/// A directory entry, as GEMDOS shows it.
pub const Entry = struct {
    name: [12]u8 = [_]u8{0} ** 12, // "NAME.EXT", NUL-padded
    name_len: u8 = 0,
    attr: u8 = 0,
    size: u32 = 0,
    cluster: u32 = 0,
    date: u32 = 0, // YYYYMMDD, the desktop's stamp (0: none)

    pub fn isDir(self: *const Entry) bool {
        return self.attr & ATTR_DIR != 0;
    }
    pub fn nameSlice(self: *const Entry) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub fn entryOf(r: *const [32]u8) Entry {
    var e = Entry{ .attr = r[11], .size = le32(r, 28) };
    e.cluster = le16(r, 26) | @as(u32, le16(r, 20)) << 16;
    var n: usize = 0;
    for (r[0..8]) |ch| if (ch != ' ') {
        e.name[n] = if (n == 0 and ch == 0x05) 0xE5 else ch; // 05: a name that starts with E5
        n += 1;
    };
    if (r[8] != ' ') {
        e.name[n] = '.';
        n += 1;
        for (r[8..11]) |ch| if (ch != ' ') {
            e.name[n] = ch;
            n += 1;
        };
    }
    e.name_len = @intCast(n);
    const d = le16(r, 24); // DOS date: year-1980 << 9 | month << 5 | day
    if (d != 0) e.date = (1980 + @as(u32, d >> 9)) * 10000 + @as(u32, (d >> 5) & 15) * 100 + (d & 31);
    return e;
}

pub fn le16(b: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, b[at..][0..2], .little);
}
pub fn le32(b: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, b[at..][0..4], .little);
}
