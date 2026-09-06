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
