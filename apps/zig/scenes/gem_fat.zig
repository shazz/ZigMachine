// --------------------------------------------------------------------------
// The desktop shell's FAT drives (KOS, docs/KOS_FAT.md): when the host says drive A holds a FAT
// image (insertDisk(2): a real floppy, an .ST), the shell reads it through the drive
// (zg.readBlock, the same diskReadBlock every cart has) with KOS's reader (rom/kos/fat.zig) and
// fills the ROM's desktop model: the folders and every file with its folder (the records, the
// folder byte at +25). Once per insertion. C: (F5), the SD card, is read the same way through
// the cart's own env.kosDriveRead, once at the shell's start, into C:'s model; its files are
// data (nothing on C: launches in v1).
//
// Limits are the desktop's: MAX_FILES files and MAX_FOLDERS folders over the whole disk, read
// breadth first (the root, then each folder), the rest left out.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const rom = @import("rom_sdk");
const fat = @import("kos_fat");

const MAX_FOLDERS = 16; // rom/gem/desktop/dirmodel.zig MAX_FOLDERS
pub const UNIT_A: u32 = 0;
pub const UNIT_C: u32 = 2;

/// KOS's C: (docs/KOS_FAT.md F5): `count` sectors of `unit` into memory at `dst` (word-aligned);
/// the sectors read, 0 for none. Served by every host (sealed-loader.js, host/disk.h, the board's
/// glass), never by the ROM.
extern fn kosDriveRead(unit: u32, sector: u32, count: u32, dst: u32) u32;

fn readA(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    return zg.readBlock(n, dst) == fat.SECTOR;
}

var c_sector: [fat.SECTOR]u8 align(4) = undefined;
fn readC(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    if (kosDriveRead(UNIT_C, n, 1, @intCast(@intFromPtr(&c_sector))) != 1) return false;
    dst.* = c_sector;
    return true;
}

var vol: fat.Volume = undefined;
var entries: [32]fat.Entry = undefined;

/// Fill drive A's model from its FAT disk; false if it does not mount (an empty disk shows).
pub fn load() bool {
    return loadUnit(UNIT_A, readA);
}

/// Fill C:'s model from the SD card, and show its icon only if it mounted.
pub fn loadC() bool {
    const ok = loadUnit(UNIT_C, readC);
    rom.Desktop.setDriveC(ok);
    return ok;
}

fn loadUnit(unit: u32, read: fat.ReadFn) bool {
    var dummy: u8 = 0;
    rom.Desktop.driveReset(unit);
    vol = fat.Volume.mount(read, &dummy) catch return false;
    const ent = rom.deskDirEntryBytes();
    const cap = rom.deskDirMaxFiles();
    const recs = rom.Desktop.driveDirPtr(unit);
    var clusters: [MAX_FOLDERS]u32 = undefined;
    var n_folders: usize = 0;
    var files: u32 = 0;
    var q: isize = -1; // the directory being read: -1 the root, else a folder index
    while (q < @as(isize, @intCast(n_folders))) : (q += 1) {
        const dir: fat.Dir = if (q < 0) vol.root() else .{ .cluster = clusters[@intCast(q)] };
        const n = vol.list(dir, &entries) catch 0;
        for (entries[0..n]) |*e| {
            if (e.isDir()) {
                const f = rom.Desktop.driveFolder(unit, @intCast(q), e.nameSlice(), e.cluster) orelse continue;
                clusters[f] = e.cluster;
                n_folders = @max(n_folders, @as(usize, f) + 1);
            } else if (files < cap) {
                record(recs[files * ent ..][0..ent], e, q, unit == UNIT_A);
                files += 1;
            }
        }
    }
    rom.Desktop.driveSetFileCount(unit, files);
    return true;
}

/// One file's record, as dirmodel.zig reads it: name, type (0 a program: .WSM, on drive A only),
/// size, date, folder + 1.
fn record(r: []u8, e: *const fat.Entry, folder: isize, programs: bool) void {
    @memset(r, 0);
    @memcpy(r[0..e.name_len], e.nameSlice());
    r[16] = if (programs and std.mem.endsWith(u8, e.nameSlice(), ".WSM")) 0 else 1;
    std.mem.writeInt(u32, r[17..21], e.size, .little);
    std.mem.writeInt(u32, r[21..25], e.date, .little);
    if (r.len > 25) r[25] = @intCast(folder + 1);
}
