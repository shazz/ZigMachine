// --------------------------------------------------------------------------
// RACER: a car's floor key (split from carview.zig, file size): the highest key of the kept ground faces under its
// footprint, so a road decal or a road quad nearer than the car's middle never paints over the car standing on it
// (under.zig, R82 bug pass), and the M5 rule kept as the harness' mutant. No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const cam = @import("cam.zig");
const carmodel = @import("carmodel.zig");
const frame = @import("frame.zig");
const groundmod = @import("ground.zig");
const trk = @import("trk.zig");
const under = @import("under.zig");
const Snap = @import("carview.zig").Snap;

/// The highest key of the kept ground faces under the car's footprint (under.zig, R82 bug pass): a road decal (the start
/// line, a skid puff's face) or a road quad nearer than the car's middle never paints over the car standing on it.
pub fn footKey(fr: *const frame.Frame, t: *const trk.Track, m: *const carmodel.Model, s: Snap, centre: ?u16) ?u16 {
    const f = m.foot;
    const q = under.corners(s.pos, s.angle, s.size, f.x0, f.x1, f.z0, f.z1);
    return under.key(fr, t, q, s.pos[1], centre);
}

/// The M5 rule, kept as the harness' mutant (--break under, key O): the centre's face and the face under the footprint's
/// corner nearest the eye, nothing else.
pub fn m5Key(fr: *const frame.Frame, t: *const trk.Track, m: *const carmodel.Model, v: *const cam.View, s: Snap, ground: ?u16, centre: ?u16) ?u16 {
    const f = m.foot;
    const q = under.corners(s.pos, s.angle, s.size, f.x0, f.x1, f.z0, f.z1);
    var best = q[0];
    var bd: i64 = std.math.maxInt(i64);
    for (q) |p| {
        const dx: i64 = p[0] - v.eye7[0];
        const dz: i64 = p[1] - v.eye7[2];
        if (dx * dx + dz * dz < bd) {
            bd = dx * dx + dz * dz;
            best = p;
        }
    }
    const g = groundmod.findFace(t, .{ best[0] << 9, s.pos[1], best[1] << 9 }, ground) orelse return centre;
    const k = fr.faceKey(g.face) orelse return centre;
    return @max(k, centre orelse 0);
}

