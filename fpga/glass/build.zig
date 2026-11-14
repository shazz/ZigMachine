// The glass: the ZigMachine console's ARM-side program (docs/FPGA_GLASS.md).
//
//   zig build test                                   host tests (simulated register file + fake DDR)
//   zig build                                        host binary, `glass sim-*` commands
//   zig build -Dtarget=arm-linux-musleabihf -Dcpu=cortex_a9 -Doptimize=ReleaseSafe
//                                                    the board binary (Zynq-7000: dual Cortex-A9)
const std = @import("std");

const VERSION = "0.4.0"; // 0.4: REG_POINTER in raster coordinates (with the cart firmware that subtracts the borders); 0.3: the control channel (glass ctl); 0.2: console + debug pages, shelf.txt

fn gitHash(b: *std.Build) []const u8 {
    var code: u8 = 0;
    const out = b.runAllowFail(&.{ "git", "-C", b.pathFromRoot("."), "rev-parse", "--short=8", "HEAD" }, &code, .ignore) catch return "nogit";
    return std.mem.trim(u8, out, " \n");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // The cart's ZX0 depacker and packer are the machine's own (libs/zig/depackers):
    // the board unpacks a cart exactly as rom.wasm's romDepack does.
    const zx0 = b.createModule(.{ .root_source_file = b.path("../../libs/zig/depackers/zx0.zig") });
    const zx0_pack = b.createModule(.{ .root_source_file = b.path("../../libs/zig/depackers/zx0_pack.zig") });
    // KOS's FAT reader (rom/kos/fat.zig), the desktop's own: glass finds a real floppy's programs with it.
    const kos_fat = b.createModule(.{ .root_source_file = b.path("../../rom/kos/fat.zig") });
    // KOS GEMDOS's path gate (rom/kos/kfs_path.zig), KFS's own: what a cart may name on C: when it writes.
    const kfs_path = b.createModule(.{ .root_source_file = b.path("../../rom/kos/kfs_path.zig") });
    // ZIGNIC's request (machine/sdk/net_abi.zig): the one definition glass's network card serves (src/net_card.zig).
    const net_abi = b.createModule(.{ .root_source_file = b.path("../../machine/sdk/net_abi.zig") });
    // The machine's memory map: a desk-mode screenshot reads plane 0 and palette 0 by it (src/shot_grab.zig),
    // and the tests check the pointer's coordinate space against it.
    const memmap = b.createModule(.{ .root_source_file = b.path("../../machine/sdk/memmap.zig") });

    // The glass program's version and the commit it was built from, for the OSD's debug page.
    const info = b.addOptions();
    info.addOption([]const u8, "version", VERSION);
    info.addOption([]const u8, "git", b.option([]const u8, "git", "commit hash to report (default: git rev-parse)") orelse gitHash(b));
    const build_info = info.createModule();

    const exe = b.addExecutable(.{
        .name = "glass",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "zx0", .module = zx0 }, .{ .name = "build_info", .module = build_info }, .{ .name = "kos_fat", .module = kos_fat }, .{ .name = "kos_kfs_path", .module = kfs_path }, .{ .name = "net_abi", .module = net_abi }, .{ .name = "memmap", .module = memmap } },
        }),
    });
    b.installArtifact(exe);

    // zx0_pack.zig imports zx0.zig itself, and a file may belong to one module
    // only, so the tests reach the depacker through the packer (src/zx0_shim.zig).
    const zx0_via_pack = b.createModule(.{
        .root_source_file = b.path("src/zx0_shim.zig"),
        .imports = &.{.{ .name = "zx0_pack", .module = zx0_pack }},
    });
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zx0", .module = zx0_via_pack },
                .{ .name = "memmap", .module = memmap },
                .{ .name = "build_info", .module = build_info },
                .{ .name = "kos_fat", .module = kos_fat },
                .{ .name = "kos_kfs_path", .module = kfs_path },
                .{ .name = "net_abi", .module = net_abi },
            },
        }),
    });
    const run = b.addRunArtifact(tests);
    b.step("test", "Run the glass's host tests").dependOn(&run.step);
}
