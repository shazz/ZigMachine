const std = @import("std");

const page_size = 65536; // in bytes

// Video shared main-thread memory (see machine/sdk/memmap.zig): machine-video.wasm +
// demo.wasm import the SAME WebAssembly.Memory; demo linked above the machine.
const video_shared_bytes = 79 * page_size; // ~5.2 MiB (2 MiB demo window + 1 MiB VRAM + PFB; see memmap SHARED_PAGES)
const demo_global_base: u64 = 0x100000; // 1 MiB
const machine_stack = 1 * page_size;
const demo_stack = 6 * page_size;

// Audio shared worklet-thread memory (see machine/sdk/audio.zig).
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
    // (machine/sdk/*), never machine/ source.
    // ----------------------------------------------------------------------
    const sdk_video = b.createModule(.{
        .root_source_file = b.path("machine/sdk/hardware.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const sdk_audio = b.createModule(.{
        .root_source_file = b.path("machine/sdk/audio.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    const zigos_mod = b.createModule(.{
        .root_source_file = b.path("libs/zig/zigos.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "hardware", .module = sdk_video }},
    });
    const players_mod = b.createModule(.{
        .root_source_file = b.path("libs/zig/players/players.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "audio_hw", .module = sdk_audio }},
    });
    // rom/ — reference system software (GEM). Statically linked into the demo for
    // now; cut into its own rom.wasm later. Uses ZigOS helpers + the HW ABI.
    const rom_mod = b.createModule(.{
        .root_source_file = b.path("rom/rom.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigos", .module = zigos_mod },
            .{ .name = "hardware", .module = sdk_video },
        },
    });
    // machine/boot.zig — the boot ROM (POST screen). Machine firmware: depends
    // ONLY on the HW ABI, no libs. App-linked into the demo for now; will move
    // into machine-video.wasm when the machine renders its own boot (Phase 2).
    const boot_rom_mod = b.createModule(.{
        .root_source_file = b.path("machine/boot.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "hardware", .module = sdk_video }},
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
    // machine/ — SEALED machine binaries (single module root each; no SDK imports)
    // ----------------------------------------------------------------------
    const machine_video = b.addExecutable(.{
        .name = "machine-video",
        .root_module = b.createModule(.{
            .root_source_file = b.path("machine/machine_video.zig"),
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
            .root_source_file = b.path("machine/machine_audio.zig"),
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
    // apps/zig/ — OPEN coder binaries (import zigos / rom / players / audio_hw)
    // ----------------------------------------------------------------------
    // Cartridge matrix: the menu launcher (demo.wasm) + one cart per scene
    // (demo-<tag>.wasm). Each shares apps/zig/demo_main.zig; its `cart` module is
    // the scene (or the menu), whose entry demo_main auto-detects. Keep in sync
    // with apps/zig/scenes/catalog.zig (menu list) and tools/pack_floppies.sh.
    // Cart names, index-aligned with the switch in apps/zig/cart.zig and the tags
    // in apps/zig/scenes/catalog.zig. Index 0 is the menu launcher (demo.wasm).
    // An "" entry is EXCLUDED from the build (index kept for alignment): union_intro,
    // union_main and music have been migrated to the overscan-flicker trick and are
    // re-enabled below. medium_overscan still calls the removed setMediumFullscreen()
    // — it returns once a setMediumOverscan() twin exists (separate sealed-HW work).
    const cart_names = [_][]const u8{
        "demo",              "demo-union_intro",
        "demo-union_main",   "demo-music",
        "demo-blitter",      "demo-scroll",      "demo-obj",        "demo-gem",
        "demo-st_replay",    "demo-ancool",      "demo-bladerunners", "demo-dbug",
        "demo-deltaforce",   "demo-deltaforce2", "demo-empire",     "demo-equinox",
        "demo-fallen_angels", "demo-fullscreen", "demo-ics",        "demo-leonard",
        "demo-maxi",         "", // medium_overscan (excluded)
        "demo-res_switch",   "demo-shapes",
        "demo-stcs",         "demo-tex",
        "demo-badflicker", // 26 — overscan trick done wrong (raw pokes, off-column)
        "demo-stream", // 27 — block-streams a sample off the disk
    };
    for (cart_names, 0..) |name, idx| {
        if (name.len == 0) continue; // excluded cart (see note above)
        const cart_opts = b.addOptions();
        cart_opts.addOption(usize, "index", idx);
        const cart_mod = b.createModule(.{
            .root_source_file = b.path("apps/zig/cart.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigos", .module = zigos_mod },
                .{ .name = "rom", .module = rom_mod },
                // The HW ABI header (not machine source) — lets a scene poke sealed
                // registers directly, ST-style (e.g. scenes/badflicker.zig).
                .{ .name = "hardware", .module = sdk_video },
                .{ .name = "cart_opts", .module = cart_opts.createModule() },
            },
        });
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("apps/zig/demo_main.zig"),
                .target = wasm_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zigos", .module = zigos_mod },
                    .{ .name = "rom", .module = rom_mod },
                    .{ .name = "boot_rom", .module = boot_rom_mod },
                    .{ .name = "cart", .module = cart_mod },
                },
            }),
        });
        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.import_memory = true;
        exe.stack_size = demo_stack;
        exe.initial_memory = video_shared_bytes;
        exe.max_memory = video_shared_bytes;
        exe.global_base = demo_global_base;
        installTo(b, exe, sealed_step);
    }

    // Executable boot-sector programs (ZigCart format v2): bare wasm — no ZigOS/ROM,
    // they poke the sealed video ABI directly and must stay tiny (≤ 1 KB boot sector).
    // Packed into a disk's block 0 by mkdisk (which tunes the $1234 checksum word).
    const boot_progs = [_][]const u8{"novirus"};
    for (boot_progs) |bp| {
        const exe = b.addExecutable(.{
            .name = b.fmt("boot-{s}", .{bp}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("apps/zig/boot/{s}.zig", .{bp})),
                .target = wasm_target,
                .optimize = optimize,
                .imports = &.{.{ .name = "hardware", .module = sdk_video }},
            }),
        });
        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.import_memory = true;
        exe.stack_size = demo_stack;
        exe.initial_memory = video_shared_bytes;
        exe.max_memory = video_shared_bytes;
        exe.global_base = demo_global_base;
        installTo(b, exe, sealed_step);
    }

    const demo_audio = b.addExecutable(.{
        .name = "demo-audio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/zig/demo_audio_main.zig"),
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
