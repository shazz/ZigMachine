// --------------------------------------------------------------------------
// RACER: the car drawn into the frame: the camera's view recomposed for the car's own space (so the
// model's Q7 vertices go through the very same transform, clip and fill as the track's) and its
// polygons pushed into the frame's list between collect and sort. Each face keeps a floor: its key
// never falls below the ground face under the car, so the road quad cannot paint over the body (the
// car is not yet sorted per face against walls: M3). No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const fix = @import("fix.zig");
const frame = @import("frame.zig");
const fx = @import("fx.zig");
const project = @import("project.zig");
const types = @import("types.zig");
const xf = @import("xform.zig");

pub const Snap = struct { pos: [3]i32, angle: i32 };

pub fn draw(fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View, s: Snap, ground: ?u16) void {
    const mv = modelView(v, s);
    const floor = if (ground) |g| fr.faceKey(g) orelse 0 else 0;
    cache.next();
    for (&carmodel.faces) |*f| {
        if (types.facing(f, &mv) <= f.cp) continue;
        _ = project.build(fr, cache, &carmodel.verts, &mv, f, .{ .floor = floor });
    }
}

/// The camera's view recomposed for the car's own space: rows right-multiplied by the car's yaw,
/// the translation carrying the car's position, the eye in the car's Q7 space (the back-face test).
pub fn modelView(v: *const cam.View, s: Snap) cam.View {
    const c = fix.cos(s.angle);
    const d = -fix.sin(s.angle);
    var m = v.*;
    for (0..3) |i| {
        const r = v.r[i];
        m.r[i] = .{ fx.mulsh16(r[0], c) + fx.mulsh16(r[2], -d), r[1], fx.mulsh16(r[0], d) + fx.mulsh16(r[2], c) };
        m.t[i] = v.t[i] + ((fx.mulsh16(r[0], s.pos[0]) + fx.mulsh16(r[1], s.pos[1]) + fx.mulsh16(r[2], s.pos[2])) >> 9);
    }
    const dx = v.eye7[0] - (s.pos[0] >> 9);
    const dz = v.eye7[2] - (s.pos[2] >> 9);
    m.eye7 = .{ fx.mulsh16(c, dx) + fx.mulsh16(-d, dz), v.eye7[1] - (s.pos[1] >> 9), fx.mulsh16(d, dx) + fx.mulsh16(c, dz) };
    if (fx.use_f32) cam.floatView(&m);
    return m;
}
