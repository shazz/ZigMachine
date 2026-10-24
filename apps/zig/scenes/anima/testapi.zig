// --------------------------------------------------------------------------
// The headless harness's door into ANIMA (apps/anima_headless.mjs). Pulled in
// only when this scene IS the cart, so the exports never leak elsewhere.
// --------------------------------------------------------------------------
const app = @import("app.zig");
const raster = @import("raster.zig");

export fn animaOk() u32 {
    return @intFromBool(app.ok);
}

export fn animaTick() u32 {
    return app.tick;
}

export fn animaPhase() u32 {
    return @intFromEnum(app.phase());
}

/// Jump the timeline to tick t (frame_cost --call F:animaJump:t).
export fn animaJump(t: u32) void {
    app.jump(t);
}

/// 1 when physical line r flickers the border open this frame.
export fn animaLineOpen(r: u32) u32 {
    return @intFromBool(raster.isOpen(r));
}

/// Plane 0's 400x280 buffer (palette indices), for the harness's pixel checks.
export fn animaFb() u32 {
    return @intCast(@intFromPtr(app.planePtr()));
}

/// CHISEL ops the last frame issued by the logo and the scroller, and the
/// glenz's triangles (the harness counts every hwBlit itself as well).
export fn animaLogoBlits() u32 {
    return @import("logo.zig").blits;
}

/// The colour the HBL writes into slot s on physical line r.
export fn animaLineColour(r: u32, s: u32) u32 {
    return if (r < raster.ROWS and s < raster.MAX) raster.lines[r][s] else 0;
}

/// The raster's colour for physical line r (entry 0's per-line table).
export fn animaRasterAt(r: u32) u32 {
    return if (r < raster.ROWS) raster.lines[r][0] else 0;
}
