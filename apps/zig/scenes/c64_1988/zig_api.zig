// --------------------------------------------------------------------------
// The headless harness's door into 1988's ZIG mode (apps/c64_1988_zig.mjs). Imported only when
// this scene IS the cart (c64_1988.zig checks cart.Cart), so the exports never leak into
// another cart's build.
// --------------------------------------------------------------------------
const zig = @import("zig_mode.zig");

/// 1 while ZIG mode draws the plane (from Z until the next C64 frame boundary after Z again).
export fn c64Zig() u32 {
    const z = zig.current orelse return 0;
    return @intFromBool(z.on);
}

/// Sixths of a C64 frame the last ZIG picture was past the frame before (0: a C64 frame exactly).
export fn c64ZigK() u32 {
    const z = zig.current orelse return 0;
    return z.k;
}

/// CHISEL ops the last ZIG picture took.
export fn c64ZigOps() u32 {
    const z = zig.current orelse return 0;
    return z.ops;
}
