// KOS GEMDOS's writes (rom/kos/gemdos_write.zig, gemdos_wops.zig) end to end, natively: the library's
// C: reads the sectors of a copy of docs/gemdos-c.img (FAT12) and its writes go to KFS (kfs.zig), the
// page's and the native host's writer, over the same copy. What a program saves, it reads back; the
// listing shows it; TOS's refusals; what a save costs in requests. tools/tests/test_kos_cfs.py holds
// KFS itself against mtools and fsck.fat on FAT16 / FAT32. Run from the repository's root.
const std = @import("std");
const gemdos = @import("gemdos.zig");
const kfs = @import("kfs.zig");
const abi = @import("kfs_abi.zig");
const fat = @import("fat.zig");
const err = gemdos.err;
const t = std.testing;

var image: []u8 = &.{};
var refuse: i32 = 0; // the host answers this to every write (0: it serves them)
var writes: u32 = 0; // write requests the host got

fn run(_: *anyopaque, sector: u32, count: u32, dst: [*]align(4) u8) u32 {
    const at = @as(usize, sector) * fat.SECTOR;
    const n = @as(usize, count) * fat.SECTOR;
    if (count == 0 or count > 64 or at + n > image.len) return 0;
    @memcpy(dst[0..n], image[at..][0..n]);
    return count;
}

fn rd(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    dst.* = image[@as(usize, n) * fat.SECTOR ..][0..fat.SECTOR].*;
    return true;
}

fn wr(_: *anyopaque, n: u32, src: *const [fat.SECTOR]u8) bool {
    image[@as(usize, n) * fat.SECTOR ..][0..fat.SECTOR].* = src.*;
    return true;
}

var server: kfs.Server = .{};
fn op(_: *anyopaque, req: *abi.Req, path: []const u8, path2: []const u8, data: []const u8) i32 {
    writes += 1;
    if (refuse != 0) return refuse;
    const r = kfs.Request{ .op = @enumFromInt(req.op), .flags = req.flags, .slot = req.slot, .attr = req.attr, .offset = req.offset, .path = path, .path2 = path2, .data = data };
    return server.serve(.{ .ctx = &dummy, .read_fn = rd, .write_fn = wr }, &r);
}

var dummy: u8 = 0;
var drive_c: gemdos.Drive = .{ .run_fn = run, .ctx = &dummy, .max_run = 64, .root_name = "HD", .op_fn = op };
var drive_a: gemdos.Drive = .{ .run_fn = run, .ctx = &dummy, .max_run = 64, .root_name = "HD" }; // no writes
var dos: gemdos.Dos = .{};

fn setUp() !void {
    const src = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/gemdos-c.img", std.heap.page_allocator, .limited(1 << 20));
    image = src;
    refuse = 0;
    writes = 0;
    drive_c.reset();
    drive_a.reset();
    dos = .{};
    dos.attach(gemdos.DRIVE_C, &drive_c);
    dos.attach(gemdos.DRIVE_A, &drive_a);
    _ = dos.Dsetdrv(2);
}

fn save(path: []const u8, data: []const u8, chunk: usize) !i32 {
    const h = dos.Fcreate(path, 0);
    if (h < 0) return h;
    var off: usize = 0;
    while (off < data.len) : (off += chunk) {
        const n = @min(chunk, data.len - off);
        try t.expectEqual(@as(i32, @intCast(n)), dos.Fwrite(h, @intCast(n), data[off..].ptr));
    }
    return dos.Fclose(h);
}

fn load(path: []const u8, buf: []u8) i32 {
    const h = dos.Fopen(path, 0);
    if (h < 0) return h;
    defer _ = dos.Fclose(h);
    return dos.Fread(h, @intCast(buf.len), buf.ptr);
}

fn bytes(n: usize, seed: u8) [80000]u8 {
    var b: [80000]u8 = undefined;
    for (b[0..n], 0..) |*x, i| x.* = @truncate(i * 31 + seed);
    return b;
}

