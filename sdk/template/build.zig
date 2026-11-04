// The cart's build: this directory depends on the KESTREL SDK (the ZigMachine
// repository) as a Zig package; build.zig.zon says where it is. `make` runs it.
//   zig build                 -> zig-out/demo-<name>.wasm (+ zig-out/bin/zx0pack)
//   zig build -Dname=mydemo   another tag (the Makefile's NAME)
const std = @import("std");
const kestrel = @import("kestrel");

pub fn build(b: *std.Build) void {
    const name = b.option([]const u8, "name", "The cart's tag: demo-<name>.wasm") orelse "hello";
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Default ReleaseSmall") orelse .ReleaseSmall;
    _ = kestrel.addCart(b, b.dependency("kestrel", .{}), .{
        .name = name,
        .root_source_file = b.path("src/hello.zig"),
        .optimize = optimize,
    });
}
