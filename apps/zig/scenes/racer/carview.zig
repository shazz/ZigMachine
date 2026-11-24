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

/// Draw one car; `shift` recolours the body (carmodel.liveryShift: 0 keeps the player's red).
pub fn draw(fr: *frame.Frame, cache: *xf.Cache, v: *const cam.View, s: Snap, ground: ?u16, shift: u8) void {
    const mv = modelView(v, s);
    const floor = if (ground) |g| fr.faceKey(g) orelse 0 else 0;
    cache.next();
    for (&carmodel.faces) |*f| {
        if (types.facing(f, &mv) <= f.cp) continue;
        const dc: u8 = if (f.colour >= BODY0 and f.colour < BODY0 + 8) shift else 0;
        _ = project.build(fr, cache, &carmodel.verts, &mv, f, .{ .floor = floor, .dc = dc });
    }
}

const BODY0: u8 = 16 + carmodel.RAMP_BODY * 8;

/// True when the car at `pos` is within `tiles` tiles (8 units each) of the eye: farther cars are not worth transforming.
pub fn inRange(v: *const cam.View, pos: [3]i32, tiles: u32) bool {
    const dx: i64 = v.eye7[0] - (pos[0] >> 9);
    const dz: i64 = v.eye7[2] - (pos[2] >> 9);
    const r: i64 = @as(i64, tiles) * 8 * 128;
    return dx * dx + dz * dz <= r * r;
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
        m.t[i] = v.t[i] + @as(i32, @truncate((dot25(r[0], s.pos[0]) + dot25(r[1], s.pos[1]) + dot25(r[2], s.pos[2])) >> 9));
    }
    const dx = v.eye7[0] - (s.pos[0] >> 9);
    const dz = v.eye7[2] - (s.pos[2] >> 9);
    m.eye7 = .{ fx.mulsh16(c, dx) + fx.mulsh16(-d, dz), v.eye7[1] - (s.pos[1] >> 9), fx.mulsh16(d, dx) + fx.mulsh16(c, dz) };
    if (fx.use_f32) cam.floatView(&m);
    return m;
}

/// (a * b) >> 16 kept in 64 bits: a Q25 row times a Q16 position passes 2^31 once the car is 64 units out (the oval is 90 long).
fn dot25(a: i32, b: i32) i64 {
    return (@as(i64, a) * b) >> 16;
}
