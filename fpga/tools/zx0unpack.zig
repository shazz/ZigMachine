// zx0unpack: a ZigMachine ZX0 container back to its bytes, with the machine's own depacker
// (libs/zig/depackers/zx0.zig, what rom.wasm's romDepack runs), for tools/glass_shelf.py:
// a program on a data disk is ZX0-packed wasm, and its board image is built from the wasm.
//
//   zx0unpack <in> <out>      exit 1 if <in> is not a readable ZX0 container
//
//   zig build-exe -OReleaseFast --dep zx0 -Mroot=fpga/tools/zx0unpack.zig -Mzx0=libs/zig/depackers/zx0.zig
const std = @import("std");
const zx0 = @import("zx0");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const in = args.next() orelse return usage();
    const out = args.next() orelse return usage();
    const src = try std.Io.Dir.cwd().readFileAlloc(init.io, in, init.gpa, .limited(64 << 20));
    defer init.gpa.free(src);
    const n = zx0.depackedLen(src) orelse return fail(in);
    const dst = try init.gpa.alloc(u8, n);
    defer init.gpa.free(dst);
    if (zx0.depack(src, dst) != n) return fail(in);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = dst });
}

fn usage() error{Usage} {
    std.debug.print("usage: zx0unpack <in> <out>\n", .{});
    return error.Usage;
}

fn fail(path: []const u8) error{NotZx0} {
    std.debug.print("zx0unpack: {s}: not a readable ZX0 container\n", .{path});
    return error.NotZx0;
}
