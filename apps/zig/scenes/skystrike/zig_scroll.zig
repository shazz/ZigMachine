// --------------------------------------------------------------------------
// ZIG mode's two planes and its camera.
//
//   plane 1  the world: an overscan SCROLL plane over the ring's 960 x 540
//            buffer (zig_ring.zig), panned by the hardware (setScroll = the
//            plane's base register), borders opened by flickerBorder() from
//            its HBL at OVERSCAN_MAGIC_X on every line: 400 x 280 on screen
//   plane 2  the sprites and the HUD: a 400 x 280 overscan plane, borders
//            opened the same way, index 255 transparent (zig_overlay.zig,
//            zig_hud.zig)
//
// Both come out of the VRAM pool ONCE, at the cart's init: vramAlloc() has no
// guard (it runs on into the physical framebuffer), so the total is checked
// here at comptime against the pool. Plane 0 stays the original 320 x 200.
//
// The camera is the window's top-left in the world (x wraps at 51 sectors;
// layer al's line y is -al * 160 + y). It follows the plane's sprite by a
// fraction of the way a frame, capped (zig_settings.zig's glide_*), so the
// world glides between the game's passes; a jump too far to glide (a new plane, the
// autoland) is a cut. Its y stops where the ground's last line meets the HUD.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ring = @import("zig_ring.zig");
const set = @import("zig_settings.zig");

pub const WIN_W: i32 = zg.PHYSICAL_WIDTH;
pub const WIN_H: i32 = zg.PHYSICAL_HEIGHT;
/// The HUD panel's height: the game's lines 176-199.
pub const PANEL_H: i32 = 24;
/// The world's part of the window; the HUD band (the panel, then the
/// margin a monitor's frame covers) is under it.
pub const VIEW_H: i32 = WIN_H - PANEL_H - @as(i32, @intCast(set.hud_bottom_margin));
/// Where the plane sits in the window.
pub const PLANE_X: i32 = set.plane_x;
pub const PLANE_Y: i32 = set.plane_y;
pub const MAXSTEP: i32 = set.glide_cap;
const SNAP: i32 = set.glide_snap;
/// The ground layer's line 175 on the window's line VIEW_H - 1.
const LOWEST: i32 = 175 - (VIEW_H - 1);

pub const WORLD_PLANE = 1;
pub const OVERLAY_PLANE = 2;

comptime {
    const used = 4 * zg.NORMAL_FB_BYTES + ring.W * ring.H + zg.OVERSCAN_FB_BYTES;
    if (used > zg.VRAM_BYTES) @compileError("ZIG mode's planes overrun the VRAM pool");
}

pub var cam_x: i32 = 0;
pub var cam_y: i32 = 0;
var placed: bool = false;
/// The pan the hardware was given last (ring coords), for the harness.
pub var scroll_x: i32 = 0;
pub var scroll_y: i32 = 0;
/// The overlay plane's 400 x 280 indices.
pub var over_px: []u8 = &.{};

/// Once per cart load: both planes' buffers and their border HBLs.
pub fn init(zigos: *zg.ZigOS) void {
    const world = &zigos.lfbs[WORLD_PLANE];
    world.setOverscanScrollPlane(@intCast(ring.W), @intCast(ring.H));
    world.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, zg.flickerAllHbl);
    world.is_enabled = false;
    ring.buf = world.fb[0 .. ring.W * ring.H];
    const over = &zigos.lfbs[OVERLAY_PLANE];
    over.openBorders(.all);
    over.is_enabled = false;
    over_px = over.fb[0..@intCast(WIN_W * WIN_H)];
}

/// The next time the camera moves it jumps straight to the plane.
pub fn cut() void {
    placed = false;
}

fn glide(d: i32) i32 {
    const m = if (d > 2 or d < -2) @divTrunc(d, set.glide_div) else d;
    return @max(-MAXSTEP, @min(MAXSTEP, m));
}

/// Towards the plane's hot spot at world (px, py).
pub fn follow(px: i32, py: i32) void {
    const tx = @mod(px - PLANE_X, ring.WORLD_W);
    const ty = @min(LOWEST, py - PLANE_Y);
    const dx = ring.wrapDelta(tx - cam_x);
    const dy = ty - cam_y;
    if (!placed or @abs(dx) > SNAP or @abs(dy) > SNAP) {
        cam_x = tx;
        cam_y = ty;
        placed = true;
        return;
    }
    cam_x = @mod(cam_x + glide(dx), ring.WORLD_W);
    cam_y += glide(dy);
}

/// The pan, kept inside the ring; returns the world point the window's
/// top-left really shows (the overlay draws against it).
pub fn apply(zigos: *zg.ZigOS) [2]i32 {
    const max_x: i32 = @as(i32, @intCast(ring.W)) - WIN_W;
    const max_y: i32 = @as(i32, @intCast(ring.H)) - WIN_H;
    scroll_x = @max(0, @min(max_x, ring.wrapDelta(cam_x - ring.leftWX())));
    scroll_y = @max(0, @min(max_y, cam_y - ring.topWY()));
    zigos.lfbs[WORLD_PLANE].setScroll(@intCast(scroll_x), @intCast(scroll_y));
    return .{ @mod(ring.leftWX() + scroll_x, ring.WORLD_W), ring.topWY() + scroll_y };
}
