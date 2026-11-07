// glass's C: writes (kos_file.zig, kos_fs.zig) over a test directory standing for the card's /HD, a
// sibling OUT standing for everything else on the card (KESTREL/, the boot files). Path traversal is
// the main risk: every escape a cart could send is refused, and OUT never changes. Then the operations
// TOS's way, and the request block as cycles/bkosfile.c writes it.
const std = @import("std");
const linux = std.os.linux;
const mc = @import("map_cart.zig");
const kf = @import("kos_file.zig");
const fs = @import("kos_fs.zig");
const t = std.testing;

const Card = struct {
    tmp: std.testing.TmpDir,
    hd: i32,
    out: i32,

    fn init() !Card {
        const tmp = std.testing.tmpDir(.{});
        const d = tmp.dir.handle;
        _ = linux.mkdirat(d, "HD", 0o755);
        _ = linux.mkdirat(d, "OUT", 0o755);
        _ = linux.mkdirat(d, "HD/PICS", 0o755);
        const hd: i32 = @intCast(linux.openat(d, "HD", .{ .DIRECTORY = true }, 0));
        const out: i32 = @intCast(linux.openat(d, "OUT", .{ .DIRECTORY = true }, 0));
        try put(out, "SYSTEM.RV3", "system");
        try put(hd, "PICS/OLD.PI1", "old picture");
        _ = linux.symlinkat("../OUT", hd, "LINK"); // FAT has none: a test plants one anyway
        return .{ .tmp = tmp, .hd = hd, .out = out };
    }
    fn deinit(c: *Card) void {
        _ = linux.close(c.hd);
        _ = linux.close(c.out);
        c.tmp.cleanup();
    }
    fn outsideUntouched(c: *Card) !void {
        var buf: [64]u8 = undefined;
        try t.expectEqualStrings("system", try get(c.out, "SYSTEM.RV3", &buf));
        var n: usize = 0;
        var d = try c.tmp.dir.openDir(t.io, "OUT", .{ .iterate = true });
        defer d.close(t.io);
        var it = d.iterate();
        while (try it.next(t.io)) |_| n += 1;
        try t.expectEqual(@as(usize, 1), n); // nothing new appeared outside HD
    }
};

fn put(dir: i32, name: [*:0]const u8, data: []const u8) !void {
    const fd: i32 = @intCast(linux.openat(dir, name, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644));
    defer _ = linux.close(fd);
    _ = linux.write(fd, data.ptr, data.len);
}

fn get(dir: i32, name: [*:0]const u8, buf: []u8) ![]const u8 {
    const rc = linux.openat(dir, name, .{}, 0);
    if (linux.errno(rc) != .SUCCESS) return error.FileNotFound;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    return buf[0..linux.read(fd, buf.ptr, buf.len)];
}

fn op(c: *Card, o: kf.Op, path: []const u8, path2: []const u8, flags: u32, data: []const u8) i32 {
    const r = kf.Req{ .op = o, .flags = flags, .slot = 0, .attr = 0, .offset = 0, .path = path, .path2 = path2, .data = data };
    return kf.run(c.hd, &r) catch |e| fs.code(e);
}

