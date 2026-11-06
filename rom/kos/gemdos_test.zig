// KOS GEMDOS (rom/kos/gemdos.zig) over docs/gemdos-c.img (tools/gemdos_c_image.py) as C:, the card's
// HD folder its root: the calls TOS programs make, their answers, and what they cost in requests.
// Run from the repository's root (build.sh does). tools/tests/test_kos_gemdos.py holds the same calls
// against mtools on FAT16 / FAT32 cards made by mkfs.fat (fragmented files, long names, big folders).
const std = @import("std");
const gemdos = @import("gemdos.zig");
const err = gemdos.err;
const fat = @import("fat.zig");
const t = std.testing;

var image: []const u8 = &.{};
var fail = false; // the drive stops answering (a card pulled, glass not serving)
var biggest: u32 = 0;

fn run(_: *anyopaque, sector: u32, count: u32, dst: [*]align(4) u8) u32 {
    const at = @as(usize, sector) * fat.SECTOR;
    const n = @as(usize, count) * fat.SECTOR;
    if (fail or count == 0 or count > 64 or at + n > image.len) return 0;
    @memcpy(dst[0..n], image[at..][0..n]);
    biggest = @max(biggest, count);
    return count;
}

var dummy: u8 = 0;
var drive_c: gemdos.Drive = .{ .run_fn = run, .ctx = &dummy, .max_run = 64, .root_name = "HD" };
var dos: gemdos.Dos = .{};

fn setUp() !void {
    if (image.len == 0) image = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/gemdos-c.img", std.heap.page_allocator, .limited(1 << 20));
    fail = false;
    drive_c.reset();
    dos = .{};
    dos.attach(gemdos.DRIVE_C, &drive_c);
}

fn pic(name: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(t.io, name, std.heap.page_allocator, .limited(1 << 20));
}

test "C:\\ is the card's HD folder: a nested picture reads whole, in a request or two" {
    try setUp();
    try t.expectEqual(@as(i32, 1 << 2), dos.Dsetdrv(2)); // only C: answers (no A: attached)
    const h = dos.Fopen("C:\\PICTURES\\PLASMA\\ZIGPLASM.PI1", 0);
    try t.expectEqual(@as(i32, gemdos.FIRST_HANDLE), h);
    const want = try pic("apps/ports/grafx2/ownpics/ZIGPLASMA.PI1");
    var buf: [40000]u8 align(4) = undefined;
    const before = drive_c.trips;
    try t.expectEqual(@as(i32, @intCast(want.len)), dos.Fread(h, buf.len, &buf));
    try t.expectEqualSlices(u8, want, buf[0..want.len]);
    try t.expect(drive_c.trips - before <= 3); // 63 whole sectors in one request, the tail via the cache
    try t.expectEqual(@as(u32, 62), biggest); // one request: the file's 31 clusters, contiguous
    try t.expectEqual(@as(i32, 0), dos.Fread(h, 10, &buf)); // at the end
    try t.expectEqual(@as(i32, 0), dos.Fclose(h));
    try t.expectEqual(err.EIHNDL, dos.Fclose(h));
}

test "names: either separator, any case, a long name cut to 8.3, `..`, the current folder" {
    try setUp();
    _ = dos.Dsetdrv(2);
    try t.expect(dos.Fopen("c:/pictures/plasma/../ZIGWAVES.pi1", 0) >= 0);
    try t.expect(dos.Fopen("C:\\PICTURES\\PLASMA\\ZIGPLASMA.PI1", 0) >= 0); // cut, as TOS cuts it
    try t.expectEqual(@as(i32, 0), dos.Dsetpath("\\PICTURES\\PLASMA"));
    var path: [64]u8 = undefined;
    try t.expectEqual(@as(i32, 0), dos.Dgetpath(&path, 0));
    try t.expectEqualStrings("\\PICTURES\\PLASMA", std.mem.sliceTo(&path, 0));
    try t.expect(dos.Fopen("ZIGPLASM.NEO", 0) >= 0);
    try t.expect(dos.Fopen("..\\ZIGWAVES.PI1", 0) >= 0);
    try t.expectEqual(@as(i32, 0), dos.Dsetpath("..\\..\\..")); // stops at C:\
    try t.expectEqual(@as(i32, 0), dos.Dgetpath(&path, 3));
    try t.expectEqualStrings("", std.mem.sliceTo(&path, 0));
}

