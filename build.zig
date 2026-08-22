const std = @import("std");

const page_size = 65536; // in bytes
const min_pages = 32;
const max_pages = 32;
const stack_size = 6 * page_size;

pub fn build(b: *std.Build) void {
    const build_native = b.option(bool, "native", "Build the native executable.") orelse false;
    const build_wasm = b.option(bool, "wasm", "Build the wasm library.") orelse false;
    // Kept for compatibility with the old `-Drelease=true` invocation.
    const release = b.option(bool, "release", "Build in ReleaseSmall mode.") orelse false;
    const optimize: std.builtin.OptimizeMode = if (release) .ReleaseSmall else b.standardOptimizeOption(.{});

    if (build_wasm) {
        const wasm_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        });

        const bootloader = b.addExecutable(.{
            .name = "bootloader",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/bootloader.zig"),
                .target = wasm_target,
                .optimize = optimize,
            }),
        });

        // Freestanding wasm "reactor": no _start entry, export decls, import env memory.
        bootloader.entry = .disabled;
        bootloader.rdynamic = true;
        bootloader.import_memory = true;
        bootloader.stack_size = stack_size;
        bootloader.initial_memory = min_pages * page_size;
        bootloader.max_memory = max_pages * page_size;

        const install = b.addInstallArtifact(bootloader, .{
            .dest_dir = .{ .override = .{ .custom = "../docs" } },
        });
        b.getInstallStep().dependOn(&install.step);

        const bootloader_step = b.step("bootloader", "Compiles bootloader.zig");
        bootloader_step.dependOn(&install.step);
    }

    if (build_native) {
        const target = b.standardTargetOptions(.{});
        const exe = b.addExecutable(.{
            .name = "bootloader",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/native.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(exe);
    }
}
