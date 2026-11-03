// --------------------------------------------------------------------------
// The headless harness's door into the demo (apps/grodan_kvack_headless.mjs).
// It reads back the words compose() draws from -- the tick count, the four
// scroll positions and the Go's own animation counters -- so a pixel check that
// ever drifts can say WHERE (which layer) it drifted, not just that it did.
// Imported only when this scene IS the cart (grodan_kvack.zig checks cart.Cart),
// so the exports never leak into another cart's build (kickoff2's pattern).
// --------------------------------------------------------------------------
const scene = @import("../grodan_kvack.zig");

/// The 60 Hz tick count (one step of the Go's Update()).
export fn gkTick() u32 {
    return scene.tick;
}

/// Scroll position by layer: 0 = mainText, 1 = vertText, 2 = smallText1,
/// 3 = smallText2 (the Go's ScreenWidth font-px units).
export fn gkScroll(layer: u32) i32 {
    const s = &scene.state;
    return switch (layer) {
        0 => s.s1.scroll,
        1 => s.s2.scroll,
        2 => s.s3.scroll,
        else => s.s4.scroll,
    };
}

/// CHISEL blits the last frame issued (draw.zig); 0 means the CPU composer ran
/// (cart RAM could not hold the chunky art).
export fn gkBlits() u32 {
    return @import("draw.zig").blits_last_frame;
}

/// The state words by selector, for the harness's sanity assertions:
/// 0 moveY, 1 moveX, 2 X, 3 Y, 4 bgcount, 5 ychange (tenths), 6 swing, 7 swingy.
export fn gkState(sel: u32) i32 {
    const s = &scene.state;
    return switch (sel) {
        0 => s.moveY,
        1 => s.moveX,
        2 => s.X,
        3 => s.Y,
        4 => s.bgcount,
        5 => s.ychange10,
        6 => @bitCast(s.swing),
        else => @bitCast(s.swingy),
    };
}

// ---- ZIG mode (zig_mode.zig) ---------------------------------------------------
const zig = @import("zig_mode.zig");

/// 1 while ZIG mode is on.
export fn gkZig() u32 {
    return @intFromBool(zig.on);
}

/// The green plane: 0 = its pan column (HSCROLL), 1 = row (FB_BASE), 2 = times drawn.
export fn gkZigGreen(sel: u32) u32 {
    const g = @import("zig_green.zig");
    return switch (sel) {
        0 => g.pan_x,
        1 => g.pan_y,
        else => g.draws,
    };
}

/// Plane p's pixel buffer and stride (0 before the first Z press).
export fn gkPlanePtr(p: u32) u32 {
    const os = zig.os orelse return 0;
    return @intCast(@intFromPtr(os.lfbs[p & 3].fb));
}
export fn gkPlaneStride(p: u32) u32 {
    const os = zig.os orelse return 0;
    return os.lfbs[p & 3].stride;
}

/// Plane p's published copper list (HW 1.9.0): address and length in words, 0 = none.
export fn gkCopperPtr(p: u32) u32 {
    const os = zig.os orelse return 0;
    const l = os.lfbs[p & 3].copperBuffer() orelse return 0;
    return @intCast(@intFromPtr(l.ptr));
}
export fn gkCopperLen(p: u32) u32 {
    const os = zig.os orelse return 0;
    const l = os.lfbs[p & 3].copperBuffer() orelse return 0;
    return @intCast(l.len);
}

/// CHISEL ops the last ZIG frame issued: the AFFINE plus the keyed blits.
export fn gkZigBlits() u32 {
    return 1 + @import("zig_layers.zig").blits_last_frame;
}

/// The rotozoom for tick t: 0 = its angle (u32), 1 = texels a pixel (Q16).
export fn gkZigRoto(sel: u32, t: u32) u32 {
    const r = @import("zig_roto.zig");
    return if (sel == 0) r.angleAt(t) else @bitCast(r.scaleAt(t));
}