test "Fsfirst / Fsnext list a folder as TOS does: files, folders only when asked, patterns" {
    try setUp();
    var dta: gemdos.Dta = .{};
    dos.Fsetdta(&dta);
    try t.expectEqual(@as(i32, 0), dos.Fsfirst("C:\\*.*", 0));
    try t.expectEqualStrings("README.TXT", std.mem.sliceTo(&dta.name, 0));
    try t.expectEqual(@as(u16, (2026 - 1980) << 9 | 10 << 5 | 26), std.mem.readInt(u16, &dta.date, .little)); // the fixture's stamp
    try t.expectEqual(@as(u32, 150), std.mem.readInt(u32, &dta.length, .little));
    try t.expectEqual(@as(i32, 0), dos.Fsnext());
    try t.expectEqualStrings("EMPTY.DAT", std.mem.sliceTo(&dta.name, 0)); // PICTURES, TEXTS: folders
    try t.expectEqual(err.ENMFIL, dos.Fsnext());
    var n: usize = 0;
    var r = dos.Fsfirst("C:\\*.*", gemdos.search.FA_DIR);
    while (r == 0) : (r = dos.Fsnext()) n += 1;
    try t.expectEqual(@as(usize, 4), n);
    n = 0;
    r = dos.Fsfirst("C:\\TEXTS\\NOTE1?.TXT", 0); // past the folder's first sector
    while (r == 0) : (r = dos.Fsnext()) n += 1;
    try t.expectEqual(@as(usize, 10), n);
    try t.expectEqual(@as(u32, 9 * 20), std.mem.readInt(u32, &dta.length, .little)); // NOTE19.TXT
    try t.expectEqual(err.EFILNF, dos.Fsfirst("C:\\*.PNG", 0));
    try t.expectEqual(err.EPTHNF, dos.Fsfirst("C:\\NOPE\\*.*", 0));
}

test "Fseek and short reads: from the start, the position and the end; past it is ERANGE" {
    try setUp();
    const h = dos.Fopen("C:\\PICTURES\\ZIGWAVES.PI1", 0);
    const want = try pic("apps/ports/grafx2/ownpics/ZIGWAVES.PI1");
    var b: [600]u8 = undefined;
    try t.expectEqual(@as(i32, 2), dos.Fseek(2, h, 0));
    try t.expectEqual(@as(i32, 600), dos.Fread(h, 600, &b)); // a head inside a sector
    try t.expectEqualSlices(u8, want[2..602], &b);
    try t.expectEqual(@as(i32, @intCast(want.len - 10)), dos.Fseek(-10, h, 2));
    try t.expectEqual(@as(i32, 10), dos.Fread(h, 600, &b));
    try t.expectEqualSlices(u8, want[want.len - 10 ..], b[0..10]);
    try t.expectEqual(@as(i32, 1000), dos.Fseek(1000 - @as(i32, @intCast(want.len)), h, 1));
    try t.expectEqual(err.ERANGE, dos.Fseek(1, h, 2));
    try t.expectEqual(err.ERANGE, dos.Fseek(-1, h, 0));
    try t.expectEqual(err.EINVFN, dos.Fseek(0, h, 3));
}

test "every refusal answers a TOS error, never a trap" {
    try setUp();
    try t.expectEqual(err.EFILNF, dos.Fopen("C:\\NOPE.TXT", 0));
    try t.expectEqual(err.EPTHNF, dos.Fopen("C:\\NOPE\\X.TXT", 0));
    try t.expectEqual(err.EFILNF, dos.Fopen("C:\\PICTURES", 0)); // a folder
    try t.expectEqual(err.EACCDN, dos.Fopen("C:\\README.TXT", 1)); // phase 1: read-only
    try t.expectEqual(err.EDRIVE, dos.Fopen("A:\\README.TXT", 0)); // no A: here
    try t.expectEqual(err.EWRPRO, dos.Fattrib("C:\\README.TXT", 1, 0));
    try t.expectEqual(@as(i32, gemdos.search.FA_DIR), dos.Fattrib("C:\\PICTURES", 0, 0));
    try t.expectEqual(@as(i32, gemdos.search.FA_DIR), dos.Fattrib("C:\\", 0, 0));
    try t.expectEqual(err.EPTHNF, dos.Dsetpath("C:\\README.TXT"));
    try t.expectEqual(err.EIHNDL, dos.Fread(42, 1, undefined));
    for (0..gemdos.MAX_FILES) |_| try t.expect(dos.Fopen("C:\\EMPTY.DAT", 0) >= 0);
    try t.expectEqual(err.ENHNDL, dos.Fopen("C:\\EMPTY.DAT", 0));
}

test "a drive that stops answering: no C:, then read faults on what was open" {
    try setUp();
    fail = true;
    try t.expectEqual(@as(i32, 0), dos.Dsetdrv(2)); // no drive mounts
    try t.expectEqual(err.EDRIVE, dos.Fopen("C:\\README.TXT", 0));
    try setUp();
    const h = dos.Fopen("C:\\PICTURES\\ZIGWAVES.PI1", 0);
    fail = true;
    var b: [4096]u8 align(4) = undefined;
    try t.expectEqual(err.EREADF, dos.Fread(h, b.len, &b));
}

test "a card with no HD folder has no C:" {
    try setUp();
    var bare: gemdos.Drive = .{ .run_fn = run, .ctx = &dummy, .max_run = 64, .root_name = "NOHD" };
    dos.attach(gemdos.DRIVE_C, &bare);
    try t.expectEqual(err.EDRIVE, dos.Fsfirst("C:\\*.*", 0));
}

test {
    _ = @import("gemdos_drive.zig");
}