test "every escape from HD is refused, and nothing outside it changes" {
    var c = try Card.init();
    defer c.deinit();
    const escapes = [_][]const u8{
        "..\\OUT\\SYSTEM.RV3", "..",            "\\OUT\\X",    "C:\\X",     "/etc/passwd", "PICS/../../OUT/X", "PICS\\..\\..\\X",
        ".\\X",                "",              "PICS\\",      "\\",        "x.dat",       "A B",              "OUT\\..\\..",
        "LINK\\SYSTEM.RV3",    "LINK\\NEW.DAT", "PICS\\\x00X", "%2E%2E\\X",
    };
    for (escapes) |p| {
        for ([_]kf.Op{ .write, .delete, .mkdir, .rmdir, .setattr }) |o| {
            const r = op(&c, o, p, "", 3, "data");
            if (r >= 0) {
                std.debug.print("{t} \"{s}\": {d}\n", .{ o, p, r });
                return error.Escaped;
            }
        }
        try t.expect(op(&c, .rename, "PICS\\OLD.PI1", p, 0, "") < 0); // as a destination
        try t.expect(op(&c, .rename, p, "PICS\\X.PI1", 0, "") < 0); // as a source
    }
    try t.expectEqual(fs.EACCDN, op(&c, .delete, "LINK", "", 0, "")); // the link itself is no file
    try t.expectEqual(fs.EACCDN, op(&c, .write, "LINK", "", 3, "x")); // never written through
    try t.expectEqual(fs.EACCDN, op(&c, .rename, "LINK", "L2", 0, ""));
    try t.expectEqual(fs.EACCDN, op(&c, .setattr, "LINK", "", 0, ""));
    try c.outsideUntouched();
    var buf: [64]u8 = undefined;
    try t.expectEqualStrings("old picture", try get(c.hd, "PICS/OLD.PI1", &buf));
}

test "a save through the temp name, an overwrite, delete, rename, folders, attributes" {
    var c = try Card.init();
    defer c.deinit();
    var buf: [64]u8 = undefined;
    try t.expectEqual(@as(i32, 0), op(&c, .write, "PICS\\NEW.PI1", "", 1, "first half "));
    try t.expectError(error.FileNotFound, get(c.hd, "PICS/NEW.PI1", &buf)); // not there before LAST
    const r2 = kf.Req{ .op = .write, .flags = 2, .slot = 0, .attr = 0, .offset = 11, .path = "PICS\\NEW.PI1", .path2 = "", .data = "and the rest" };
    try t.expectEqual(@as(i32, 0), try kf.run(c.hd, &r2));
    try t.expectEqualStrings("first half and the rest", try get(c.hd, "PICS/NEW.PI1", &buf));
    try t.expectError(error.FileNotFound, get(c.hd, "PICS/~KOS0.TMP", &buf));
    try t.expectEqual(@as(i32, 0), op(&c, .write, "PICS\\NEW.PI1", "", 3, "short"));
    try t.expectEqualStrings("short", try get(c.hd, "PICS/NEW.PI1", &buf));
    try t.expectEqual(fs.EIHNDL, op(&c, .write, "PICS\\NEW.PI1", "", 2, "no FIRST")); // no temp file
    try t.expectEqual(fs.EACCDN, op(&c, .write, "PICS", "", 3, "a folder"));
    try t.expectEqual(@as(i32, 0), op(&c, .mkdir, "DIR", "", 0, ""));
    try t.expectEqual(fs.EACCDN, op(&c, .mkdir, "DIR", "", 0, ""));
    try t.expectEqual(fs.EPTHNF, op(&c, .mkdir, "NO\\DIR", "", 0, ""));
    try t.expectEqual(@as(i32, 0), op(&c, .rename, "PICS\\NEW.PI1", "DIR\\MOVED.PI1", 0, ""));
    try t.expectEqual(fs.EACCDN, op(&c, .rename, "DIR", "DIR\\IN", 0, "")); // into itself
    try t.expectEqual(fs.EACCDN, op(&c, .rmdir, "DIR", "", 0, "")); // not empty
    const ro = kf.Req{ .op = .setattr, .flags = 0, .slot = 0, .attr = 1, .offset = 0, .path = "DIR\\MOVED.PI1", .path2 = "", .data = "" };
    _ = try kf.run(c.hd, &ro);
    try t.expectEqual(fs.EACCDN, op(&c, .delete, "DIR\\MOVED.PI1", "", 0, "")); // read-only
    try t.expectEqual(fs.EACCDN, op(&c, .write, "DIR\\MOVED.PI1", "", 3, "x"));
    _ = op(&c, .setattr, "DIR\\MOVED.PI1", "", 0, "");
    try t.expectEqual(@as(i32, 0), op(&c, .delete, "DIR\\MOVED.PI1", "", 0, ""));
    try t.expectEqual(fs.EFILNF, op(&c, .delete, "DIR\\MOVED.PI1", "", 0, ""));
    try t.expectEqual(fs.EFILNF, op(&c, .delete, "DIR", "", 0, "")); // a folder is Ddelete's
    try t.expectEqual(@as(i32, 0), op(&c, .rmdir, "DIR", "", 0, ""));
    try t.expectEqual(fs.EPTHNF, op(&c, .rmdir, "DIR", "", 0, ""));
    try c.outsideUntouched();
}

