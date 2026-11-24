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
