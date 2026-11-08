// --------------------------------------------------------------------------
// The headless harness's door into NATRIUM's ZIG mode (apps/rno_natrium_zig.mjs).
// Imported only when this scene IS the cart (rno_natrium.zig checks cart.Cart),
// so the exports never leak into another cart's build.
// --------------------------------------------------------------------------
const zig = @import("zig_mode.zig");
const R = @import("zig_res.zig");
const tunnel = @import("zig_tunnel.zig");
const env = @import("zig_env.zig");
const dots = @import("zig_dots.zig");
const twist = @import("zig_twist.zig");

/// 1 while ZIG mode is on.
export fn natZig() u32 {
    return @intFromBool(zig.on);
}

/// What plane 1 showed last frame: 0 classic, 1 tunnel, 2 wobble, 3 env, 4 roto,
/// 5 dots, 6 twister.
export fn natZigPart() u32 {
    return @intFromEnum(zig.part);
}

/// The time the last ZIG frame drew, Q10 VBLs of the part.
export fn natZigTime() u32 {
    return zig.time;
}

/// CHISEL ops the last ZIG frame issued.
export fn natZigOps() u32 {
    return R.ops;
}

/// Plane p's pixel buffer and stride (the cart sets the handle at init).
export fn natPlanePtr(p: u32) u32 {
    const os = zig.os orelse return 0;
    return @intCast(@intFromPtr(os.lfbs[p & 3].fb));
}
export fn natPlaneStride(p: u32) u32 {
    const os = zig.os orelse return 0;
    return os.lfbs[p & 3].stride;
}

/// Cart-RAM buffers: 0 the tunnel map (u16, 600 x 360), 1 skin, 2 face, 3 env
/// (128 x 128, levels at 16..), 4 bg (400 x 280), 5 the dot map (u16, 400 x 280),
/// 6 the dot texture (32 x 128), 7 the chrome strip (512 x 64 pens).
export fn natZigBuf(sel: u32) u32 {
    const p: usize = switch (sel) {
        0 => @intFromPtr(tunnel.map.ptr),
        1 => @intFromPtr(R.skin.ptr),
        2 => @intFromPtr(R.face.ptr),
        3 => @intFromPtr(R.env.ptr),
        5 => @intFromPtr(dots.map.ptr),
        6 => @intFromPtr(dots.tex.ptr),
        7 => @intFromPtr(twist.strip.ptr),
        else => @intFromPtr(R.bg.ptr),
    };
    return @intCast(p);
}

/// The env object's last box (0..3: x0, y0, x1, y1), 4: its span count.
export fn natZigEnv(sel: u32) i32 {
    return if (sel < 4) env.box[sel] else @intCast(env.nspans);
}

/// The twister's bar: its top line last frame (-1: none yet).
export fn natZigTwistTop() i32 {
    return twist.top;
}
