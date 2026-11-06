// What KOS GEMDOS (rom/kos/gemdos.zig) sees on C: of a card image: every file and folder under the
// card's HD folder, depth first, through Fsfirst / Fsnext / Fopen / Fread, one line each:
// "PATH\tSIZE\tFNV-1a of the bytes" (folders: "PATH\\\t-\t-"); the last line, "trips N", the requests.
// Each file is read in pieces of `chunk` bytes (an argument): tools/tests/test_kos_gemdos.py reads with
// one big read (straight into the buffer, merged clusters) and with stdio's 1 KB (through the cache),
// and holds both against mtools on cards made by mkfs.fat.
//
//   zig run rom/kos/gemdos_dump.zig -- IMAGE CHUNK   (a native tool beside the library)
const std = @import("std");
const gemdos = @import("gemdos.zig");
const fat = @import("fat.zig");

var image: []const u8 = &.{};
var data: [8 << 20]u8 align(4) = undefined;
var chunk: usize = 1024;

fn run(_: *anyopaque, sector: u32, count: u32, dst: [*]align(4) u8) u32 {
    const at = @as(usize, sector) * fat.SECTOR;
    const n = @as(usize, count) * fat.SECTOR;
    if (count == 0 or count > 64 or at + n > image.len) return 0;
    @memcpy(dst[0..n], image[at..][0..n]);
    return count;
}

fn fnv(b: []const u8) u32 {
    var h: u32 = 0x811C9DC5;
    for (b) |x| h = (h ^ x) *% 0x01000193;
    return h;
}

fn walk(dos: *gemdos.Dos, path: []const u8, depth: u32, w: *std.Io.Writer) !void {
    if (depth > 7) return error.TooDeep;
    var spec: [160]u8 = undefined;
    var dta: gemdos.Dta = .{};
    var names: [256][14]u8 = undefined; // a folder's entries first: the walk below reuses the DTA
    var dirs: [256]bool = undefined;
    var n: usize = 0;
    dos.Fsetdta(&dta);
    var r = dos.Fsfirst(try std.fmt.bufPrint(&spec, "{s}\\*.*", .{path}), gemdos.search.FA_DIR | gemdos.search.FA_HIDDEN | gemdos.search.FA_SYSTEM);
    while (r == 0 and n < names.len) : (r = dos.Fsnext()) {
        names[n] = dta.name;
        dirs[n] = dta.attrib & gemdos.search.FA_DIR != 0;
        n += 1;
    }
    if (r != gemdos.err.EFILNF and r != gemdos.err.ENMFIL and r != 0) try w.print("error {d} in {s}\n", .{ r, path });
    for (names[0..n], dirs[0..n]) |*nm, isdir| {
        var full: [160]u8 = undefined;
        const p = try std.fmt.bufPrint(&full, "{s}\\{s}", .{ path, std.mem.sliceTo(nm, 0) });
        if (isdir) {
            try w.print("{s}\\\t-\t-\n", .{p[3..]});
            try walk(dos, p, depth + 1, w);
            continue;
        }
        const h = dos.Fopen(p, 0);
        if (h < 0) {
            try w.print("{s}\terror {d}\n", .{ p[3..], h });
            continue;
        }
        var got: usize = 0;
        while (true) {
            const k = dos.Fread(h, @intCast(chunk), data[got..].ptr);
            if (k <= 0) break;
            got += @intCast(k);
        }
        _ = dos.Fclose(h);
        try w.print("{s}\t{d}\t{x:0>8}\n", .{ p[3..], got, fnv(data[0..got]) });
    }
}

pub fn main(init: std.process.Init) !u8 {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse return 2;
    if (args.next()) |c| chunk = try std.fmt.parseInt(usize, c, 10);
    image = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(256 << 20));
    defer init.gpa.free(image);
    var buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &buf);
    const w = &fw.interface;
    var dummy: u8 = 0;
    var c: gemdos.Drive = .{ .run_fn = run, .ctx = &dummy, .max_run = 64, .root_name = "HD" };
    var dos: gemdos.Dos = .{};
    dos.attach(gemdos.DRIVE_C, &c);
    if (dos.Dsetdrv(gemdos.DRIVE_C) & 4 == 0) {
        try w.print("no C:\n", .{});
        try w.flush();
        return 1;
    }
    try walk(&dos, "C:", 0, w);
    try w.print("trips {d}\n", .{c.trips});
    try w.flush();
    return 0;
}
