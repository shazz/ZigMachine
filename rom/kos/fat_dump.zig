// What KOS's FAT reader (rom/kos/fat.zig) sees in a disk image: every file and folder, depth first,
// one line each: "PATH\tSIZE\tDATE\tFNV-1a of the bytes" (folders: "PATH/\t-\tDATE\t-"). The first
// line is the FAT type. tools/tests/test_kos_fat.py compares it with mtools' view of images made by
// mkfs.fat, the independent oracle.
//
//   zig run rom/kos/fat_dump.zig -- IMAGE   (a native tool beside the reader; rom.wasm never imports it)
const std = @import("std");
const fat = @import("fat.zig");

var image: []const u8 = &.{};
var data: [8 << 20]u8 = undefined; // one file at a time: the largest image the tests make

fn read(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    const at = @as(usize, n) * fat.SECTOR;
    if (at + fat.SECTOR > image.len) return false;
    @memcpy(dst, image[at..][0..fat.SECTOR]);
    return true;
}

fn fnv(b: []const u8) u32 {
    var h: u32 = 0x811C9DC5;
    for (b) |x| h = (h ^ x) *% 0x01000193;
    return h;
}

fn walk(v: *fat.Volume, d: fat.Dir, path: []const u8, depth: u32, w: *std.Io.Writer) !void {
    if (depth > 8) return error.TooDeep;
    var out: [256]fat.Entry = undefined;
    const n = try v.list(d, &out);
    for (out[0..n]) |*e| {
        var p: [256]u8 = undefined;
        const full = try std.fmt.bufPrint(&p, "{s}{s}", .{ path, e.nameSlice() });
        if (e.isDir()) {
            try w.print("{s}/\t-\t{d}\t-\n", .{ full, e.date });
            var sub: [257]u8 = undefined;
            try walk(v, .{ .cluster = e.cluster }, try std.fmt.bufPrint(&sub, "{s}/", .{full}), depth + 1, w);
            continue;
        }
        const got = try v.read(e, 0, data[0..e.size]);
        try w.print("{s}\t{d}\t{d}\t{x:0>8}\n", .{ full, got, e.date, fnv(data[0..got]) });
    }
}

pub fn main(init: std.process.Init) !u8 {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const path = args.next() orelse return 2;
    image = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(256 << 20));
    defer init.gpa.free(image);
    var buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(init.io, &buf);
    const w = &fw.interface;
    var dummy: u8 = 0;
    var v = fat.Volume.mount(read, &dummy) catch |err| {
        try w.print("error {t}\n", .{err});
        try w.flush();
        return 1;
    };
    try w.print("{t}\n", .{v.kind});
    walk(&v, v.root(), "", 0, w) catch |err| try w.print("error {t}\n", .{err});
    try w.flush();
    return 0;
}
