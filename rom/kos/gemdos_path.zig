// --------------------------------------------------------------------------
// GEMDOS paths (docs/KOS_GEMDOS.md §3): `C:\FOLDER\FILE.EXT`, `\` or `/` between names (TOS takes
// both), a drive letter or the current drive, absolute from the drive's root or relative to its
// current folder. `.` and `..` are resolved here, by name, never by following a folder's `..` entry
// (so `..` at the root stays at the root, as TOS does). Names are 8.3, upper case; a longer name is
// cut to 8.3 as TOS cuts it. `*` and `?` make a pattern (Fsfirst): `*` fills the rest of its field.
// --------------------------------------------------------------------------
const std = @import("std");
const upper = @import("fat_dir.zig").upper;

pub const MAX_DEPTH = 8; // folders below a drive's root (docs/KOS_FAT.md §2)
pub const NO_DRIVE: u8 = 0xFF;

/// A name in a directory entry's own form: 8 + 3 bytes, space padded, upper case.
pub const Fcb = [11]u8;

pub const Path = struct {
    drive: u8 = NO_DRIVE, // 0 A: .. 25 Z:; NO_DRIVE: none given (the current one)
    absolute: bool = false, // from the drive's root, else from its current folder
    names: [MAX_DEPTH + 1]Fcb = undefined,
    n: u8 = 0,
    up: u8 = 0, // leading `..` of a relative path, applied to the current folder first

    pub fn slice(p: *const Path) []const Fcb {
        return p.names[0..p.n];
    }
};

pub const Error = error{ TooDeep, BadName };

/// Splits `s` into a drive, a root flag and the names, `.` and `..` resolved.
pub fn parse(s: []const u8) Error!Path {
    var p = Path{};
    var rest = s;
    if (rest.len >= 2 and rest[1] == ':') {
        const c = upper(rest[0]);
        if (c < 'A' or c > 'Z') return error.BadName;
        p.drive = c - 'A';
        rest = rest[2..];
    }
    if (rest.len > 0 and isSep(rest[0])) p.absolute = true;
    var it = std.mem.tokenizeAny(u8, rest, "\\/");
    while (it.next()) |name| {
        if (std.mem.eql(u8, name, ".")) continue;
        if (std.mem.eql(u8, name, "..")) {
            if (p.n > 0) p.n -= 1 else if (!p.absolute) p.up += 1;
            continue;
        }
        if (p.n == p.names.len) return error.TooDeep;
        p.names[p.n] = try fcb(name);
        p.n += 1;
    }
    return p;
}

fn isSep(c: u8) bool {
    return c == '\\' or c == '/';
}

/// "name.ext" in a directory entry's form; `*` fills the rest of its field with `?`.
pub fn fcb(name: []const u8) Error!Fcb {
    var out: Fcb = [_]u8{' '} ** 11;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.');
    const base = if (dot) |d| name[0..d] else name;
    const ext = if (dot) |d| name[d + 1 ..] else "";
    if (base.len == 0) return error.BadName;
    field(out[0..8], base);
    field(out[8..11], ext);
    return out;
}

fn field(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    for (src) |c| {
        if (i == dst.len) return; // cut, as TOS cuts a long name
        if (c == '*') {
            @memset(dst[i..], '?');
            return;
        }
        dst[i] = upper(c);
        i += 1;
    }
}

/// "NAME.EXT" (fat_entry's form) as an Fcb.
pub fn fcbOfEntry(name: []const u8) Fcb {
    return fcb(name) catch [_]u8{' '} ** 11;
}

pub fn hasWild(f: *const Fcb) bool {
    return std.mem.indexOfScalar(u8, f, '?') != null;
}

/// `pat` (with `?`) against a name, both in Fcb form.
pub fn matches(pat: *const Fcb, name: *const Fcb) bool {
    for (pat, name) |p, c| if (p != '?' and p != c) return false;
    return true;
}

/// "NAME.EXT" of an Fcb into `out`; its length.
pub fn show(f: *const Fcb, out: []u8) usize {
    var n: usize = 0;
    for (f[0..8]) |c| if (c != ' ') {
        out[n] = c;
        n += 1;
    };
    if (f[8] != ' ') {
        out[n] = '.';
        n += 1;
        for (f[8..11]) |c| if (c != ' ') {
            out[n] = c;
            n += 1;
        };
    }
    return n;
}