test "a picture saved through stdio-sized writes is one request, and reads back whole" {
    try setUp();
    const pic = bytes(32034, 7);
    try t.expectEqual(@as(i32, 0), try save("C:\\PICTURES\\NEW.PI1", pic[0..32034], 1024));
    try t.expectEqual(@as(u32, 1), writes); // FIRST | LAST: the whole picture in one request
    var buf: [40000]u8 align(4) = undefined;
    try t.expectEqual(@as(i32, 32034), load("C:\\PICTURES\\NEW.PI1", &buf));
    try t.expectEqualSlices(u8, pic[0..32034], buf[0..32034]);
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    try t.expectEqual(@as(i32, 0), dos.Fsfirst("C:\\PICTURES\\*.*", 0));
    var seen: u32 = 0;
    var r: i32 = 0;
    while (r == 0) : (r = dos.Fsnext()) seen += @intFromBool(std.mem.startsWith(u8, &dta.name, "NEW.PI1"));
    try t.expectEqual(@as(u32, 1), seen);
    try t.expectEqual(err.EFILNF, dos.Fsfirst("C:\\PICTURES\\~KOS*.*", 0)); // the temp name is gone
}

test "a big file goes in 32 KB requests; an overwrite replaces; Fseek rewrites what was written" {
    try setUp();
    const big = bytes(70000, 3);
    try t.expectEqual(@as(i32, 0), try save("C:\\BIG.DAT", big[0..70000], 5000));
    try t.expectEqual(@as(u32, 3), writes); // 32 KB, 32 KB, the rest with LAST
    var buf: [80000]u8 align(4) = undefined;
    try t.expectEqual(@as(i32, 70000), load("C:\\BIG.DAT", &buf));
    try t.expectEqualSlices(u8, big[0..70000], buf[0..70000]);
    const h = dos.Fcreate("C:\\BIG.DAT", 0);
    try t.expectEqual(@as(i32, 10), dos.Fwrite(h, 10, "0123456789"));
    try t.expectEqual(@as(i32, 2), dos.Fseek(2, h, 0));
    try t.expectEqual(@as(i32, 2), dos.Fwrite(h, 2, "ab"));
    try t.expectEqual(err.ERANGE, dos.Fseek(11, h, 0));
    try t.expectEqual(err.EACCDN, dos.Fread(h, 1, &buf));
    try t.expectEqual(@as(i32, 0), dos.Fclose(h));
    try t.expectEqual(@as(i32, 10), load("C:\\BIG.DAT", &buf));
    try t.expectEqualSlices(u8, "01ab456789", buf[0..10]);
}

test "two files written at once share the buffer and both arrive whole" {
    try setUp();
    const a = dos.Fcreate("C:\\A.DAT", 0);
    const b = dos.Fcreate("C:\\TEXTS\\B.DAT", 0);
    for (0..100) |_| {
        try t.expectEqual(@as(i32, 3), dos.Fwrite(a, 3, "aaa"));
        try t.expectEqual(@as(i32, 2), dos.Fwrite(b, 2, "bb"));
    }
    try t.expectEqual(@as(i32, 0), dos.Fclose(b));
    try t.expectEqual(@as(i32, 0), dos.Fclose(a));
    var buf: [400]u8 align(4) = undefined;
    try t.expectEqual(@as(i32, 300), load("C:\\A.DAT", &buf));
    try t.expect(std.mem.allEqual(u8, buf[0..300], 'a'));
    try t.expectEqual(@as(i32, 200), load("C:\\TEXTS\\B.DAT", &buf));
    try t.expect(std.mem.allEqual(u8, buf[0..200], 'b'));
}

