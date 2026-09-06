const std = @import("std");

const page_size = 65536; // in bytes

// Video shared main-thread memory (see hw/sdk/memmap.zig): machine-video.wasm +
// demo.wasm import the SAME WebAssembly.Memory; demo linked above the machine.
const video_shared_bytes = 55 * page_size; // 3.6 MiB (holds the 800x280 raster PFB; see memmap SHARED_PAGES)
const demo_global_base: u64 = 0x100000; // 1 MiB
const machine_stack = 1 * page_size;
const demo_stack = 6 * page_size;

// Audio shared worklet-thread memory (see hw/sdk/audio.zig).
const audio_bytes = 48 * page_size;
const audio_demo_base: u64 = 0x100000;

pub fn build(b: *std.Build) void {
    const build_wasm = b.option(bool, "wasm", "Build the wasm libraries.") orelse false;
    // Kept for compatibility with the old `-Drelease=true` invocation.
    const release = b.option(bool, "release", "Build in ReleaseSmall mode.") orelse false;
    const optimize: std.builtin.OptimizeMode = if (release) .ReleaseSmall else b.standardOptimizeOption(.{});

    if (!build_wasm) return;

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .musl,
    });

    // ----------------------------------------------------------------------
    // Shared modules — the SEAL is enforced here: the open `apps`/`zigos` code
    // reaches the machine ONLY through the `hardware`/`audio_hw` SDK headers
    // (hw/sdk/*), never hw/ machine source.
    // ----------------------------------------------------------------------
    const sdk_video = b.createModule(.{
        .root_source_file = b.path("hw/sdk/hardware.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const sdk_audio = b.createModule(.{
        .root_source_file = b.path("hw/sdk/audio.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const zigos_mod = b.createModule(.{
        .root_source_file = b.path("zigos/zigos.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "hardware", .module = sdk_video }},
    });
    const players_mod = b.createModule(.{
        .root_source_file = b.path("zigos/players/players.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "audio_hw", .module = sdk_audio }},
    });

    const sealed_step = b.step("sealed", "Compiles the sealed machine + open demo wasm");

    const installTo = struct {
        fn add(bld: *std.Build, art: *std.Build.Step.Compile, step: *std.Build.Step) void {
            const inst = bld.addInstallArtifact(art, .{ .dest_dir = .{ .override = .{ .custom = "../docs" } } });
            bld.getInstallStep().dependOn(&inst.step);
            step.dependOn(&inst.step);
        }
    }.add;

    // ----------------------------------------------------------------------
    // hw/ — SEALED machine binaries (single module root each; no SDK imports)
    // ----------------------------------------------------------------------
    const machine_video = b.addExecutable(.{
        .name = "machine-video",
        .root_module = b.createModule(.{
            .root_source_file = b.path("hw/machine_video.zig"),
            .target = wasm_target,
            .optimize = optimize,
        }),
    });
    machine_video.entry = .disabled;
    machine_video.rdynamic = true;
    machine_video.import_memory = true;
    machine_video.stack_size = machine_stack;
    machine_video.initial_memory = video_shared_bytes;
    machine_video.max_memory = video_shared_bytes;
    installTo(b, machine_video, sealed_step);

    const machine_audio = b.addExecutable(.{
        .name = "machine-audio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("hw/machine_audio.zig"),
            .target = wasm_target,
            .optimize = optimize,
        }),
    });
    machine_audio.entry = .disabled;
    machine_audio.rdynamic = true;
    machine_audio.import_memory = true;
    machine_audio.stack_size = machine_stack;
    machine_audio.initial_memory = audio_bytes;
    machine_audio.max_memory = audio_bytes;
    installTo(b, machine_audio, sealed_step);

    // ----------------------------------------------------------------------
    // apps/ — OPEN coder binaries (import zigos / players / audio_hw modules)
    // ----------------------------------------------------------------------
    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/demo_main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zigos", .module = zigos_mod }},
        }),
    });
    demo.entry = .disabled;
    demo.rdynamic = true;
    demo.import_memory = true;
    demo.stack_size = demo_stack;
    demo.initial_memory = video_shared_bytes;
    demo.max_memory = video_shared_bytes;
    demo.global_base = demo_global_base;
    installTo(b, demo, sealed_step);

    const demo_audio = b.addExecutable(.{
        .name = "demo-audio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/demo_audio_main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "audio_hw", .module = sdk_audio },
                .{ .name = "players", .module = players_mod },
            },
        }),
    });
    demo_audio.entry = .disabled;
    demo_audio.rdynamic = true;
    demo_audio.import_memory = true;
    demo_audio.stack_size = 2 * page_size;
    demo_audio.initial_memory = audio_bytes;
    demo_audio.max_memory = audio_bytes;
    demo_audio.global_base = audio_demo_base;
    installTo(b, demo_audio, sealed_step);
}
