// --------------------------------------------------------------------------
// The host's check of a C: path a cart sent with a write (kfs_abi.zig): the one gate between a cart
// and the card. glass (fpga/glass/src/kos_file.zig) and the image writer (kfs.zig) both run it on
// THEIR OWN copy of the bytes, before anything touches a disk. A path is relative to C:\ (/HD),
// names joined by `\`, each a plain 8.3 name in upper case: so no `..` or `.`, no leading `\` or
// drive (nothing absolute), no `/`, no empty name, no device-like or control characters, and at most
// MAX_NAMES deep. Anything else is refused whole: there is no "cleaning" of a bad path.
// --------------------------------------------------------------------------
const std = @import("std");
const abi = @import("kfs_abi.zig");

pub const MAX_NAMES = 9; // 8 folders below C:\ (docs/KOS_GEMDOS.md §3) and a name

pub const Path = struct {
    names: [MAX_NAMES][]const u8 = undefined,
    n: usize = 0,

    pub fn slice(p: *const Path) []const []const u8 {
        return p.names[0..p.n];
    }
    pub fn last(p: *const Path) []const u8 {
        return p.names[p.n - 1];
    }
    pub fn parent(p: *const Path) []const []const u8 {
        return p.names[0 .. p.n - 1];
    }
};

/// `s` split into its names, or null if any of it is not a plain C: path.
pub fn check(s: []const u8) ?Path {
    if (s.len == 0 or s.len > abi.PATH_MAX) return null;
    var p = Path{};
    var it = std.mem.splitScalar(u8, s, '\\');
    while (it.next()) |name| {
        if (!validName(name) or p.n == MAX_NAMES) return null;
        p.names[p.n] = name;
        p.n += 1;
    }
    return p;
}

/// An 8.3 name as FAT stores it (upper case, the base 1..8 bytes, an extension 0..3 after one dot).
pub fn validName(name: []const u8) bool {
    const dot = std.mem.indexOfScalar(u8, name, '.');
    const base = if (dot) |d| name[0..d] else name;
    const ext = if (dot) |d| name[d + 1 ..] else "";
    if (base.len == 0 or base.len > 8 or ext.len > 3) return false;
    if (dot != null and ext.len == 0) return false; // "NAME." is no FAT name
    for (base) |c| if (!validChar(c)) return false;
    for (ext) |c| if (!validChar(c)) return false;
    return true;
}

/// FAT's short-name characters, upper case: letters, digits and DOS's punctuation; never a
/// separator, a wildcard, a space, a lower-case letter or a control byte.
pub fn validChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', '0'...'9' => true,
        '!', '#', '$', '%', '&', '\'', '(', ')', '-', '@', '^', '_', '`', '{', '}', '~' => true,
        else => false,
    };
}

/// True if folder path `a` is `b` or one of b's ancestors (a folder renamed into itself).
pub fn isPrefix(a: []const []const u8, b: []const []const u8) bool {
    if (a.len > b.len) return false;
    for (a, b[0..a.len]) |x, y| if (!std.mem.eql(u8, x, y)) return false;
    return true;
}

test "plain C: paths pass, split into their names" {
    const p = check("PICTURES\\PLASMA\\NEW.PI1").?;
    try std.testing.expectEqual(@as(usize, 3), p.n);
    try std.testing.expectEqualStrings("NEW.PI1", p.last());
    try std.testing.expect(check("A") != null);
    try std.testing.expect(check("~KOS0.TMP") != null);
    try std.testing.expect(check("A\\B\\C\\D\\E\\F\\G\\H\\X.Y") != null); // 8 folders deep
}

test "every escape and every odd name is refused" {
    const bad = [_][]const u8{
        "",                             "..",    ".",   "..\\X", "A\\..\\..\\X", "\\X",   "\\",   "X\\",         "A\\\\B", "/X",    "A/B",    "C:\\X",
        "C:X",                          "x.pi1", "A B", "A*",    "A?",           "NAME.", ".PI1", "TOOLONGNAME", "A.TOOL", "A.B.C", "A\x00B", "A\nB",
        "A\\B\\C\\D\\E\\F\\G\\H\\I\\X", "A:",    "<>",  "A|B",   "A\"B",         "\xE5X",
    };
    for (bad) |s| {
        if (check(s) != null) {
            std.debug.print("accepted: {s}\n", .{s});
            return error.Accepted;
        }
    }
    var long: [abi.PATH_MAX + 1]u8 = undefined;
    @memset(&long, 'A');
    for (0..long.len / 9) |i| long[i * 9 + 8] = '\\';
    try std.testing.expect(check(&long) == null);
}

test "a folder is its own prefix and its parent's" {
    const a = check("A\\B").?;
    const b = check("A\\B\\C").?;
    try std.testing.expect(isPrefix(a.slice(), b.slice()));
    try std.testing.expect(isPrefix(a.slice(), a.slice()));
    try std.testing.expect(!isPrefix(b.slice(), a.slice()));
}
