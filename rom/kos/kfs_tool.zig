// --------------------------------------------------------------------------
// KFS (kfs.zig) on an image file, from the command line: tools/tests/test_kos_cfs.py drives it and
// holds the result against mtools and fsck.fat. One operation a run; prints the TOS code it got.
//
//   kfs_tool IMAGE [--cut N] save PATH FILE       FILE saved as PATH, 32 KB a request, as the library does
//   kfs_tool IMAGE [--cut N] delete|mkdir|rmdir PATH
//   kfs_tool IMAGE [--cut N] rename PATH PATH2
//   kfs_tool IMAGE [--cut N] setattr PATH ATTR
//
// --cut N: the disk stops taking writes after N sectors (a crash mid-request); the image keeps what
// was written before the cut.
// --------------------------------------------------------------------------
const std = @import("std");
const kfs = @import("kfs.zig");
const abi = @import("kfs_abi.zig");
const fat = @import("fat.zig");

var image: []u8 = &.{};
var cut: ?u64 = null;
var writes: u64 = 0;

fn rd(_: *anyopaque, n: u32, dst: *[fat.SECTOR]u8) bool {
    const at = @as(usize, n) * fat.SECTOR;
    if (at + fat.SECTOR > image.len) return false;
    dst.* = image[at..][0..fat.SECTOR].*;
    return true;
}

fn wr(_: *anyopaque, n: u32, src: *const [fat.SECTOR]u8) bool {
    const at = @as(usize, n) * fat.SECTOR;
    if (at + fat.SECTOR > image.len) return false;
    if (cut) |c| if (writes >= c) return false;
    writes += 1;
    image[at..][0..fat.SECTOR].* = src.*;
    return true;
}

var dummy: u8 = 0;
const dev = kfs.Dev{ .ctx = &dummy, .read_fn = rd, .write_fn = wr };

fn save(srv: *kfs.Server, path: []const u8, data: []const u8) i32 {
    var off: usize = 0;
    while (true) {
        const n = @min(data.len - off, abi.DATA_MAX);
        var flags: u32 = if (off == 0) abi.FIRST else 0;
        if (off + n == data.len) flags |= abi.LAST;
        const r = srv.serve(dev, &.{ .op = .write, .flags = flags, .path = path, .offset = @intCast(off), .data = data[off..][0..n] });
        if (r < 0 or flags & abi.LAST != 0) return r;
        off += n;
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;
    var it = init.minimal.args.iterate();
    var args: [8][]const u8 = undefined;
    var argc: usize = 0;
    while (it.next()) |x| : (argc += 1) {
        if (argc == args.len) return error.Usage;
        args[argc] = x;
    }
    if (argc < 4) return error.Usage;
    var a: usize = 2;
    if (std.mem.eql(u8, args[a], "--cut")) {
        cut = try std.fmt.parseInt(u64, args[a + 1], 10);
        a += 2;
    }
    const cwd = std.Io.Dir.cwd();
    image = try cwd.readFileAlloc(io, args[1], gpa, .limited(1 << 31));
    var srv = kfs.Server{};
    const op = args[a];
    const p = args[a + 1];
    const r: i32 = if (std.mem.eql(u8, op, "save"))
        save(&srv, p, try cwd.readFileAlloc(io, args[a + 2], gpa, .limited(1 << 28)))
    else if (std.mem.eql(u8, op, "rename"))
        srv.serve(dev, &.{ .op = .rename, .path = p, .path2 = args[a + 2] })
    else if (std.mem.eql(u8, op, "setattr"))
        srv.serve(dev, &.{ .op = .setattr, .path = p, .attr = try std.fmt.parseInt(u32, args[a + 2], 0) })
    else
        srv.serve(dev, &.{ .op = std.meta.stringToEnum(abi.Op, op) orelse return error.Usage, .path = p });
    try cwd.writeFile(io, .{ .sub_path = args[1], .data = image });
    var buf: [64]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    try w.interface.print("{d} {d}\n", .{ r, writes });
    try w.interface.flush();
}
