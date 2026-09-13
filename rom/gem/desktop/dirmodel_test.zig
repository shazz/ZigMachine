// Native tests for the directory model — `zig test rom/gem/desktop/dirmodel_test.zig`
// (listed in build.sh). The host packs the FAT; these pack it the same way.
const std = @import("std");
const dm = @import("dirmodel.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn pack(m: *dm.DirModel, i: usize, name: []const u8, kind: u8, size: u32, date: u32) void {
    const e = i * dm.FILE_ENT;
    @memset(m.disk_dir[e .. e + dm.FILE_ENT], 0);
    @memcpy(m.disk_dir[e .. e + name.len], name);
    m.disk_dir[e + 16] = kind;
    std.mem.writeInt(u32, m.disk_dir[e + 17 ..][0..4], size, .little);
    std.mem.writeInt(u32, m.disk_dir[e + 21 ..][0..4], date, .little);
}

fn disk() dm.DirModel {
    var m: dm.DirModel = .{};
    pack(&m, 0, "BETA.TXT", 1, 512, 20260101);
    pack(&m, 1, "ALPHA.PRG", 0, 12345, 20250101);
    pack(&m, 2, "GAMMA.DAT", 1, 40960, 20260912);
    m.n_disk = 3;
    return m;
}

fn expectOrder(m: *const dm.DirModel, sort: dm.SortKey, want: []const u8) !void {
    const o = m.order(sort);
    try std.testing.expectEqualSlices(u8, want, o[0..want.len]);
}

test "entry fields read back what the host packed" {
    const m = disk();
    try expectEqualStrings("ALPHA.PRG", m.name(1));
    try expectEqual(@as(u8, 0), m.kind(1));
    try expectEqual(@as(u32, 12345), m.size(1));
    try expectEqual(@as(u32, 20250101), m.date(1));
    try expectEqual(@as(u32, 512 + 12345 + 40960), m.usedBytes());
}

test "a 16-byte name with no NUL is read whole, not overrun into the type byte" {
    var m: dm.DirModel = .{};
    pack(&m, 0, "ABCDEFGHIJKLMNOP", 1, 0, 0);
    m.n_disk = 1;
    try expectEqualStrings("ABCDEFGHIJKLMNOP", m.name(0));
}

test "every sort key orders the disk, and name breaks the ties" {
    var m = disk();
    try expectOrder(&m, .name, &.{ 1, 0, 2 });
    try expectOrder(&m, .size, &.{ 2, 1, 0 }); // largest first
    try expectOrder(&m, .date, &.{ 2, 0, 1 }); // newest first
    try expectOrder(&m, .type, &.{ 1, 0, 2 }); // the program, then data by name
    pack(&m, 2, "AAA.DAT", 1, 512, 20260101); // ties BETA.TXT on size AND date
    try expectOrder(&m, .size, &.{ 1, 2, 0 });
    try expectOrder(&m, .date, &.{ 2, 0, 1 });
}

test "launchName: the named program, else the disk's first, else nothing" {
    const m = disk();
    try expectEqualStrings("ALPHA.PRG", m.launchName(1));
    try expectEqualStrings("ALPHA.PRG", m.launchName(0)); // a data file falls back
    try expectEqualStrings("ALPHA.PRG", m.launchName(-1)); // FLOPPY-as-launcher
    try expectEqualStrings("ALPHA.PRG", m.launchName(99)); // out of range falls back
    var none = disk();
    none.n_disk = 0;
    try expectEqual(@as(usize, 0), none.launchName(-1).len);
}

test "put adds a data file, then updates it in place" {
    var m = disk();
    try expect(m.put("DESKTOP.INF", 100));
    try expectEqual(@as(u8, 4), m.n_disk);
    try expect(m.put("DESKTOP.INF", 200));
    try expectEqual(@as(u8, 4), m.n_disk);
    try expectEqual(@as(u32, 200), m.size(3));
    try expectEqual(@as(u8, 1), m.kind(3));
}

test "put refuses a new file when the directory is full" {
    var m = disk();
    m.n_disk = dm.MAX_FILES;
    try expect(!m.put("NEW.INF", 1));
    try expectEqual(@as(u8, dm.MAX_FILES), m.n_disk);
}

test "remove closes the gap; removing from an empty disk is a no-op" {
    var m = disk();
    m.remove(0);
    try expectEqual(@as(u8, 2), m.n_disk);
    try expectEqualStrings("ALPHA.PRG", m.name(0));
    try expectEqualStrings("GAMMA.DAT", m.name(1));
    var empty: dm.DirModel = .{};
    empty.remove(0);
    try expectEqual(@as(u8, 0), empty.n_disk);
}

test "renameFile rewrites the name field and leaves the rest of the entry" {
    var m = disk();
    m.renameFile(2, "G.DAT");
    try expectEqualStrings("G.DAT", m.name(2));
    try expectEqual(@as(u32, 40960), m.size(2));
}

test "folders: auto-name, typed name, nested titles, per-directory counts" {
    var m: dm.DirModel = .{};
    m.addFolder(dm.ROOT, "");
    m.addFolder(dm.ROOT, "WORK");
    m.addFolder(1, "SRC");
    try expectEqualStrings("NEWDIR1", m.folderName(0));
    try expectEqualStrings("A:\\WORK\\SRC", m.folders[2].title[0..m.folders[2].tlen]);
    try expectEqual(@as(usize, 2), m.folderCount(dm.ROOT));
    try expectEqual(@as(usize, 1), m.folderCount(1));
    try expectEqual(@as(u8, 1), m.nthFolder(dm.ROOT, 1));
    try expectEqual(@as(u8, 2), m.nthFolder(1, 0));
    try expectEqual(@as(usize, 0), m.fileCount(1)); // disk files live only at root
}

test "addFolder cuts a long name to 12 and is a no-op when full" {
    var m: dm.DirModel = .{};
    m.addFolder(dm.ROOT, "ABCDEFGHIJKLMNOPQ");
    try expectEqualStrings("ABCDEFGHIJKL", m.folderName(0));
    m.n_folders = dm.MAX_FOLDERS;
    m.addFolder(dm.ROOT, "X");
    try expectEqual(@as(u8, dm.MAX_FOLDERS), m.n_folders);
}

test "renameFolder rebuilds its window title" {
    var m: dm.DirModel = .{};
    m.addFolder(dm.ROOT, "OLD");
    m.renameFolder(0, "NEW");
    try expectEqualStrings("A:\\NEW", m.folders[0].title[0..m.folders[0].tlen]);
}
