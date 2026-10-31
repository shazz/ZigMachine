// --------------------------------------------------------------------------
// The desktop shell's FAT disk (KOS, docs/KOS_FAT.md): when the host says drive A holds a FAT
// image (insertDisk(2): a real floppy, an .ST), the shell reads it through the drive
// (zg.readBlock, the same diskReadBlock every cart has) with KOS's reader (rom/kos/fat.zig) and
// fills the ROM's desktop model: the folders (deskFatFolder) and every file with its folder
// (deskDirPtr's records, the folder byte at +25). Once per insertion. No host packs a listing
// for such a disk, and no host or ROM import is new: browser, native host and board run this
// same wasm.
//
// Limits are the desktop's: MAX_FILES files and MAX_FOLDERS folders over the whole disk, read
// breadth first (the root, then each folder), the rest left out.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const rom = @import("rom_sdk");
const fat = @import("kos_fat");

const MAX_FOLDERS = 16; // rom/gem/desktop/dirmodel.zig MAX_FOLDERS

fn read(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    return zg.readBlock(n, dst) == fat.SECTOR;
}

var vol: fat.Volume = undefined;
var entries: [32]fat.Entry = undefined;

/// Fill the desktop's model from drive A's FAT disk; false if it does not mount (the window then
/// shows an empty disk).
pub fn load() bool {
    var dummy: u8 = 0;
    rom.Desktop.fatReset();
    vol = fat.Volume.mount(read, &dummy) catch return false;
    const ent = rom.deskDirEntryBytes();
    const cap = rom.deskDirMaxFiles();
    const recs = rom.Desktop.dirPtr();
    var clusters: [MAX_FOLDERS]u32 = undefined;
    var n_folders: usize = 0;
    var files: u32 = 0;
    var q: isize = -1; // the directory being read: -1 the root, else a folder index
    while (q < @as(isize, @intCast(n_folders))) : (q += 1) {
        const dir: fat.Dir = if (q < 0) vol.root() else .{ .cluster = clusters[@intCast(q)] };
        const n = vol.list(dir, &entries) catch 0;
        for (entries[0..n]) |*e| {
            if (e.isDir()) {
                const f = rom.Desktop.fatFolder(@intCast(q), e.nameSlice(), e.cluster) orelse continue;
                clusters[f] = e.cluster;
                n_folders = @max(n_folders, @as(usize, f) + 1);
            } else if (files < cap) {
                record(recs[files * ent ..][0..ent], e, q);
                files += 1;
            }
        }
    }
    rom.Desktop.setFileCount(files);
    return true;
}

/// One file's record, as dirmodel.zig reads it: name, type (0 a program: .WSM), size, date, folder + 1.
fn record(r: []u8, e: *const fat.Entry, folder: isize) void {
    @memset(r, 0);
    @memcpy(r[0..e.name_len], e.nameSlice());
    r[16] = if (std.mem.endsWith(u8, e.nameSlice(), ".WSM")) 0 else 1;
    std.mem.writeInt(u32, r[17..21], e.size, .little);
    std.mem.writeInt(u32, r[21..25], e.date, .little);
    if (r.len > 25) r[25] = @intCast(folder + 1);
}
