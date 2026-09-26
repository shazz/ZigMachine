const std = @import("std");

const page_size = 65536; // in bytes

// Video shared main-thread memory (see machine/sdk/memmap.zig): machine-video.wasm +
// demo.wasm import the SAME WebAssembly.Memory; demo linked above the machine.
const video_shared_bytes = 112 * page_size; // 7 MiB (2 MiB demo window + VRAM + PFB + the 2 MiB ROM window; see memmap SHARED_PAGES)
const demo_global_base: u64 = 0x100000; // 1 MiB
const machine_stack = 1 * page_size;
const demo_stack = 6 * page_size;
// The ROM chip's own window (memmap ROM_RAM_BASE/TOP): 2 MiB at 5 MiB.
const rom_global_base: u64 = 0x500000;
const rom_stack = 4 * page_size;

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
    // TV analogue snow shown while a channel (+/- on the monitor) tunes in; pure,
    // so demo_main owns the plane and this stays natively testable. Its own
    // directory: a module rooted in effects/ would claim files zigos imports.
    const tvnoise_mod = b.createModule(.{
        .root_source_file = b.path("libs/zig/tvnoise/tvnoise.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    // Runtime depackers (Pack-Ice &c). ST files arrive crunched, and opening one
    // is the machine's job, not a build step's.
    const depackers_mod = b.createModule(.{
        .root_source_file = b.path("libs/zig/depackers/depackers.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });
    // Cart assets that ship ZX0-packed (libs/zig/depackers/zx0.zig, docs/DEPACK.md).
    // zx0pack runs on the HOST at build time, so a packed asset can never drift
    // from its source; a scene reaches it as @import("packed_assets").<name> and
    // depacks it at run time, with the effect chosen here (--fx).
    const zx0pack = b.addExecutable(.{
        .name = "zx0pack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zx0pack/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "zx0_pack", .module = b.createModule(.{
                .root_source_file = b.path("libs/zig/depackers/zx0_pack.zig"),
                .target = b.graph.host,
                .optimize = .ReleaseFast,
            }) }},
        }),
    });
    // Also installed (zig-out/bin/zx0pack) so build.sh can pack every asset and
    // report the ratios (tools/pack_stats.sh).
    b.installArtifact(zx0pack);
    const pack_trsi = b.addRunArtifact(zx0pack);
    pack_trsi.addArgs(&.{ "--fx", "rasters" });
    pack_trsi.addFileArg(b.path("apps/zig/assets/screens/union_intro/trsi_turn.raw"));
    const trsi_zx0 = pack_trsi.addOutputFileArg("trsi_turn.zx0");
    // The Union Demo MULTIFAKE screen depacks behind its own TEX loader panel.
    const pack_multifake = b.addRunArtifact(zx0pack);
    pack_multifake.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_multifake.addFileArg(b.path("apps/zig/assets/screens/union_multifake/loader_multifake.txt"));
    pack_multifake.addFileArg(b.path("apps/zig/assets/screens/union_multifake/multifake.bin"));
    const multifake_zx0 = pack_multifake.addOutputFileArg("union_multifake.zx0");
    // The Union Demo intro's graphics. No effect: nothing loads before the
    // remake's introScreen (main.js:262-265 goes straight to it on a black canvas).
    const pack_intro = b.addRunArtifact(zx0pack);
    pack_intro.addFileArg(b.path("apps/zig/assets/screens/union_demo_intro/intro.bin"));
    const intro_zx0 = pack_intro.addOutputFileArg("union_demo_intro.zx0");
    // The Union Demo main menu's graphics depack behind menuloader.js's TEX panel,
    // as the remake's mainMenuLoader stands before the street on every entry
    // (main.js:347, and every screen's return to MENU_LOADER).
    const pack_menu = b.addRunArtifact(zx0pack);
    pack_menu.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_menu.addFileArg(b.path("apps/zig/assets/screens/union_demo/loader_main_menu.txt"));
    pack_menu.addFileArg(b.path("apps/zig/assets/screens/union_demo/menu_assets.bin"));
    const menu_zx0 = pack_menu.addOutputFileArg("union_demo_menu.zx0");
    // The Union Demo hidden screen: its picture and mice depack behind the TEX
    // loader panel of screens/textracker/loader.js.
    const pack_textracker = b.addRunArtifact(zx0pack);
    pack_textracker.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_textracker.addFileArg(b.path("apps/zig/assets/screens/union_textracker/loader_textracker.txt"));
    pack_textracker.addFileArg(b.path("apps/zig/assets/screens/union_textracker/screen.raw"));
    const textracker_zx0 = pack_textracker.addOutputFileArg("union_textracker.zx0");
    // The Union Demo DELTA FORCE screen: its pictures and font depack behind
    // the TEX loader panel of screens/deltaforce/loader.js.
    const pack_deltaforce = b.addRunArtifact(zx0pack);
    pack_deltaforce.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_deltaforce.addFileArg(b.path("apps/zig/assets/screens/union_deltaforce/loader_deltaforce.txt"));
    pack_deltaforce.addFileArg(b.path("apps/zig/assets/screens/union_deltaforce/deltaforce.bin"));
    const deltaforce_zx0 = pack_deltaforce.addOutputFileArg("union_deltaforce.zx0");
    // The Union Demo TEX COPIER: display, font, textures and raster colours depack
    // behind the TEX loader panel of screens/texcopier/loader.js.
    const pack_texcopier = b.addRunArtifact(zx0pack);
    pack_texcopier.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_texcopier.addFileArg(b.path("apps/zig/assets/screens/union_texcopier/loader_texcopier.txt"));
    pack_texcopier.addFileArg(b.path("apps/zig/assets/screens/union_texcopier/texcopier.bin"));
    const texcopier_zx0 = pack_texcopier.addOutputFileArg("union_texcopier.zx0");
    // The Union Demo TNT3 vector screen: stars and font behind screens/tnt3/loader.js's panel.
    const pack_tnt3 = b.addRunArtifact(zx0pack);
    pack_tnt3.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_tnt3.addFileArg(b.path("apps/zig/assets/screens/union_tnt3/loader_tnt3.txt"));
    pack_tnt3.addFileArg(b.path("apps/zig/assets/screens/union_tnt3/tnt3.bin"));
    const tnt3_zx0 = pack_tnt3.addOutputFileArg("union_tnt3.zx0");
    // The Union Demo LEVEL 16 FULLSCREEN, behind screens/L16/loader.js's panel.
    const pack_l16 = b.addRunArtifact(zx0pack);
    pack_l16.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_l16.addFileArg(b.path("apps/zig/assets/screens/union_l16/loader_l16.txt"));
    pack_l16.addFileArg(b.path("apps/zig/assets/screens/union_l16/l16.bin"));
    const l16_zx0 = pack_l16.addOutputFileArg("union_l16.zx0");
    // The Union Demo TNT1 Starballs: logo, font and ball sheets behind screens/tnt1/loader.js's panel.
    const pack_tnt1 = b.addRunArtifact(zx0pack);
    pack_tnt1.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_tnt1.addFileArg(b.path("apps/zig/assets/screens/union_tnt1/loader_tnt1.txt"));
    pack_tnt1.addFileArg(b.path("apps/zig/assets/screens/union_tnt1/tnt1.bin"));
    const tnt1_zx0 = pack_tnt1.addOutputFileArg("union_tnt1.zx0");
    // The Union Demo REPS screen depacks behind its own TEX loader panel.
    const pack_reps = b.addRunArtifact(zx0pack);
    pack_reps.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_reps.addFileArg(b.path("apps/zig/assets/screens/union_reps/loader_reps.txt"));
    pack_reps.addFileArg(b.path("apps/zig/assets/screens/union_reps/reps.bin"));
    const reps_zx0 = pack_reps.addOutputFileArg("union_reps.zx0");
    // The Union Demo TNT2 screen depacks behind screens/tnt2/loader.js's panel.
    const pack_tnt2 = b.addRunArtifact(zx0pack);
    pack_tnt2.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_tnt2.addFileArg(b.path("apps/zig/assets/screens/union_tnt2/loader_tnt2.txt"));
    pack_tnt2.addFileArg(b.path("apps/zig/assets/screens/union_tnt2/tnt2.bin"));
    const tnt2_zx0 = pack_tnt2.addOutputFileArg("union_tnt2.zx0");
    // The Union Demo TCB1 BEAT DIS: both versions' pictures behind screens/beatdis/loader.js's panel.
    const pack_beatdis = b.addRunArtifact(zx0pack);
    pack_beatdis.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_beatdis.addFileArg(b.path("apps/zig/assets/screens/union_beatdis/loader_beatdis.txt"));
    pack_beatdis.addFileArg(b.path("apps/zig/assets/screens/union_beatdis/beatdis.bin"));
    const beatdis_zx0 = pack_beatdis.addOutputFileArg("union_beatdis.zx0");
    // The Union Demo TCB2 WOW!-SCROLLER: behind screens/superscroller/loader.js's panel.
    const pack_superscroller = b.addRunArtifact(zx0pack);
    pack_superscroller.addArgs(&.{ "--fx", "tex_loader", "--panel" });
    pack_superscroller.addFileArg(b.path("apps/zig/assets/screens/union_superscroller/loader_superscroller.txt"));
    pack_superscroller.addFileArg(b.path("apps/zig/assets/screens/union_superscroller/superscroller.bin"));
    const superscroller_zx0 = pack_superscroller.addOutputFileArg("union_superscroller.zx0");
    // THE REPLICANTS / Emlyn Hughes: the big logo and the font. 769,580 bytes
    // pack to 17,862, so the cart embeds the packed form and depacks in init().
    const pack_emlyn = b.addRunArtifact(zx0pack);
    pack_emlyn.addFileArg(b.path("apps/zig/assets/screens/replicants_emlyn/emlyn.bin"));
    const emlyn_zx0 = pack_emlyn.addOutputFileArg("replicants_emlyn.zx0");
    // THE SILENTS / HYBRID GLENZ (CODEF 417): logo + font + 3 text overlays.
    const pack_tsl = b.addRunArtifact(zx0pack);
    pack_tsl.addFileArg(b.path("apps/zig/assets/screens/tsl_hybridglenz/tsl.bin"));
    const tsl_zx0 = pack_tsl.addOutputFileArg("tsl_hybridglenz.zx0");
    const packed_files = b.addWriteFiles();
    // SWEDISH NEW YEAR (CODEF 295): every picture and font, one blob each. The
    // scene depacks only the part on screen's set, into one working buffer
    // (apps/zig/scenes/swedish_newyear/assets.zig names the sets).
    const SWEDISH = [_][]const u8{ "main", "font7", "block", "banner", "syncfont", "logo", "sync1", "sync2", "tcb", "kh", "kh2", "edge", "tcblogo", "wizcoder", "ancool", "omain", "omega", "ofont", "vumeter", "atari" };
    var swedish_decl: []const u8 = "pub const swedish_newyear = struct {\n";
    for (SWEDISH) |name| {
        const file = b.fmt("swedish_newyear_{s}.zx0", .{name});
        const pack_swe = b.addRunArtifact(zx0pack);
        pack_swe.addFileArg(b.path(b.fmt("apps/zig/assets/screens/swedish_newyear/{s}.raw", .{name})));
        _ = packed_files.addCopyFile(pack_swe.addOutputFileArg(file), file);
        swedish_decl = b.fmt("{s}    pub const {s} = @embedFile(\"{s}\");\n", .{ swedish_decl, name, file });
    }
    swedish_decl = b.fmt("{s}}};\n", .{swedish_decl});
    _ = packed_files.addCopyFile(trsi_zx0, "trsi_turn.zx0");
    _ = packed_files.addCopyFile(multifake_zx0, "union_multifake.zx0");
    _ = packed_files.addCopyFile(textracker_zx0, "union_textracker.zx0");
    _ = packed_files.addCopyFile(intro_zx0, "union_demo_intro.zx0");
    _ = packed_files.addCopyFile(menu_zx0, "union_demo_menu.zx0");
    _ = packed_files.addCopyFile(deltaforce_zx0, "union_deltaforce.zx0");
    _ = packed_files.addCopyFile(texcopier_zx0, "union_texcopier.zx0");
    _ = packed_files.addCopyFile(tnt3_zx0, "union_tnt3.zx0");
    _ = packed_files.addCopyFile(l16_zx0, "union_l16.zx0");
    _ = packed_files.addCopyFile(tnt1_zx0, "union_tnt1.zx0");
    _ = packed_files.addCopyFile(reps_zx0, "union_reps.zx0");
    _ = packed_files.addCopyFile(tnt2_zx0, "union_tnt2.zx0");
    _ = packed_files.addCopyFile(beatdis_zx0, "union_beatdis.zx0");
    _ = packed_files.addCopyFile(superscroller_zx0, "union_superscroller.zx0");
    _ = packed_files.addCopyFile(emlyn_zx0, "replicants_emlyn.zx0");
    _ = packed_files.addCopyFile(tsl_zx0, "tsl_hybridglenz.zx0");
    // MPP TRUECOLOR's gallery: one blob per picture and mode (tools/mpp_convert.py).
    // Unpacked they overflow the cart window, so the scene depacks only the one on
    // screen. MPP_PICTURES follows the converter's PICTURES list.
    const MPP_PICTURES = 5;
    const MPP_MODES = 3;
    var mpp_decl: []const u8 = "pub const mpp_truecolor = [_][3][]const u8{\n";
    for (0..MPP_PICTURES) |p| {
        mpp_decl = b.fmt("{s}    .{{", .{mpp_decl});
        for (1..MPP_MODES + 1) |m| {
            const name = b.fmt("mpp_p{d}_m{d}.zx0", .{ p, m });
            const pack_mpp = b.addRunArtifact(zx0pack);
            pack_mpp.addFileArg(b.path(b.fmt("apps/zig/assets/screens/mpp_truecolor/p{d}_m{d}.bin", .{ p, m })));
            _ = packed_files.addCopyFile(pack_mpp.addOutputFileArg(name), name);
            mpp_decl = b.fmt("{s} @embedFile(\"{s}\"),", .{ mpp_decl, name });
        }
        mpp_decl = b.fmt("{s} }},\n", .{mpp_decl});
    }
    const packed_assets_mod = b.createModule(.{
        .root_source_file = packed_files.add("packed_assets.zig", b.fmt(
            \\// Generated by build.zig: ZX0-packed cart assets.
            \\pub const trsi_turn = @embedFile("trsi_turn.zx0");
            \\pub const union_multifake = @embedFile("union_multifake.zx0");
            \\pub const union_textracker = @embedFile("union_textracker.zx0");
            \\pub const union_demo_intro = @embedFile("union_demo_intro.zx0");
            \\pub const union_demo_menu = @embedFile("union_demo_menu.zx0");
            \\pub const union_deltaforce = @embedFile("union_deltaforce.zx0");
            \\pub const union_texcopier = @embedFile("union_texcopier.zx0");
            \\pub const union_tnt3 = @embedFile("union_tnt3.zx0");
            \\pub const union_l16 = @embedFile("union_l16.zx0");
            \\pub const union_tnt1 = @embedFile("union_tnt1.zx0");
            \\pub const union_reps = @embedFile("union_reps.zx0");
            \\pub const union_tnt2 = @embedFile("union_tnt2.zx0");
            \\pub const union_beatdis = @embedFile("union_beatdis.zx0");
            \\pub const union_superscroller = @embedFile("union_superscroller.zx0");
            \\pub const replicants_emlyn = @embedFile("replicants_emlyn.zx0");
            \\pub const tsl_hybridglenz = @embedFile("tsl_hybridglenz.zx0");
            \\{s}{s}}};
            \\
        , .{ swedish_decl, mpp_decl })),
        .target = wasm_target,
        .optimize = optimize,
    });
    const players_mod = b.createModule(.{
        .root_source_file = b.path("libs/zig/players/players.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audio_hw", .module = sdk_audio },
            .{ .name = "depackers", .module = depackers_mod },
        },
    });
    // The SNDH player needs a 68000, because an SNDH IS 68000 code: Musashi runs
    // it and libs/zig/players/sndh_player.zig traps its PSG writes to the sealed
    // YM chip. Musashi's opcode table is machine-generated, so m68kmake is built
    // for the HOST and run here rather than checking 800 KB of C into the repo.
    addMusashi(b, players_mod);
    // rom/ — reference system software (GEM). Linked into rom.wasm (rom_chip
    // below), NOT into carts: a cart gets rom_sdk, the flat ABI header.
    const rom_mod = b.createModule(.{
        .root_source_file = b.path("rom/rom.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigos", .module = zigos_mod },
            .{ .name = "hardware", .module = sdk_video },
        },
    });
    // rom/sdk/ — the FLAT, app-facing ROM ABI. Apps import this as `rom_sdk`; only
    // numbers cross its entry points, which is what lets the bodies live in
    // rom.wasm (see rom_chip below) and lets a C or Rust app call GEM.
    const rom_sdk_mod = b.createModule(.{
        .root_source_file = b.path("rom/sdk/rom.zig"),
        .target = wasm_target,
        .optimize = optimize,
        // NO `rom` import: this is a pure header of `extern` declarations now, and
        // an app that linked the ROM's internals would defeat the whole split.
        .imports = &.{
            .{ .name = "zigos", .module = zigos_mod },
            .{ .name = "hardware", .module = sdk_video },
        },
    });

    // rom.wasm — the ROM CHIP. Its own module, its own RAM window above the video
    // region, linked against the sealed HW ABI exactly like a cart. It exports the
    // flat ABI declared in rom/sdk/rom.zig; the host wires an app's env to it.
    const rom_chip = b.addExecutable(.{
        .name = "rom",
        .root_module = b.createModule(.{
            .root_source_file = b.path("rom/rom_main.zig"),
            .target = wasm_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigos", .module = zigos_mod },
                .{ .name = "rom", .module = rom_mod },
                .{ .name = "hardware", .module = sdk_video },
                // romDepack: a disk's cart is stored ZX0-packed and the ROM unpacks it.
                .{ .name = "depackers", .module = depackers_mod },
            },
        }),
    });
    rom_chip.entry = .disabled;
    rom_chip.rdynamic = true;
    rom_chip.import_memory = true;
    rom_chip.stack_size = rom_stack;
    rom_chip.initial_memory = video_shared_bytes;
    rom_chip.max_memory = video_shared_bytes;
    rom_chip.global_base = rom_global_base;
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(
        rom_chip.getEmittedBin(), .{ .custom = "../docs" }, "rom.wasm").step);

    // machine/boot.zig — the boot ROM (POST screen). Machine firmware: depends ONLY
    // on the HW ABI, no libs. Still app-linked into every cart; moving it inside
    // machine-video.wasm is an open idea, unrelated to the ROM chip.
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
    // An "" entry EXCLUDES a cart from the build (the index is kept, so it stays
    // aligned with cart.zig and catalog.zig). None are excluded today.
    const cart_names = [_][]const u8{
        "demo",              "demo-union_intro",
        "demo-union_main",   "demo-music",
        "demo-blitter",      "demo-scroll",      "demo-obj",        "demo-gem",
        "demo-st_replay",    "demo-ancool",      "demo-bladerunners", "demo-dbug",
        "demo-deltaforce",   "demo-deltaforce2", "demo-empire",     "demo-equinox",
        "demo-fallen_angels", "demo-fullscreen", "demo-ics",        "demo-leonard",
        "demo-maxi",         "demo-medium_overscan",
        "demo-res_switch",   "demo-shapes",
        "demo-stcs",         "demo-tex",
        "demo-badflicker", // 26 — overscan trick done wrong (raw pokes, off-column)
        "demo-stream", // 27 — block-streams a sample off the disk
        "demo-noextra", // 28 — NoExtra Team / DHS Megademo 2005 (CODEF screen 198)
        "demo-replicants_dd2", // 29 — Replicants / Double Dragon II (CODEF screen 515)
        "demo-supplex_fs2", // 30 — Supplex / Flight Simulator II NDD (CODEF screen 525)
        "demo-replicants_garfield", // 31 — The Replicants / Garfield (CODEF screen 28)
        "demo-ulm_spoon_distorter", // 32 — ULM / Dark Side of the Spoon, Parallax Distorter (CODEF screen 287)
        "demo-replicants", // 33 — REPS OLD: the pre-CODEF Replicants/Garfield, kept to compare with 31
        "demo-cuddly_starwars", // 34 — The Carebears / Starwars Scroller, Cuddly Demos (CODEF screen 360)
        "demo-replicants_kickoff2", // 35 — The Replicants / Kick Off 2 crack intro (CODEF screen 168)
        "demo-dyno_paradis3", // 36 — Dyno / ParaDis3, Parallax Distorter (CODEF screen 470)
        "demo-mandelbrot", // 37 — the fractal channel from the original gh-page
        "demo-stniccc", // 38 — Oxygene / STNICCC 2000, the polygon flight (scene1.bin stream)
        "demo-tex_neoshow", // 39 — The Exceptions / Super Neo Demo Show (CODEF screen 473)
        "demo-elite_snooker", // 40 — ELITE / Jimmy White Snooker crack intro (CODEF screen 422)
        "demo-union_demo", // 41 — The Union / Union Demo main menu (melonJS remake hub)
        "demo-tutorial", // 42 — docs/TUTORIAL.md: the newcomer's first screen (Zig version)
        "demo-mpp_truecolor", // 43 — truecolor picture via per-line palettes on 1 and 4 planes (MPP)
        "demo-union_multifake", // 44 — The Union Demo / TCB3 MULTIFAKE scroller (melonJS remake)
        "demo-union_textracker", // 45 — The Union Demo hidden screen, TEX's Sample-Mon ST (melonJS remake)
        "demo-union_intro_screen", // 46 — The Union Demo intro screen (melonJS remake, screens/intro): hub-only
        "demo-union_deltaforce", // 47 — The Union Demo / DELTA FORCE Sphericool screen (melonJS remake)
        "demo-union_texcopier", // 48 — The Union Demo / COPIER TEX, TEX's copy program (melonJS remake)
        "demo-union_tnt3", // 49 — The Union Demo / TNT3, the TNT Crew's vector screen (melonJS remake)
        "demo-union_l16", // 50 — The Union Demo / LEVEL 16 FULLSCREEN (melonJS remake)
        "demo-union_tnt1", // 51 — The Union Demo / TNT1, TNT-Crew Starballs (melonJS remake)
        "demo-union_reps", // 52 — The Union Demo / REPS, The Replicants' wobbly sprites (melonJS remake)
        "demo-union_tnt2", // 53 — The Union Demo / TNT2, the TNT-Crew's parallax superscroller (melonJS remake)
        "demo-union_beatdis", // 54 — The Union Demo / TCB1 BEAT DIS, 1 MB and 1/2 MB (melonJS remake)
        "demo-union_superscroller", // 55 — The Union Demo / TCB2 WOW!-SCROLLER (melonJS remake)
        "demo-tutorial_steps", // 56 — tutorial.zig stopped at any step, for docs/TUTORIAL.html
        "demo-automation442", // 57 — AUTOMATION CD 442 PART A, the Ghostbusters II menu (CODEF screen 420)
        "demo-big_demo", // 58 — The Exceptions / The B.I.G. Demo jukebox (CODEF screen 23)
        "demo-tlb_spoon", // 59 — THE LOST BOYS / THE TWIDDLE DEMO, ULM Megademo (CODEF screen 122)
        "demo-tcb_colorshock", // 60 — THE CAREBEARS / COLORSHOCK 2, The Cuddly Demos (CODEF screen 172)
        "demo-vex", // 61 — vEctRoniX / VEX 2025, the GTA VI cracktro (ported from the ST binary)
        "demo-replicants_emlyn", // 62 — The Replicants / Emlyn Hughes Intl Soccer cracktro (CODEF screen 17)
        "demo-scrolllab", // 63 — scrolltext distortion lab: ten filters over one text, for picking one
        "demo-tsl_hybridglenz", // 64 — THE SILENTS / HYBRID GLENZ, blitter glenz vectors (CODEF screen 417)
        "demo-polkadots", // 65 — POLKA DOTS: NoNameNo's halftone dot-matrix torus (CODEF screen 81)
        "demo-elite_cfsr", // 66 — ELITE / Challenge Foot Senior crack intro (ported from the ST binary)
        "demo-rno_sodium", // 67 — RNO / SODIUM, Altparty intro (ported from the ST binary)
        "demo-rno_natrium", // 68 — RNO / NATRIUM, 96k intro (ported from the ST binary)
        "demo-dhs_0pxl0reg", // 69 — DHS / (n)0 PIXELS (n)0 REGRETS, zero bitplanes on the BEAM (ported from the ST binary)
        "demo-trsi_transarctica", // 70 — TRSI / TRANSARCTICA Falcon030 cracktro (ported from the Falcon binary)
        "demo-north_south", // 71 — Infogrames / NORTH & SOUTH, the battle, playable (ported from the ST program)
        "demo-joust", // 72 — JOUST, Atari Corp 1986: the game, ported from JOUST.PRG through its reference model
        "demo-tcb_spreadpoint", // 73 — The Carebears / The Spreadpoint Demo (CODEF screen 469)
        "demo-stcs_css3", // 74 — STCS / Tsunoo Rhilty 3rd CSS Convention intro (ported from the ST binary)
        "demo-tcb_weirddream", // 75 — TCB + REPLICANTS / WEIRD DREAM crack intro (CODEF screen 345)
        "demo-swedish_newyear", // 76 — SYNC / AN COOL / TCB / OMEGA, Swedish New Year Demo: menu + 5 screens (CODEF screen 295)
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
                // NO `rom`: a cart links the ROM's flat ABI header, never its
                // internals — those live in rom.wasm now. Handing rom_mod to carts
                // made the separation a convention that one @import("rom") could
                // silently undo, re-linking the whole toolkit into that cart.
                .{ .name = "rom_sdk", .module = rom_sdk_mod },
                // The HW ABI header (not machine source) — lets a scene poke sealed
                // registers directly, ST-style (e.g. scenes/badflicker.zig).
                .{ .name = "hardware", .module = sdk_video },
                .{ .name = "cart_opts", .module = cart_opts.createModule() },
                // Run-time depackers + the assets build.zig packs (see zx0pack above).
                .{ .name = "depackers", .module = depackers_mod },
                .{ .name = "packed_assets", .module = packed_assets_mod },
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
                    .{ .name = "rom_sdk", .module = rom_sdk_mod }, // the ABI, not the ROM
                    .{ .name = "boot_rom", .module = boot_rom_mod },
                    .{ .name = "cart", .module = cart_mod },
                    .{ .name = "tvnoise", .module = tvnoise_mod },
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
    // A GENERIC boot program lives in apps/zig/boot/; one that talks about a
    // particular screen's keys lives with that screen, so the source path is
    // spelled out here rather than derived from the name.
    const boot_progs = [_]struct { name: []const u8, src: []const u8 }{
        .{ .name = "novirus", .src = "apps/zig/boot/novirus.zig" },
        .{ .name = "replicants_emlyn", .src = "apps/zig/scenes/replicants_emlyn/boot.zig" },
    };
    for (boot_progs) |bp| {
        const exe = b.addExecutable(.{
            .name = b.fmt("boot-{s}", .{bp.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(bp.src),
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

// Musashi (kstenerud, MIT — see libs/c/musashi/README.md) compiled into a module
// as the 68000 the SNDH player drives.
//
// Its opcode table is machine-generated, so m68kmake is built for the HOST and
// run here rather than checking 800 KB of generated C into the repo. Include
// order matters: config/ shadows upstream's m68kconf.h with our 68000-only
// settings, freestanding/ supplies the few libc headers wasm32-freestanding
// lacks, and the generated m68kops.h has to be findable as well.
fn addMusashi(b: *std.Build, mod: *std.Build.Module) void {
    const maker = b.addExecutable(.{
        .name = "m68kmake",
        .root_module = b.createModule(.{ .target = b.graph.host, .optimize = .ReleaseFast }),
    });
    maker.root_module.addCSourceFile(.{
        .file = b.path("libs/c/musashi/upstream/m68kmake.c"),
        .flags = &.{"-w"}, // 1998 C, and not ours to clean up
    });
    maker.root_module.link_libc = true;

    const run = b.addRunArtifact(maker);
    const generated = run.addOutputDirectoryArg("musashi");
    run.addFileArg(b.path("libs/c/musashi/upstream/m68k_in.c"));

    mod.addIncludePath(b.path("libs/c/musashi/config"));
    mod.addIncludePath(b.path("libs/c/musashi/freestanding"));
    mod.addIncludePath(b.path("libs/c/musashi/upstream"));
    mod.addIncludePath(generated);

    // Absolute: a relative -include lands in the compilation's dependency list
    // as a path the cache cannot resolve, and every C step fails CacheCheckFailed.
    const config_h = b.pathJoin(&.{ b.build_root.path.?, "libs/c/musashi/config/zm_musashi.h" });
    const flags = [_][]const u8{ "-ffreestanding", "-fno-builtin", "-w", "-include", config_h };
    mod.addCSourceFile(.{ .file = generated.path(b, "m68kops.c"), .flags = &flags });
    mod.addCSourceFile(.{ .file = b.path("libs/c/musashi/upstream/m68kcpu.c"), .flags = &flags });
    mod.addCSourceFile(.{ .file = b.path("libs/c/musashi/upstream/softfloat/softfloat.c"), .flags = &flags });
    mod.addCSourceFile(.{ .file = b.path("libs/c/musashi/freestanding/stubs.c"), .flags = &flags });
}
