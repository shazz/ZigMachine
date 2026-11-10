// --------------------------------------------------------------------------
// The shell's file operations (gem_fileop.zig): a GEMDOS path that grows by a name as the walk
// goes down a folder and is cut back as it comes up, and the GEMDOS calls the walk and the
// count share (an entry's attributes through a scratch DTA, the "." / ".." / temp-file filter).
// --------------------------------------------------------------------------
const std = @import("std");
const gemdos = @import("kos_gemdos");
const op = @import("rom_sdk").deskop;

pub const FA_DIR: u8 = 0x10;
pub const ANY: i32 = 0x16; // folders, hidden and system files too: everything a copy carries

pub const Path = struct {
    buf: [op.PATH_MAX]u8 = undefined,
    len: usize = 0,

    pub fn set(p: *Path, s: []const u8) void {
        const n = @min(s.len, op.PATH_MAX);
        @memcpy(p.buf[0..n], s[0..n]);
        p.len = n;
    }
    pub fn str(p: *const Path) []const u8 {
        return p.buf[0..p.len];
    }
    /// `name` appended (`sep`: and a '\', a folder to go into); false when the path would not fit.
    pub fn push(p: *Path, name: []const u8, sep: bool) bool {
        const extra = name.len + @intFromBool(sep);
        if (p.len + extra >= op.PATH_MAX) return false;
        @memcpy(p.buf[p.len..][0..name.len], name);
        if (sep) p.buf[p.len + name.len] = '\\';
        p.len += extra;
        return true;
    }
};

/// What Fsfirst found for one path (an item, or the next entry of a folder).
pub const Entry = struct {
    name: [op.NAME_MAX]u8 = undefined,
    len: usize = 0,
    dir: bool = false,
    size: u32 = 0,

    pub fn slice(e: *const Entry) []const u8 {
        return e.name[0..e.len];
    }
    pub fn of(t: *const gemdos.Dta) Entry {
        var e = Entry{ .dir = t.attrib & FA_DIR != 0, .size = std.mem.readInt(u32, &t.length, .little) };
        e.len = std.mem.indexOfScalar(u8, &t.name, 0) orelse t.name.len;
        @memcpy(e.name[0..e.len], t.name[0..e.len]);
        return e;
    }
};

/// The walk skips a folder's "." and "..", and a save's temporary file (KOS_GEMDOS_WRITES §2).
pub fn skipped(t: *const gemdos.Dta) bool {
    return t.name[0] == '.' or std.mem.startsWith(u8, &t.name, "~KOS");
}

var scratch: gemdos.Dta = .{};

/// The entry at `path` (file or folder), or null (GEMDOS's error in `code`).
pub fn stat(path: []const u8, code: *i32) ?Entry {
    const dos = gemdos.dos();
    dos.Fsetdta(&scratch);
    code.* = dos.Fsfirst(path, ANY);
    return if (code.* == 0) Entry.of(&scratch) else null;
}

/// Something is at `path`.
pub fn exists(path: []const u8) bool {
    var code: i32 = 0;
    return stat(path, &code) != null;
}
