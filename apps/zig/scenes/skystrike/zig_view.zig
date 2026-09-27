// --------------------------------------------------------------------------
// One displayed frame: the original's plane 0 (in ZIG, off the world, the
// same screen in plane 2's open frame: zig_screens.zig), or in
// ZIG's flight the scrolled world (plane 1), its sprites and HUD (plane 2);
// the notice over any of them (plane 3). Nothing here writes game state.
//
// A ZIG frame: the ring follows the live screen (a shift or a rebuild),
// draws what the view is missing, takes the live screen into its slot; the
// camera glides after the plane's sprite; the hardware pans; the overlay is
// drawn against the point the pan really shows; the palette (fades too) is
// the ST's colour registers on every plane.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const machine = @import("machine.zig");
const pal = @import("pal.zig");
const scr = @import("scr.zig");
const sprite = @import("sprite.zig");
const sandbox = @import("zig_sandbox.zig");
const hooks = @import("zig_hooks.zig");
const ring = @import("zig_ring.zig");
const scroll = @import("zig_scroll.zig");
const overlay = @import("zig_overlay.zig");
const hud = @import("zig_hud.zig");
const tracers = @import("zig_tracers.zig");
const help = @import("zig_help.zig");
const screens = @import("zig_screens.zig");
const scroller = @import("zig_scroller.zig");
const set = @import("zig_settings.zig");

const PLANE0 = 0;

/// Once per cart load (after machine.alloc).
pub fn init(zigos: *zg.ZigOS) void {
    sandbox.alloc();
    screens.alloc();
    scroll.init(zigos);
    // The planes' buffers were just (re)bound and cleared: nothing drawn in
    // them before is there any more.
    ring.invalidate();
    scroll.cut();
    zigos.lfbs[hud.NOTICE_PLANE].is_enabled = false;
}

pub fn render(zigos: *zg.ZigOS) void {
    colours(zigos);
    hud.tickNotice(zigos);
    if (!hooks.flightView()) return original(zigos);
    zigos.lfbs[PLANE0].is_enabled = false;
    zigos.lfbs[scroll.WORLD_PLANE].is_enabled = true;
    zigos.lfbs[scroll.OVERLAY_PLANE].is_enabled = true;
    const before = ring.rebuilds;
    ring.sync(hooks.live_sx, hooks.live_al);
    if (ring.rebuilds != before) scroll.cut();
    follow();
    const at = scroll.apply(zigos);
    ring.pump(scroll.scroll_x, scroll.scroll_y, scroll.WIN_W, scroll.WIN_H);
    copyLive();
    overlay.draw(scroll.over_px, at);
    tracers.watch();
    tracers.draw(scroll.over_px, at);
    hud.draw(scroll.over_px, tracers.ink);
    help.draw(scroll.over_px);
}

/// The live screen into its ring slot, every frame (smoke, craters, messages
/// as they happen); the bonus bar's box keeps the clean draw under it.
fn copyLive() void {
    const r = ring.rowOf(hooks.live_al) orelse return;
    const c = ring.colOf(hooks.live_sx) orelse return;
    const back = scr.get(.back);
    const lines: usize = if (r == 2) ring.LAST else @intCast(ring.LAYER);
    for (0..lines) |y| {
        const dst = ring.buf[(r * 160 + y) * ring.W + c * 320 ..][0..320];
        const src = back[y * 320 ..][0..320];
        if (y >= ring.BAR_Y0 and y <= ring.BAR_Y1) {
            @memcpy(dst[0..ring.BAR_X0], src[0..ring.BAR_X0]);
            @memcpy(dst[ring.BAR_X1 + 1 ..], src[ring.BAR_X1 + 1 ..]);
        } else @memcpy(dst, src);
    }
}

/// Not the world: the ST's screen, as it is (ORIGINAL) or in the open frame
/// (ZIG, zig_screens.zig).
fn original(zigos: *zg.ZigOS) void {
    ring.invalidate();
    tracers.clear();
    help.shown = false;
    zigos.lfbs[scroll.WORLD_PLANE].is_enabled = false;
    const full = hooks.zig and set.fullscreen_screens;
    zigos.lfbs[scroll.OVERLAY_PLANE].is_enabled = full;
    const p0 = &zigos.lfbs[PLANE0];
    p0.is_enabled = !full;
    if (full) screens.draw(scroll.over_px) else machine.present(p0);
}

/// The camera after sprite 1: the plane, or the pilot under his chute.
fn follow() void {
    const s = sprite.shown[1];
    if (!s.on or s.x < -100 or s.x > 420) return;
    scroll.follow(s.fx * ring.SEC + s.x, -s.fy * ring.LAYER + s.y);
}

fn colours(zigos: *zg.ZigOS) void {
    for (1..4) |p| {
        const fb = &zigos.lfbs[p];
        for (0..16) |i| fb.palette[i] = machine.stColor(pal.hw[i]);
        fb.palette[overlay.CLEAR] = 0;
        fb.palette[scroller.INK] = machine.stColor(scroller.ink());
    }
}
