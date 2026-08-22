const std = @import("std");
const memmap = @import("src/sdk/memmap.zig");

const page_size = 65536; // in bytes

// Shared main-thread memory: the sealed machine-video.wasm and the open demo.wasm
// import the SAME WebAssembly.Memory. Layout (see src/sdk/memmap.zig):
//   [0x000000..0x100000) machine module data + stack   (global-base default)
//   [0x100000..0x200000) demo module data + stack       (global-base below)
//   [0x200000..)         reserved video hardware region (neither module's data)
const shared_bytes = memmap.SHARED_PAGES * page_size; // 48 pages, 3 MiB
const demo_global_base: u64 = 0x100000; // 1 MiB
const machine_stack = 1 * page_size;
const demo_stack = 6 * page_size;

pub fn build(b: *std.Build) void {
    const build_native = b.option(bool, "native", "Build the native executable.") orelse false;
    const build_wasm = b.option(bool, "wasm", "Build the wasm libraries.") orelse false;
    // Kept for compatibility with the old `-Drelease=true` invocation.
    const release = b.option(bool, "release", "Build in ReleaseSmall mode.") orelse false;
    const optimize: std.builtin.OptimizeMode = if (release) .ReleaseSmall else b.standardOptimizeOption(.{});

    if (build_wasm) {
        const wasm_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        });

        // --- SEALED: machine-video.wasm ---
        const machine = b.addExecutable(.{
            .name = "machine-video",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/machine_video.zig"),
                .target = wasm_target,
                .optimize = optimize,
            }),
        });
        machine.entry = .disabled;
        machine.rdynamic = true;
        machine.import_memory = true;
        machine.stack_size = machine_stack;
        machine.initial_memory = shared_bytes;
        machine.max_memory = shared_bytes;

        const machine_install = b.addInstallArtifact(machine, .{
            .dest_dir = .{ .override = .{ .custom = "../docs" } },
        });
        b.getInstallStep().dependOn(&machine_install.step);

        // --- OPEN: demo.wasm (ZigOS + effects + scene), linked ABOVE the machine ---
        const demo = b.addExecutable(.{
            .name = "demo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/demo_main.zig"),
                .target = wasm_target,
                .optimize = optimize,
            }),
        });
        demo.entry = .disabled;
        demo.rdynamic = true;
        demo.import_memory = true;
        demo.stack_size = demo_stack;
        demo.initial_memory = shared_bytes;
        demo.max_memory = shared_bytes;
        demo.global_base = demo_global_base;

        const demo_install = b.addInstallArtifact(demo, .{
            .dest_dir = .{ .override = .{ .custom = "../docs" } },
        });
        b.getInstallStep().dependOn(&demo_install.step);

        const sealed_step = b.step("sealed", "Compiles the sealed machine + open demo wasm");
        sealed_step.dependOn(&machine_install.step);
        sealed_step.dependOn(&demo_install.step);

        // --- SEALED + OPEN audio pair, sharing one memory on the worklet thread ---
        // Layout (see src/sdk/audio.zig): machine-audio at global-base 0, demo-audio
        // at 0x100000, reserved song RAM at 0x200000; 48 pages (3 MiB), no growth.
        const audio_bytes = 48 * page_size;
        const audio_demo_base: u64 = 0x100000;

        const machine_audio = b.addExecutable(.{
            .name = "machine-audio",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/machine_audio.zig"),
                .target = wasm_target,
                .optimize = optimize,
            }),
        });
        machine_audio.entry = .disabled;
        machine_audio.rdynamic = true;
        machine_audio.import_memory = true;
        machine_audio.stack_size = 1 * page_size;
        machine_audio.initial_memory = audio_bytes;
        machine_audio.max_memory = audio_bytes;

        const machine_audio_install = b.addInstallArtifact(machine_audio, .{
            .dest_dir = .{ .override = .{ .custom = "../docs" } },
        });
        b.getInstallStep().dependOn(&machine_audio_install.step);
        sealed_step.dependOn(&machine_audio_install.step);

        const demo_audio = b.addExecutable(.{
            .name = "demo-audio",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/demo_audio_main.zig"),
                .target = wasm_target,
                .optimize = optimize,
            }),
        });
        demo_audio.entry = .disabled;
        demo_audio.rdynamic = true;
        demo_audio.import_memory = true;
        demo_audio.stack_size = 2 * page_size;
        demo_audio.initial_memory = audio_bytes;
        demo_audio.max_memory = audio_bytes;
        demo_audio.global_base = audio_demo_base;

        const demo_audio_install = b.addInstallArtifact(demo_audio, .{
            .dest_dir = .{ .override = .{ .custom = "../docs" } },
        });
        b.getInstallStep().dependOn(&demo_audio_install.step);
        sealed_step.dependOn(&demo_audio_install.step);
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
