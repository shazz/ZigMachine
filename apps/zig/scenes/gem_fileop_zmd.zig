// --------------------------------------------------------------------------
// Drive A as a .zmd data disk, for the shell's file operations (gem_fileop.zig). The desktop
// lists a .zmd's files (the host hands the listing: insertDisk(1)), but KOS GEMDOS does not mount
// A: over one (no BPB, docs/KOS_GEMDOS.md §3), so a copy out of it went to GEMDOS and stopped at
// EDRIVE: "The disk cannot be read" (Matt on the board, 13 Nov: BOOT.WSM onto C:\GEMTESTS). A
// source on A: while the drive holds a .zmd is read here instead, through the disk's own flat
// directory (zg.disk, the reader every cart has); a FAT floppy still goes through GEMDOS. A .zmd
// has no folders, and nothing is ever written to it (a move keeps its source: write-protected).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const gemdos = @import("kos_gemdos");
const fp = @import("gem_fileop_path.zig");
const err = gemdos.err;

/// `path` is on drive A and the drive holds a .zmd (the disk's ZMDISK descriptor answers).
pub fn owns(path: []const u8) bool {
    if (path.len < 2 or path[1] != ':' or (path[0] | 0x20) != 'a') return false;
    return zg.disk.mount() != null;
}

/// The file `path` ("A:\NAME") names on the .zmd, or GEMDOS's error in `code`.
fn find(path: []const u8, code: *i32) ?zg.disk.Entry {
    code.* = err.EFILNF;
    if (path.len < 4 or path[2] != '\\') return null; // the desktop always spells "A:\NAME"
    const name = path[3..];
    for (name) |c| if (c == '\\') {
        code.* = err.EPTHNF; // a .zmd has no folders
        return null;
    };
    const lay = zg.disk.mount() orelse return null;
    const e = zg.disk.find(lay, name) orelse return null;
    code.* = 0;
    return e;
}

/// fp.stat's answer for a .zmd file.
pub fn stat(path: []const u8, code: *i32) ?fp.Entry {
    const e = find(path, code) orelse return null;
    var out = fp.Entry{ .size = e.len };
    const name = path[3..]; // find() took "A:\NAME"
    out.len = @min(name.len, out.name.len);
    @memcpy(out.name[0..out.len], name[0..out.len]);
    return out;
}

var file: zg.disk.Entry = .{ .start = 0, .len = 0, .kind = 0 };
var pos: u32 = 0;

/// The file being copied: 0, or GEMDOS's error.
pub fn open(path: []const u8) i32 {
    var code: i32 = 0;
    file = find(path, &code) orelse return code;
    pos = 0;
    return 0;
}

/// Its next bytes into `dst` (Fread's answer: the count, 0 at the end, EREADF if the drive ran out).
pub fn read(dst: []u8) i32 {
    const want: u32 = @intCast(@min(dst.len, file.len - pos));
    if (want == 0) return 0;
    const rest = zg.disk.Entry{ .start = file.start + pos, .len = want, .kind = file.kind };
    const got: u32 = @intCast(zg.disk.read(rest, dst[0..want]));
    if (got != want) return err.EREADF;
    pos += got;
    return @intCast(got);
}
