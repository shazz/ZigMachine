// --------------------------------------------------------------------------
// RACER: camera zones (M5 finish). A track marks the racing-line segments that run under a roof (Neon
// Docks' warehouse, Glacier Pass' rock tunnel): bit ROOF of a line entry's `segment` word (0 on every
// file converted before: no zone). The Track Kit sets it from the CAM_NEAR vertex group on the L
// vertices (tools/racer/kit_export.py). There the far chase camera (the flyby's 6 back / 2.5 up, the
// race's 2.4 / 1.2) blends to the near one, so it never rides up into the ceiling; the near and the
// cockpit cameras are under it already. The blend is a pure function of the line position, so a frame
// of the flyby is still a function of its frame number (the fixed poses, ref_render.py --frame):
//   at segment i, d = the distance in segments to the nearest roof segment j: j - i ahead of it, or
//   i - j - BEHIND past it (the camera is behind the car: it leaves the roof up to BEHIND segments
//   later); the weight is (RAMP + 1 - d) / (RAMP + 1) of the way to the near camera, clamped to 0..1,
//   and between two segments it is interpolated by the fraction. tools/racer/ref_zone.py is its twin.
// Integer only. No ZigOS import.
// --------------------------------------------------------------------------
const trk = @import("trk.zig");

pub const ROOF: u16 = trk.LINE_ROOF;

pub const RAMP = 2; // segments of blend each side (~8.5 units on our tracks)
pub const BEHIND = 2; // segments the zone holds past its last roof segment (the far camera is <= 6 units back)
const ONE: u32 = 1 << 16;
pub var break_zone = false; // racer_zone.mjs --break zone (key K): no zone anywhere (the far camera stays far)

/// The weight (Q16: 0 the far camera, 65536 the near one) at line position `s` (Q16 segments, wrapping).
pub fn weight(t: *const trk.Track, s: u64) u32 {
    if (break_zone) return 0;
    const n = t.line.len;
    const i: usize = @intCast((s >> 16) % n);
    const fr: u32 = @intCast(s & 0xFFFF);
    const a = at(t, i);
    const b = at(t, (i + 1) % n);
    return @intCast(@as(i64, a) + ((@as(i64, b) - a) * fr >> 16));
}

/// The weight at line segment i.
pub fn at(t: *const trk.Track, i: usize) u32 {
    const n: i64 = @intCast(t.line.len);
    var best: i64 = RAMP + 1; // the distance to the nearest roof (RAMP + 1: none in reach)
    var k: i64 = -(BEHIND + RAMP);
    while (k <= RAMP) : (k += 1) {
        const j: usize = @intCast(@mod(@as(i64, @intCast(i)) + k, n));
        if (t.line[j].segment & ROOF == 0) continue;
        const d = if (k >= 0) k else @max(0, -k - BEHIND);
        best = @min(best, d);
    }
    return @intCast(@divTrunc((RAMP + 1 - best) * ONE, RAMP + 1));
}

/// The line position of a car: its unwrapped track u (Q16) on the line.
pub fn ofU(t: *const trk.Track, u: i32) u64 {
    const n: i64 = @intCast(t.line.len);
    return @intCast(@mod(@as(i64, u), n << 16));
}

/// A far camera's (back, height, pitch) blended `w` (Q16) of the way to the near one's.
pub fn blend(far: [3]i32, near: [3]i32, w: u32) [3]i32 {
    var o: [3]i32 = undefined;
    for (&o, far, near) |*r, a, b| r.* = a + @as(i32, @truncate((@as(i64, b) - a) * w >> 16));
    return o;
}
