// --------------------------------------------------------------------------
// The names of SID-WIZARD Z's files, pure: what GEMDOS can hold and what the file dialog lists.
// --------------------------------------------------------------------------
const std = @import("std");
const filer = @import("filer.zig");

/// A file name as the dialog holds it ("MYSONG.SWM"): 8.3, no folder, no wildcard, nothing below a space.
pub fn valid(name: []const u8) bool {
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return false;
    if (dot == 0 or dot > 8 or name.len - dot - 1 != 3) return false;
    for (name) |c| if (c == '\\' or c == '/' or c == ':' or c == '*' or c == '?' or c <= ' ') return false;
    return true;
}

/// Add `file` ("NAME.SWM") to the listing when it has the extension and is not there yet (C: is listed
/// first, so it shadows the floppy's file of the same name). Returns the new count; a full page adds nothing.
pub fn addEntry(out: *[filer.max_files]filer.Entry, n: usize, file: []const u8, ext: []const u8) usize {
    const dot = std.mem.lastIndexOfScalar(u8, file, '.') orelse return n;
    if (n >= out.len or dot == 0 or dot > filer.max_name or !std.ascii.eqlIgnoreCase(file[dot..], ext)) return n;
    for (out[0..n]) |e| if (std.ascii.eqlIgnoreCase(e.name[0..e.len], file[0..dot])) return n;
    out[n] = .{};
    for (file[0..dot], 0..) |c, i| out[n].name[i] = std.ascii.toUpper(c);
    out[n].len = @intCast(dot);
    return n + 1;
}

/// The mark the C editor's emulator hosts put before a folder's name in a listing (SWEMU_FOLDER_CHAR).
pub const FOLDER: u8 = 0x7F;

/// Add the folder `name` ("MUSIC", "..") to the listing as its folder entry (FOLDER + the name).
pub fn addFolder(out: *[filer.max_files]filer.Entry, n: usize, name: []const u8) usize {
    if (n >= out.len or name.len == 0 or name.len + 1 > filer.max_name) return n;
    out[n] = .{};
    out[n].name[0] = FOLDER;
    for (name, 0..) |c, i| out[n].name[i + 1] = std.ascii.toUpper(c);
    out[n].len = @intCast(name.len + 1);
    return n + 1;
}

/// Where the file dialog is: the floppy's root (read-only), or a folder of C: (the KOS GEMDOS drive).
pub const Cwd = struct {
    on_c: bool = false,
    buf: [48]u8 = undefined, // the folders under C:\ joined by backslashes: "MUSIC\SIDS"
    len: u8 = 0,

    /// Go into folder `name` (a floppy's root has one: "C", the other drive). False: refused.
    pub fn enter(self: *Cwd, name: []const u8) bool {
        if (!self.on_c) {
            if (!std.ascii.eqlIgnoreCase(name, "C")) return false;
            self.on_c = true;
            self.len = 0;
            return true;
        }
        const add = name.len + @intFromBool(self.len > 0);
        if (name.len == 0 or self.len + add > self.buf.len) return false;
        if (self.len > 0) {
            self.buf[self.len] = '\\';
            self.len += 1;
        }
        for (name) |c| {
            self.buf[self.len] = std.ascii.toUpper(c);
            self.len += 1;
        }
        return true;
    }

    /// "..": one folder up; from C:'s root back to the floppy.
    pub fn up(self: *Cwd) void {
        if (!self.on_c) return;
        if (self.len == 0) {
            self.on_c = false;
            return;
        }
        const cut = std.mem.lastIndexOfScalar(u8, self.buf[0..self.len], '\\');
        self.len = if (cut) |c| @intCast(c) else 0;
    }

    /// `C:\MUSIC\NAME` into `out`; `name` empty: the folder itself (a search path's base).
    pub fn path(self: *const Cwd, out: []u8, name: []const u8) ?[]u8 {
        const sep: []const u8 = if (self.len > 0 and name.len > 0) "\\" else "";
        return std.fmt.bufPrint(out, "C:\\{s}{s}{s}", .{ self.buf[0..self.len], sep, name }) catch null;
    }

    /// The dialog's "DR:" text: "A:\" for the floppy, "C:\MUSIC" on C:.
    pub fn label(self: *const Cwd, out: []u8) []u8 {
        if (!self.on_c) return std.fmt.bufPrint(out, "A:\\", .{}) catch out[0..0];
        return std.fmt.bufPrint(out, "C:\\{s}", .{self.buf[0..self.len]}) catch out[0..0];
    }
};

