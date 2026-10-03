// The glass: the ZigMachine console's ARM-side program (docs/FPGA_GLASS.md).
//
//   zig build test                                   host tests (simulated register file + fake DDR)
//   zig build                                        host binary, `glass sim-*` commands
//   zig build -Dtarget=arm-linux-musleabihf -Dcpu=cortex_a9 -Doptimize=ReleaseSafe
//                                                    the board binary (Zynq-7000: dual Cortex-A9)
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // The cart's ZX0 depacker and packer are the machine's own (libs/zig/depackers):
    // the board unpacks a cart exactly as rom.wasm's romDepack does.
    const zx0 = b.createModule(.{ .root_source_file = b.path("../../libs/zig/depackers/zx0.zig") });
    const zx0_pack = b.createModule(.{ .root_source_file = b.path("../../libs/zig/depackers/zx0_pack.zig") });

    const exe = b.addExecutable(.{
        .name = "glass",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zx0", .module = zx0 }},
        }),
    });
    b.installArtifact(exe);

    // zx0_pack.zig imports zx0.zig itself, and a file may belong to one module
    // only, so the tests reach the depacker through the packer (src/zx0_shim.zig).
    const zx0_via_pack = b.createModule(.{
        .root_source_file = b.path("src/zx0_shim.zig"),
        .imports = &.{.{ .name = "zx0_pack", .module = zx0_pack }},
    });
    // The machine's memory map: the tests check the pointer's coordinate space against it.
    const memmap = b.createModule(.{ .root_source_file = b.path("../../machine/sdk/memmap.zig") });
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "zx0", .module = zx0_via_pack }, .{ .name = "memmap", .module = memmap } },
        }),
    });
    const run = b.addRunArtifact(tests);
    b.step("test", "Run the glass's host tests").dependOn(&run.step);
}
