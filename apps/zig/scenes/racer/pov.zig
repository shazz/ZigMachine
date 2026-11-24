// --------------------------------------------------------------------------
// RACER: the chase / cockpit camera behind a car, shared by driving (drive.zig, M2) and the race
// (game.zig, M3): the three POVs lerp over 30 ticks (60 frames); the cockpit sits in the car with
// the near plane at 0.05. Pure functions of the POV state, so each owner keeps its own counters.
// No ZigOS import.
// --------------------------------------------------------------------------
const cam = @import("cam.zig");
const clip = @import("clip.zig");
const fx = @import("fx.zig");

pub const FRAMES = 60;

/// back (Q16), height (Q16), pitch (turns u32 as i32) of a POV.
fn params(p: cam.Pov) [3]i32 {
    const k = @intFromEnum(p);
    return .{ cam.BACK[k], cam.HEIGHT[k], @bitCast(cam.PITCH[k]) };
}

pub fn next(p: cam.Pov) cam.Pov {
    return @enumFromInt((@intFromEnum(p) + 1) % 3);
}

/// The lerped back, height and pitch `frames` frames into the move from POV `from` to `pov`.
pub fn offsets(pov: cam.Pov, from: cam.Pov, frames: u32) [3]i32 {
    const to = params(pov);
    const fr = params(from);
    const k: i32 = @intCast(frames * 65536 / FRAMES);
    var o: [3]i32 = undefined;
    for (&o, fr, to) |*r, a, b| r.* = a + fx.mulsh16(b - a, k);
    return o;
}

/// The camera behind the car at `pos`, heading `angle` (turns, Q16).
pub fn pose(pos: [3]i32, angle: i32, o: [3]i32) cam.Pose {
    const yaw: u32 = @as(u32, @as(u16, @truncate(@as(u32, @bitCast(angle))))) << 16;
    var p = pos;
    p[0] -= fx.mulsh16(o[0], fx.sin(yaw));
    p[2] -= fx.mulsh16(o[0], fx.cos(yaw));
    p[1] += o[1];
    return .{ .pos = p, .yaw = yaw, .pitch = @bitCast(o[2]) };
}

/// The near plane this frame's POV wants (the cockpit is inside the car).
pub fn near(pov: cam.Pov, frames: u32) i32 {
    return if (pov == .cockpit and frames == FRAMES) clip.NEAR_COCKPIT else clip.NEAR;
}
