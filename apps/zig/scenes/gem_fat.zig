// --------------------------------------------------------------------------
// The desktop shell's FAT drives (KOS, docs/KOS_FAT.md): when the host says drive A holds a FAT
// image (insertDisk(2): a real floppy, an .ST), the shell reads it through the drive
// (zg.readBlock, the same diskReadBlock every cart has) with KOS's reader (rom/kos/fat.zig) and
// fills the ROM's desktop model: the folders and every file with its folder (the records, the
// folder byte at +25). Once per insertion. C: (F5), the SD card, is read the same way through
// the cart's own env.kosDriveRead, once at the shell's start, into C:'s model; its files are
// data (nothing on C: launches in v1). C: is the card's HD folder, not the card (decisions.md
// 2026-11-06): glass serves the whole partition's sectors, and the walk starts at /HD's cluster,
// so nothing above it (the boot files, KESTREL/, CARTS/) is ever listed. A card with no /HD has no C:.
//
// Limits are the desktop's: MAX_FILES files and MAX_FOLDERS folders over the whole disk, read
// breadth first (the root, then each folder), the rest left out.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const rom = @import("rom_sdk");
const fat = @import("kos_gemdos").fat; // KOS's FAT reader (one module with GEMDOS: build.zig)

const MAX_FOLDERS = 16; // rom/gem/desktop/dirmodel.zig MAX_FOLDERS
pub const UNIT_A: u32 = 0;
pub const UNIT_C: u32 = 2;
/// The root folder C:\ is (fpga/glass/src/layout.zig HD), as FAT's 8.3 directory holds it.
pub const C_ROOT = "HD";

/// KOS's C: (docs/KOS_FAT.md F5): `count` sectors of `unit` into memory at `dst` (word-aligned);
/// the sectors read, 0 for none. Served by every host (sealed-loader.js, host/disk.h, the board's
/// glass), never by the ROM.
extern fn kosDriveRead(unit: u32, sector: u32, count: u32, dst: u32) u32;

/// KOS's system variables (rom/kos/kos.zig SysVars): drive_a's bits 31:8 count media changes.
extern fn kosSysVarsPtr() u32;
const DRIVE_A_WORD = 8; // SysVars.drive_a, the 9th u32
const DRIVE_CHANGES_SHIFT = 8;

/// Media changes in drive A since power-on: a new count is a new disk, even of the same kind.
pub fn mediaChanges() u32 {
    const p = kosSysVarsPtr();
    if (p == 0) return 0;
    const words: [*]const u32 = @ptrFromInt(p);
    return words[DRIVE_A_WORD] >> DRIVE_CHANGES_SHIFT;
}

fn readA(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    return zg.readBlock(n, dst) == fat.SECTOR;
}

// C: answers a request in one round trip to glass (~0.5 ms on the board: its thread polls at
// 2 kHz) whatever the count, so read RUN sectors at a time and serve the reader's next ones from
// them (a directory and the FAT are runs): the walk at start costs a few round trips, not one a sector.
const RUN = 8;
var c_run: [RUN * fat.SECTOR]u8 align(4) = undefined;
var c_first: u32 = 0;
var c_count: u32 = 0; // sectors held from c_first (0: none)
fn readC(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    if (n < c_first or n - c_first >= c_count) {
        c_count = 0;
        const at: u32 = @intCast(@intFromPtr(&c_run));
        var got = kosDriveRead(UNIT_C, n, RUN, at); // all or nothing: near the card's end, one at a time
        if (got != RUN) got = kosDriveRead(UNIT_C, n, 1, at);
        if (got == 0) return false;
        c_first = n;
        c_count = got;
    }
    dst.* = c_run[(n - c_first) * fat.SECTOR ..][0..fat.SECTOR].*;
    return true;
}

var vol: fat.Volume = undefined;
var entries: [32]fat.Entry = undefined;

/// Fill drive A's model from its FAT disk; false if it does not mount (an empty disk shows).
pub fn load() bool {
    return loadUnit(UNIT_A, readA, null);
}

/// Fill C:'s model from the SD card's /HD, and show its icon only if the card mounted and has one.
pub fn loadC() bool {
    c_count = 0; // a fresh walk reads the card afresh
    const ok = loadUnit(UNIT_C, readC, C_ROOT);
    rom.Desktop.setDriveC(ok);
    return ok;
}

/// `root`: the folder of the volume's root that is the drive's root (null: the volume's own); none, no drive.
fn loadUnit(unit: u32, read: fat.ReadFn, root: ?[]const u8) bool {
    var dummy: u8 = 0;
    rom.Desktop.driveReset(unit);
    vol = fat.Volume.mount(read, &dummy) catch return false;
    const top: fat.Dir = if (root) |name| folderOf(vol.root(), name) orelse return false else vol.root();
    const ent = rom.deskDirEntryBytes();
    const cap = rom.deskDirMaxFiles();
    const recs = rom.Desktop.driveDirPtr(unit);
    var clusters: [MAX_FOLDERS]u32 = undefined;
    var n_folders: usize = 0;
    var files: u32 = 0;
    var q: isize = -1; // the directory being read: -1 the root, else a folder index
    while (q < @as(isize, @intCast(n_folders))) : (q += 1) {
        const dir: fat.Dir = if (q < 0) top else .{ .cluster = clusters[@intCast(q)] };
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

/// The folder `name` in `dir`, or null. Cluster 0 would be FAT12/16's fixed root: refused.
/// The card's root is wider than a desktop listing (boot files, their .prev copies): its own buffer.
var top_entries: [128]fat.Entry = undefined;
fn folderOf(dir: fat.Dir, name: []const u8) ?fat.Dir {
    const n = vol.list(dir, &top_entries) catch return null;
    for (top_entries[0..n]) |*e| if (e.isDir() and e.cluster >= 2 and std.mem.eql(u8, e.nameSlice(), name)) return .{ .cluster = e.cluster };
    return null;
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
