// A screenshot onto the card (app_shot.zig): <card>/screenshots/SHOTnnnn.PNG, 8.3 names, the next
// number after the highest already there (gaps are left alone), and never one that exists: past
// SHOT9999 the lowest free number, then error.Full. Written as SHOTnnnn.TMP and renamed, so a
// power cut leaves no half PNG under a real name. The caller makes the card writable around it.
const std = @import("std");

pub const DIR = "screenshots";
pub const MAX: u16 = 9999;
pub const NAME_LEN = "SHOT0000.PNG".len;

pub const Error = error{ NoCard, Full, ReadOnly, CardFull, WriteFailed };

/// "SHOT0007.PNG" for 7 (`ext` "PNG" or "TMP").
pub fn name(n: u16, ext: *const [3]u8) [NAME_LEN]u8 {
    var out: [NAME_LEN]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "SHOT{d:0>4}.{s}", .{ n, ext }) catch unreachable;
    return out;
}

/// The number of a SHOTnnnn.PNG (any case: a card written elsewhere), or null.
pub fn number(entry: []const u8) ?u16 {
    if (entry.len != NAME_LEN or !std.ascii.startsWithIgnoreCase(entry, "SHOT")) return null;
    if (!std.ascii.endsWithIgnoreCase(entry, ".PNG")) return null;
    for (entry[4..8]) |c| if (!std.ascii.isDigit(c)) return null; // parseInt would take "+012"
    const n = std.fmt.parseInt(u16, entry[4..8], 10) catch return null;
    return if (n >= 1 and n <= MAX) n else null;
}

/// The numbers taken, then the one to use.
pub const Picker = struct {
    taken: std.StaticBitSet(MAX + 1) = .initEmpty(),
    high: u16 = 0,

    pub fn seen(p: *Picker, entry: []const u8) void {
        const n = number(entry) orelse return;
        p.taken.set(n);
        p.high = @max(p.high, n);
    }

    pub fn pick(p: *const Picker) error{Full}!u16 {
        if (p.high < MAX) return p.high + 1;
        for (1..MAX + 1) |n| if (!p.taken.isSet(n)) return @intCast(n);
        return error.Full;
    }
};

/// Write `png` as the next SHOTnnnn.PNG under `card`/screenshots (made if missing); its number.
pub fn save(io: std.Io, card: []const u8, png: []const u8) Error!u16 {
    var root = std.Io.Dir.cwd().openDir(io, card, .{}) catch return error.NoCard;
    defer root.close(io);
    var dir = root.createDirPathOpen(io, DIR, .{ .open_options = .{ .iterate = true } }) catch |e| return fsError(e);
    defer dir.close(io);
    var p = Picker{};
    var it = dir.iterate();
    while (it.next(io) catch |e| return fsError(e)) |e| p.seen(e.name);
    const n = try p.pick();
    const tmp = name(n, "TMP");
    const final = name(n, "PNG");
    dir.writeFile(io, .{ .sub_path = &tmp, .data = png }) catch |e| {
        dir.deleteFile(io, &tmp) catch {};
        return fsError(e);
    };
    dir.rename(&tmp, dir, &final, io) catch |e| {
        dir.deleteFile(io, &tmp) catch {};
        return fsError(e);
    };
    return n;
}

/// What the OSD can say: the card read-only, full, or any other failure.
fn fsError(e: anyerror) Error {
    std.log.warn("screenshot: {t}", .{e});
    return switch (e) {
        error.ReadOnlyFileSystem, error.AccessDenied, error.PermissionDenied => error.ReadOnly,
        error.NoSpaceLeft, error.DiskQuota => error.CardFull,
        else => error.WriteFailed,
    };
}
