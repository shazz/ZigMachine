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
const Cart = @import("floppy.zig").Demo; // the selected RAM cart (scene)
const BootRom = @import("scenes/boot.zig").Demo; // the ZigMachine boot screen (Falcon-style)

const VERSION = "0.2-sealed";

// The ZigMachine boot screen plays for this many frames before the RAM cart is
// inserted (~3s at 60fps). With the boot effect's RAM_STEP=3 slowdown the
// memory-test sequence completes around frame ~153; the rest is a short hold.
const BOOT_FRAMES: u32 = 180;

const Direction = enum(u8) { Up = 0, Down = 1, Left = 2, Right = 3, Null = 4, Fire = 5, Back = 6 };

var zigos: ZigOS = undefined;
var cart: Cart = undefined;
var boot_rom: BootRom = undefined;
var booted: bool = false; // false = boot screen showing; true = cart running
var boot_frames: u32 = 0;

// --------------------------------------------------------------------------
// Boot: ZigOS discovers the machine's video base and sets up its views, then
// the scene initialises its planes/palettes.
// --------------------------------------------------------------------------
export fn boot() void {
    Console.log("ZigMachine demo v.{s}\n", .{VERSION});
    zigos.init();
    boot_rom.init(&zigos); // ZigMachine boot screen first — cart is inserted after it
}

// Reset the machine to a clean state and insert & start the selected RAM cart.
fn startCart() void {
    if (booted) return;
    zigos.resetForScene(); // clean machine state (planes/palette/registers/HBL) for the cart
    cart.init(&zigos);
    booted = true;
}

// Compute one frame. While booting, draw the boot screen; when it's done, start
// the selected RAM cart. ESC (see skipBoot) ends the boot screen early.
export fn frame(elapsed_time: f32) void {
    if (!booted) {
        boot_rom.update(&zigos, elapsed_time);
        boot_rom.render(&zigos, elapsed_time);
        boot_frames += 1;
        if (boot_frames >= BOOT_FRAMES) startCart();
        return;
    }
    cart.update(&zigos, elapsed_time);
    cart.render(&zigos, elapsed_time);
}

// Skip the boot screen (ESC in the loader): jump straight to the RAM cart.
export fn skipBoot() void {
    startCart();
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
    if (booted and @hasDecl(Cart, "setShadeMode")) cart.setShadeMode(mode);
}

// Pointer state from the host (mouse over the canvas), in 320x200 visible coords.
// Only scenes that declare pointer() react (e.g. the GEM windowing app).
export fn pointer(x: i32, y: i32, buttons: u32) void {
    if (booted and @hasDecl(Cart, "pointer")) cart.pointer(x, y, buttons);
}

// Sample-buffer bridge: a scene (e.g. ST Replay) that declares sampleBuf() lets
// the host copy a real sample into it for display. Scenes without it report len 0.
var g_no_sample: [1]u8 = .{0};
export fn getSampleBufPtr() [*]u8 {
    if (booted and @hasDecl(Cart, "sampleBuf")) return cart.sampleBuf();
    return &g_no_sample;
}
export fn getSampleBufLen() u32 {
    if (booted and @hasDecl(Cart, "sampleBuf")) return @intCast(Cart.sampleLen());
    return 0;
}

// Directional / action input from the host. Forwarded to scenes that declare
// input() (e.g. the effects menu: arrows move, Fire launches, Back returns).
export fn input(dir: Direction) void {
    if (booted and @hasDecl(Cart, "input")) cart.input(@intFromEnum(dir));
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
