// --------------------------------------------------------------------------
// RACER: one frame drawn (the Demo's render, moved here at the M5 finish): the page flipped, a menu
// screen (no 3D under it) or the 3D view of the pose in force (a fixed pose, the race's or the drive's
// chase camera, or the flyby's lap script), then the HUD, the benchmark lines and the title over it.
// Works on any Demo (racer.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const fx = @import("fx.zig");
const frontdraw = @import("frontdraw.zig");
const front = @import("front.zig");
const haze = @import("haze.zig");
const present = @import("present.zig");

/// The camera this frame: a fixed pose (A-H), the race's or the drive's chase camera, or the flyby.
pub fn pose(d: anytype) cam.Pose {
    const t = d.cur();
    if (d.pose) |k| return cam.fixedPose(t, k);
    if (d.game.mode != .off) return d.game.pose();
    if (d.drive.mode != .off) return d.drive.pose();
    return cam.lapPose(t, d.script, cam.povAt(d.script));
}

pub fn render(d: anytype, zigos: *zg.ZigOS) void {
    d.bench.frameStart();
    const fb = present.flip(d, zigos);
    if (front.menu(d)) return frontdraw.menuFrame(d, zigos, fb); // the select, the options, the results: no 3D under them
    const t = d.cur();
    const p = pose(d);
    clip.near = if (d.pose != null) clip.NEAR else if (d.game.mode != .off) d.game.near() else d.drive.near();
    var v = cam.view(p);
    if (fx.use_f32) cam.floatView(&v);
    d.p.sky(fb, &v, p.yaw);
    d.bench.lap(.sky);
    haze.setR(d.r); // M6: the haze's bands follow the draw distance (rebuilt only when it changed)
    d.f.visibility(t, &v, d.r);
    d.bench.lap(.vis);
    d.f.collect(t, &v, d.decals);
    present.addCars(d, &v);
    d.bench.lap(.collect);
    d.f.sort();
    d.bench.lap(.sort);
    const counts = d.p.fill(fb, &d.f);
    d.bench.lap(.fill);
    present.finish(d, zigos, fb, counts);
    frontdraw.overlay(d, zigos, fb); // the title over the flyby (after the view's CRC)
}