/// The block as cycles/bkosfile.c writes it, the magic last.
fn ask(win: []volatile u32, seq: u32, f: [11]u32) void {
    const at = (win.len * 4 - mc.KOS_FILE_FROM_TOP) / 4;
    var check: u32 = mc.KOS_FILE_MAGIC ^ seq;
    for (f) |x| check ^= x;
    for (f, 0..) |x, i| win[at + mc.KF_OP + i] = x;
    win[at + mc.KF_SEQ] = seq;
    win[at + mc.KF_CHECK] = ~check;
    win[at + mc.KF_MAGIC] = mc.KOS_FILE_MAGIC;
}

fn answer(win: []volatile u32) [2]u32 {
    const at = (win.len * 4 - mc.KOS_FILE_FROM_TOP) / 4;
    return .{ win[at + mc.KF_DONE], win[at + mc.KF_ACK] };
}

test "the block: served once from a copy, the paths and data inside the window, the generation bumped" {
    var c = try Card.init();
    defer c.deinit();
    var win = [_]u32{0} ** 4096; // 16 KiB
    @memcpy(std.mem.sliceAsBytes(win[0..4]), "X.DAThello world");
    var s = kf.Server{ .words = &win, .be = .{ .root = c.hd } };
    try t.expect(!s.poll()); // no block
    try t.expectEqual(mc.KOS_FILE_READY, win[(win.len * 4 - mc.KOS_FILE_READY_FROM_TOP) / 4]); // but here
    // write FIRST|LAST, slot 0, attr 0, offset 0, len 11 at 5, path "X.DAT" at 0
    ask(&win, 1, .{ 1, 3, 0, 0, 0, 11, 5, 0, 5, 0, 0 });
    try t.expect(s.poll());
    try t.expectEqual([2]u32{ 0, 1 }, answer(&win));
    try t.expect(!s.poll()); // answered: never served twice
    var buf: [64]u8 = undefined;
    try t.expectEqualStrings("hello world", try get(c.hd, "X.DAT", &buf));
    try t.expectEqual(@as(u32, 1), win[(win.len * 4 - mc.KOS_CGEN_FROM_TOP) / 4]);
    ask(&win, 2, .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }); // gen: no write
    try t.expect(s.poll());
    try t.expectEqual([2]u32{ 1, 2 }, answer(&win));
    const top: u32 = @intCast(win.len * 4 - mc.KOS_FILE_FROM_TOP);
    ask(&win, 3, .{ 1, 3, 0, 0, 0, 8, top - 4, 0, 5, 0, 0 }); // data running into the top blocks
    try t.expect(s.poll());
    try t.expectEqual([2]u32{ @bitCast(fs.ERANGE), 3 }, answer(&win));
    ask(&win, 4, .{ 2, 0, 0, 0, 0, 0, 0, 0, 200, 0, 0 }); // a path longer than any C: path
    try t.expect(s.poll());
    try t.expectEqual([2]u32{ @bitCast(fs.ERANGE), 4 }, answer(&win));
    ask(&win, 5, .{ 2, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0 });
    win[(win.len * 4 - mc.KOS_FILE_FROM_TOP) / 4 + mc.KF_CHECK] ^= 1; // half-written
    try t.expect(!s.poll());
    try t.expectError(error.FileNotFound, get(c.hd, "Y.DAT", &buf));
    try t.expectEqualStrings("hello world", try get(c.hd, "X.DAT", &buf));
}
