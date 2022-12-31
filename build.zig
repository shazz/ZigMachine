const std = @import("std");

const page_size = 65536; // in bytes
const nb_pages = 25;


pub fn build(b: *std.build.Builder) void {

    // Adds the option -Drelease=[bool] to create a release build, which we set to be ReleaseSmall by default.
    b.setPreferredReleaseMode(.ReleaseSmall);

    const build_native = b.option(bool, "native", "Build the native executable.") orelse false;
    const build_wasm = b.option(bool, "wasm", "Build the wasm library.") orelse false;

    if (build_wasm) {

        // Standard release options allow the person running `zig build` to select
        // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
        const mode = b.standardReleaseOptions();

        const bootloader_step = b.step("bootloader", "Compiles bootloader.zig");
        const bootloader_lib = b.addSharedLibrary("bootloader", "./bootloader.zig", .unversioned);

        bootloader_lib.setBuildMode(mode);
        bootloader_lib.setTarget(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .abi = .musl,
        });
        
        // https://github.com/ziglang/zig/issues/8633
        bootloader_lib.import_memory = true; // import linear memory from the environment
        bootloader_lib.initial_memory = nb_pages * page_size; // initial size of the linear memory (1 page = 64kB)
        bootloader_lib.max_memory = nb_pages * page_size; // maximum size of the linear memory
        bootloader_lib.global_base = 6560; // offset in linear memory to place global data

        bootloader_lib.setOutputDir(".");
        bootloader_lib.install();
        bootloader_step.dependOn(&bootloader_lib.step);        
    }

    if (build_native) {
        const exe = b.addExecutable("bootloader", "native.zig");
        const target = b.standardTargetOptions(.{});
        const mode = b.standardReleaseOptions();
        const exe_step = b.step("bootloader", "Compiles bootloader.zig");

        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.install();
        exe_step.dependOn(&exe.step);    

    }


}