test "delete, rename, folders and attributes, with TOS's refusals" {
    try setUp();
    try t.expectEqual(@as(i32, 0), try save("C:\\X.DAT", "x", 1));
    try t.expectEqual(@as(i32, 0), dos.Dcreate("C:\\NEWDIR"));
    try t.expectEqual(err.EACCDN, dos.Dcreate("C:\\NEWDIR"));
    try t.expectEqual(@as(i32, 0), dos.Frename(0, "C:\\X.DAT", "C:\\NEWDIR\\Y.DAT"));
    try t.expectEqual(err.EFILNF, dos.Fattrib("C:\\X.DAT", 0, 0));
    try t.expectEqual(err.EACCDN, dos.Frename(0, "C:\\NEWDIR", "C:\\NEWDIR\\IN"));
    try t.expectEqual(err.ENSAME, dos.Frename(0, "C:\\NEWDIR\\Y.DAT", "A:\\Y.DAT"));
    try t.expectEqual(@as(i32, 0x21), dos.Fattrib("C:\\NEWDIR\\Y.DAT", 1, 0x21));
    try t.expectEqual(@as(i32, 0x21), dos.Fattrib("C:\\NEWDIR\\Y.DAT", 0, 0));
    try t.expectEqual(err.EACCDN, dos.Fdelete("C:\\NEWDIR\\Y.DAT")); // read-only
    try t.expectEqual(err.EACCDN, dos.Fcreate("C:\\NEWDIR\\Y.DAT", 0));
    try t.expectEqual(@as(i32, 0x20), dos.Fattrib("C:\\NEWDIR\\Y.DAT", 1, 0x20));
    try t.expectEqual(err.EACCDN, dos.Ddelete("C:\\NEWDIR")); // not empty (the host says so)
    try t.expectEqual(@as(i32, 0), dos.Fdelete("C:\\NEWDIR\\Y.DAT"));
    try t.expectEqual(@as(i32, 0), dos.Dsetpath("C:\\NEWDIR"));
    try t.expectEqual(err.EACCDN, dos.Ddelete("C:\\NEWDIR")); // the current folder
    try t.expectEqual(@as(i32, 0), dos.Dsetpath("C:\\"));
    try t.expectEqual(@as(i32, 0), dos.Ddelete("C:\\NEWDIR"));
    try t.expectEqual(err.EPTHNF, dos.Ddelete("C:\\NEWDIR"));
    try t.expectEqual(err.EFILNF, dos.Fdelete("C:\\NOPE.DAT"));
    try t.expectEqual(err.EFILNF, dos.Fdelete("C:\\PICTURES")); // a folder: Ddelete's
}

test "refused: a folder, a missing folder, a bad name, the root, drive A, a host that fails" {
    try setUp();
    try t.expectEqual(err.EACCDN, dos.Fcreate("C:\\PICTURES", 0));
    try t.expectEqual(err.EPTHNF, dos.Fcreate("C:\\NOPE\\X.DAT", 0));
    try t.expectEqual(err.EACCDN, dos.Fcreate("C:\\A+B.DAT", 0));
    try t.expectEqual(err.EFILNF, dos.Fcreate("C:\\*.DAT", 0));
    try t.expectEqual(err.EACCDN, dos.Fcreate("C:\\", 0));
    try t.expectEqual(err.EACCDN, dos.Fcreate("C:\\X.DAT", 0x10)); // no folder by Fcreate
    try t.expectEqual(err.EWRPRO, dos.Fcreate("A:\\X.DAT", 0));
    try t.expectEqual(err.EWRPRO, dos.Fdelete("A:\\EMPTY.DAT"));
    const r = dos.Fopen("C:\\EMPTY.DAT", 0);
    try t.expectEqual(err.EACCDN, dos.Fwrite(r, 1, "x")); // a file opened for reading
    _ = dos.Fclose(r);
    refuse = err.EWRITF; // the card is full
    const h = dos.Fcreate("C:\\FULL.DAT", 0);
    try t.expectEqual(@as(i32, 1000), dos.Fwrite(h, 1000, &bytes(1000, 1))); // buffered: no request yet
    try t.expectEqual(err.EWRITF, dos.Fwrite(h, 40000, &bytes(40000, 1))); // the first 32 KB went, refused
    try t.expectEqual(err.EWRITF, dos.Fwrite(h, 1, "x")); // every later call says so
    try t.expectEqual(err.EWRITF, dos.Fclose(h));
    refuse = 0;
    try t.expectEqual(err.EFILNF, dos.Fattrib("C:\\FULL.DAT", 0, 0));
}
