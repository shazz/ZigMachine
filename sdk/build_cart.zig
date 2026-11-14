// --------------------------------------------------------------------------
// The KESTREL SDK's cart builder (docs/SDK.md): a cart that lives OUTSIDE this
// repository, in a coder's own directory with its own build.zig, which depends
// on this repository as a Zig package (a path dependency) and calls addCart.
//
// Why a package and not a slot in build.zig's cart matrix: the coder's project
// then has a real build.zig, so ZLS resolves @import("zigos") in their files,
// and nothing in this repository is edited to add a cart. The cart is built
// exactly as the matrix builds one (apps/zig/demo_main.zig around the scene,
// the same named modules, the same wasm memory layout) but only that cart:
// machine-video.wasm and rom.wasm are NOT rebuilt, the SDK ships them, because
// the board's system image (system.rv32) was built from those very bytes.
//
// This repeats the few module definitions of build.zig a cart needs. If
// build.zig gives demo_main another import, the gate's SDK harness
// (apps/sdk_check.mjs) fails to build the template, which keeps the two in step.
// --------------------------------------------------------------------------
const std = @import("std");
const memmap = @import("../machine/sdk/memmap.zig");

const page_size = 65536;
const Module = std.Build.Module;

pub const CartOptions = struct {
    /// The cart's tag: the output is demo-<name>.wasm. Lower case, digits, '_'.
    name: []const u8,
    /// The scene file: it declares `pub const Demo` (or App / Raster) with
    /// init/update/render, as every scene of apps/zig/scenes does.
    root_source_file: std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode = .ReleaseSmall,
};

pub const Cart = struct {
    exe: *std.Build.Step.Compile,
    /// The scene's own module: add imports to it (an asset module, say).
    scene: *Module,
};

/// The shared modules a cart links: the HW ABI header, ZigOS, the ROM's flat ABI.
const Libs = struct { hardware: *Module, zigos: *Module, rom_sdk: *Module, depackers: *Module, boot_rom: *Module, tvnoise: *Module, kos_gemdos: *Module };

fn libs(b: *std.Build, dep: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Libs {
    const m = struct {
        fn f(bb: *std.Build, d: *std.Build.Dependency, path: []const u8, t: std.Build.ResolvedTarget, o: std.builtin.OptimizeMode) *Module {
            return bb.createModule(.{ .root_source_file = d.path(path), .target = t, .optimize = o });
        }
    }.f;
    const l: Libs = .{
        .hardware = m(b, dep, "machine/sdk/hardware.zig", target, optimize),
        .zigos = m(b, dep, "libs/zig/zigos.zig", target, optimize),
        .rom_sdk = m(b, dep, "rom/sdk/rom.zig", target, optimize),
        .depackers = m(b, dep, "libs/zig/depackers/depackers.zig", target, optimize),
        .boot_rom = m(b, dep, "machine/boot.zig", target, optimize),
        .tvnoise = m(b, dep, "libs/zig/tvnoise/tvnoise.zig", target, optimize),
        .kos_gemdos = m(b, dep, "rom/kos/gemdos_cart.zig", target, optimize), // files on A: and C: (docs/KOS_GEMDOS.md)
    };
    l.zigos.addImport("hardware", l.hardware);
    l.zigos.addImport("depackers", l.depackers); // zg.bard.job's server depacks ZX0
    l.rom_sdk.addImport("zigos", l.zigos);
    l.rom_sdk.addImport("hardware", l.hardware);
    l.boot_rom.addImport("hardware", l.hardware);
    return l;
}

/// apps/zig/cart.zig's uniform entry, for one scene: the module demo_main imports as "cart".
fn cartShim(b: *std.Build, scene: *Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *Module {
    const shim = b.addWriteFiles().add("cart.zig",
        \\const scene = @import("scene");
        \\pub const Cart = if (@hasDecl(scene, "Demo")) scene.Demo
        \\else if (@hasDecl(scene, "App")) scene.App
        \\else scene.Raster;
        \\
    );
    return b.createModule(.{
        .root_source_file = shim,
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "scene", .module = scene }},
    });
}

