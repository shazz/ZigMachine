// --------------------------------------------------------------------------
// machine-video.wasm entry point (SEALED).
//
// Exports the hw* video ABI (see sdk/hardware.zig). Instantiated by the host on
// the main thread, sharing ONE WebAssembly.Memory with the demo module. Imports
// only env.memory and env.hblDispatch (routed by the host to the demo module).
// --------------------------------------------------------------------------
const video = @import("video.zig");
const blitter = @import("blitter.zig");
const memmap = @import("sdk/memmap.zig");

export fn hwVideoBase() i32 {
    return @intCast(video.basePtr());
}
export fn hwInit() void {
    video.reset();
}
export fn hwClear() void {
    video.clear();
}
export fn hwRenderPlane(plane: u32) void {
    video.renderPlane(@intCast(plane));
}
export fn hwBlit() void {
    blitter.execute();
}
export fn hwPhysicalPtr() i32 {
    return @intCast(video.pfbBytePtr());
}
export fn hwPlanesNumber() u8 {
    return memmap.NB_PLANES;
}
export fn hwPhysWidth() u32 {
    return memmap.RASTER_WIDTH; // 800 — the actual raster the host blits
}
export fn hwPhysHeight() u32 {
    return memmap.RASTER_HEIGHT; // 280
}
// Physical border widths, so the host can map a mouse position into the visible
// area (physical-visible coords 0..RASTER_VIS_WIDTH / 0..RASTER_VIS_HEIGHT).
export fn hwBorderX() u32 {
    return memmap.RASTER_BORDER_X; // 80
}
export fn hwBorderY() u32 {
    return memmap.RASTER_BORDER_Y; // 40
}
export fn hwVersion() u32 {
    return memmap.ZM_HW_VERSION;
}

// --- RAM instructions (see video.zig / memmap.REG_CART_HIGH) ---
// The host declares the loaded cart's data+stack high-water once, at load time;
// the cart then asks the machine how much of its window is left instead of
// guessing (which is how a 1 MB sample buffer silently ran into the video region
// and trapped the machine on boot).
export fn hwSetCartHigh(high: u32) void {
    video.setCartHigh(high);
}
export fn hwRamBase() u32 {
    return memmap.CART_RAM_BASE;
}
export fn hwRamTop() u32 {
    return memmap.CART_RAM_TOP;
}
export fn hwRamSize() u32 {
    return memmap.CART_RAM_BYTES;
}
export fn hwRamUsed() u32 {
    return video.ramUsed();
}
export fn hwRamFree() u32 {
    return video.ramFree();
}

// --- ROM chip RAM (Phase 2) ---
// The ROM gets its own window ABOVE the video region, so an app's 2 MiB stays the
// app's. Reports 0 until a rom.wasm is actually fitted and declared.
export fn hwSetRomHigh(high: u32) void {
    video.setRomHigh(high);
}
export fn hwRomRamBase() u32 {
    return memmap.ROM_RAM_BASE;
}
export fn hwRomRamTop() u32 {
    return memmap.ROM_RAM_TOP;
}
export fn hwRomRamSize() u32 {
    return memmap.ROM_RAM_BYTES;
}
export fn hwRomRamUsed() u32 {
    return video.romRamUsed();
}
export fn hwRomRamFree() u32 {
    return video.romRamFree();
}
