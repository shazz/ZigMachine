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
// The driving / racing cameras (far chase, near chase, cockpit): how far back and how high, in world units. Matt (24 Nov): "at
// 332 km/h it looks like the car drives at 30 km/h". The km/h is the original's own formula (250 * 3.6 * |velocity per tick|) on
// the original's world scale (a ~6-unit road, a ~770-unit lap); what was off was the view: the cameras sat 2-6x higher and
// further back than freds72's (far 1.65 back / 1.125 up, near 0.7 / 0.3, cockpit 0.03 / 0.12) over a car twice as big, so the
// ground flowed past at a third to a fifth of the speed. These are about his, with our steeper pitch (our view is 64 degrees
// tall, his 90). Ground flow at the bottom row at 332 km/h (11 units/s): far 337 -> 723 px/s, near 491 -> 1589, cockpit 779 -> 3663
// (docs/ports/kestrel_racing/M2.md, Speed feel). The benchmark flyby (lap v0) and the fixed poses keep cam.zig's, so their pins stay.
const BACK = [3]i32{ 157286, 78643, 0 }; // 2.4, 1.2, 0
const HEIGHT = [3]i32{ 78643, 29491, 10486 }; // 1.2, 0.45, 0.16
const PITCH = [3]u32{ 0x0600_0000, 0x0400_0000, 0x0100_0000 }; // 8.4, 5.6, 1.4 degrees

fn params(p: cam.Pov) [3]i32 {
    const k = @intFromEnum(p);
    return .{ BACK[k], HEIGHT[k], @bitCast(PITCH[k]) };
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
