// --------------------------------------------------------------------------
// demo.wasm entry point (OPEN — the coder's binary).
//
// ZigOS + effects + the selected scene, compiled against sdk/hardware.zig. Runs
// on the main thread sharing ONE WebAssembly.Memory with the sealed
// machine-video.wasm. It writes framebuffers/palettes/registers into the shared
// video region and never touches machine source.
//
// Per-frame host loop:
//   machine.hwClear()  ->  demo.frame(dt)  ->  machine.hwRenderPlane(i) per
//   enabled plane  ->  host blits PFB to canvas[i].
// The machine calls back into demo.hblDispatch() at each HBL point.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos"); // the open ZigOS library (named module)
const ZigOS = zg.ZigOS;
const Console = zg.Console;
const Demo = @import("floppy.zig").Demo;

const VERSION = "0.2-sealed";

const Direction = enum(u8) { Up = 0, Down = 1, Left = 2, Right = 3, Null = 4 };

var zigos: ZigOS = undefined;
var demo: Demo = undefined;

// --------------------------------------------------------------------------
// Boot: ZigOS discovers the machine's video base and sets up its views, then
// the scene initialises its planes/palettes.
// --------------------------------------------------------------------------
export fn boot() void {
    Console.log("ZigMachine demo v.{s}\n", .{VERSION});
    zigos.init();
    demo.init(&zigos);
}

// Compute one frame: the scene draws into the (shared) logical framebuffers.
export fn frame(elapsed_time: f32) void {
    demo.update(&zigos, elapsed_time);
    demo.render(&zigos, elapsed_time);
}

// The sealed machine routes each HBL point here (integer ids only).
export fn hblDispatch(id: u32, plane: u32, line: u32, x: u32) void {
    zigos.dispatchHBL(id, plane, line, x);
}

// The host gates blits on this (the machine renders a plane unconditionally).
export fn isPlaneEnabled(id: u8) bool {
    return zigos.lfbs[id].is_enabled;
}

// Optional per-scene shading/mode switch (keys 1-4 in sealed-loader.js). Only
// scenes that declare setShadeMode react; others ignore it (compile-time guard).
export fn setShadeMode(mode: u32) void {
    if (@hasDecl(Demo, "setShadeMode")) demo.setShadeMode(mode);
}

// Pointer state from the host (mouse over the canvas), in 320x200 visible coords.
// Only scenes that declare pointer() react (e.g. the GEM windowing app).
export fn pointer(x: i32, y: i32, buttons: u32) void {
    if (@hasDecl(Demo, "pointer")) demo.pointer(x, y, buttons);
}

export fn input(dir: Direction) void {
    switch (dir) {
        .Up => Console.log("up", .{}),
        .Down => Console.log("down", .{}),
        .Left => Console.log("left", .{}),
        .Right => Console.log("right", .{}),
        .Null => {},
    }
}

// --------------------------------------------------------------------------
// Audio mirror surface — JS copies the audio thread's YM registers, active
// player mode, and per-channel scopes into these ZigOS fields each frame so the
// music scene can visualise the chip. (Audio itself is still the standalone
// audio.wasm module; splitting it into machine-audio.wasm + ZigOS players is the
// next step of the seal.)
// --------------------------------------------------------------------------
export fn getYmRegsPointer() [*]u8 {
    return @ptrCast(&zigos.ym_regs);
}
export fn getAudioModePointer() [*]u8 {
    return @ptrCast(&zigos.audio_mode);
}
export fn getScopesPointer() [*]f32 {
    return @ptrCast(&zigos.scopes);
}