test "Cwd: the floppy's C folder opens C:, folders nest, .. climbs back to the floppy" {
    var c: Cwd = .{};
    try std.testing.expect(!c.enter("MUSIC")); // the floppy has no such folder
    try std.testing.expect(c.enter("C"));
    try std.testing.expect(c.enter("music"));
    try std.testing.expect(c.enter("SIDS"));
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("C:\\MUSIC\\SIDS\\TUNE.SWM", c.path(&b, "TUNE.SWM").?);
    try std.testing.expectEqualStrings("C:\\MUSIC\\SIDS", c.label(&b));
    c.up();
    try std.testing.expectEqualStrings("C:\\MUSIC\\X.SWM", c.path(&b, "X.SWM").?);
    c.up();
    try std.testing.expectEqualStrings("C:\\X.SWM", c.path(&b, "X.SWM").?);
    c.up();
    try std.testing.expect(!c.on_c);
    try std.testing.expectEqualStrings("A:\\", c.label(&b));
}

test "Cwd refuses a path that does not fit" {
    var c: Cwd = .{ .on_c = true };
    try std.testing.expect(c.enter("ABCDEFGHIJK"));
    try std.testing.expect(c.enter("ABCDEFGHIJK"));
    try std.testing.expect(c.enter("ABCDEFGHIJK"));
    try std.testing.expect(c.enter("ABCDEFGHIJK"));
    try std.testing.expect(!c.enter("ABCDEFGHIJK"));
}

test "addFolder marks a folder entry and refuses a too long name" {
    var out: [filer.max_files]filer.Entry = undefined;
    var n = addFolder(&out, 0, "music");
    n = addFolder(&out, n, "ABCDEFGHIJKL"); // 12 + the mark: 13 > 12
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(FOLDER, out[0].name[0]);
    try std.testing.expectEqualStrings("MUSIC", out[0].name[1..out[0].len]);
}

test "valid: 8.3 with a dot, no path or wildcard characters" {
    try std.testing.expect(valid("MYSONG.SWM"));
    try std.testing.expect(valid("A.SWM"));
    try std.testing.expect(!valid("TOOLONGNAME.SWM"));
    try std.testing.expect(!valid("NOEXT"));
    try std.testing.expect(!valid("A\\B.SWM"));
    try std.testing.expect(!valid("A*.SWM"));
    try std.testing.expect(!valid(".SWM"));
    try std.testing.expect(!valid("AB.SWMX"));
}

test "addEntry lists by extension, once, upper case, without the extension" {
    var out: [filer.max_files]filer.Entry = undefined;
    var n = addEntry(&out, 0, "song.swm", ".SWM");
    n = addEntry(&out, n, "SONG.SWM", ".SWM"); // the same name on the floppy: C: shadows it
    n = addEntry(&out, n, "NOTES.TXT", ".SWM");
    n = addEntry(&out, n, "B.SWM", ".SWM");
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("SONG", out[0].name[0..out[0].len]);
    try std.testing.expectEqualStrings("B", out[1].name[0..out[1].len]);
}

test "addEntry stops at a full page" {
    var out: [filer.max_files]filer.Entry = undefined;
    try std.testing.expectEqual(@as(usize, filer.max_files), addEntry(&out, filer.max_files, "X.SWM", ".SWM"));
}