/// build.zig's cart link options, from the same memory map.
fn linkLikeTheMatrix(exe: *std.Build.Step.Compile) void {
    const shared = @as(u64, memmap.SHARED_PAGES) * page_size;
    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.import_memory = true;
    exe.stack_size = 6 * page_size;
    exe.initial_memory = shared;
    exe.max_memory = shared;
    exe.global_base = memmap.CART_RAM_BASE;
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 32) return false;
    for (name) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
    return true;
}

/// The coder's scene: it sees what a scene of apps/zig/scenes sees, minus the repo's own assets.
fn sceneModule(b: *std.Build, opts: CartOptions, l: Libs, target: std.Build.ResolvedTarget) *Module {
    return b.createModule(.{
        .root_source_file = opts.root_source_file,
        .target = target,
        .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "zigos", .module = l.zigos },
            .{ .name = "rom_sdk", .module = l.rom_sdk },
            .{ .name = "hardware", .module = l.hardware },
            .{ .name = "depackers", .module = l.depackers },
            .{ .name = "kos_gemdos", .module = l.kos_gemdos },
        },
    });
}

/// Builds demo-<name>.wasm from the coder's scene into the prefix's root
/// (zig-out/demo-<name>.wasm), plus the host tools `make floppy` / `make board` use.
pub fn addCart(b: *std.Build, dep: *std.Build.Dependency, opts: CartOptions) Cart {
    if (!validName(opts.name)) std.debug.panic("addCart: bad cart name '{s}' (a-z, 0-9, _; 1-32 chars)", .{opts.name});
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding, .abi = .musl });
    const l = libs(b, dep, target, opts.optimize);
    const scene = sceneModule(b, opts, l, target);
    const exe = b.addExecutable(.{
        .name = b.fmt("demo-{s}", .{opts.name}),
        .root_module = b.createModule(.{
            .root_source_file = dep.path("apps/zig/demo_main.zig"),
            .target = target,
            .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "zigos", .module = l.zigos },
                .{ .name = "rom_sdk", .module = l.rom_sdk },
                .{ .name = "boot_rom", .module = l.boot_rom },
                .{ .name = "cart", .module = cartShim(b, scene, target, opts.optimize) },
                .{ .name = "tvnoise", .module = l.tvnoise },
            },
        }),
    });
    linkLikeTheMatrix(exe);
    b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .prefix } }).step);
    addHostTools(b, dep);
    return .{ .exe = exe, .scene = scene };
}

/// zig-out/bin/zx0pack (a disk carries its cart ZX0-packed: tools/mkdisks.sh) and
/// zig-out/rt/zrt.o: Zig's compiler_rt for the cart CPU (rv32imf, ilp32f, no C
/// extension), the board cart's libgcc when the riscv gcc has no rv32imf/ilp32f
/// multilib (fpga/cycles/split.mk CART_RTLIB).
fn addHostTools(b: *std.Build, dep: *std.Build.Dependency) void {
    const zx0pack = b.addExecutable(.{
        .name = "zx0pack",
        .root_module = b.createModule(.{
            .root_source_file = dep.path("tools/zx0pack/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "zx0_pack", .module = b.createModule(.{
                .root_source_file = dep.path("libs/zig/depackers/zx0_pack.zig"),
                .target = b.graph.host,
                .optimize = .ReleaseFast,
            }) }},
        }),
    });
    b.installArtifact(zx0pack);
    const rv32imf = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = std.Target.riscv.featureSet(&.{ .m, .f }),
    });
    // compiler_rt.zig itself, as one object (a static library would wrap it in an archive whose
    // member names are paths, which binutils' ar cannot extract); sdk/zrt_cart.sh trims it.
    const zig_lib = b.graph.zig_lib_directory.path orelse ".";
    const zrt = b.addObject(.{
        .name = "zrt",
        .root_module = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ zig_lib, "compiler_rt.zig" }) },
            .target = rv32imf,
            .optimize = .ReleaseFast,
            .stack_protector = false,
            .strip = true,
        }),
    });
    zrt.link_function_sections = true; // one section a helper, for zrt_cart.sh's --gc-sections
    zrt.link_data_sections = true;
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(zrt.getEmittedBin(), .{ .custom = "rt" }, "zrt.o").step);
}
