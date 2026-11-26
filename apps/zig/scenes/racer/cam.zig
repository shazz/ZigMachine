// --------------------------------------------------------------------------
// RACER: the camera. A pose (Q16 position, u32 yaw and pitch: a turn = 2^32, yaw 0 looks +z and
// grows toward +x, pitch down is positive) becomes a view: the rows right / up / forward of the
// world -> view rotation in Q25 (so mulsh16 against a Q7 vertex gives Q16), the translation in
// Q16, the eye in Q7 (the back-face test) and the PVS' yaw bucket and tile.
// The lap v0 script flies the racing line, indexed by FRAME COUNT (never the clock), through the
// three POVs of the original (far chase, near chase, cockpit), each its own back / height / pitch.
// No ZigOS import.
// --------------------------------------------------------------------------
const fx = @import("fx.zig");
const trk = @import("trk.zig");
const zone = @import("zone.zig");

pub const Pose = struct { pos: [3]i32, yaw: u32, pitch: u32 };
pub const Pov = enum(u2) { far, near, cockpit };
pub const LAP_FRAMES: u32 = 720;
pub const POSES = 8;

pub const BACK = [3]i32{ 6 << 16, 3 << 16, 0 };
pub const HEIGHT = [3]i32{ (5 << 16) / 2, (3 << 16) / 2, (3 << 16) / 4 };
pub const PITCH = [3]u32{ 0x0600_0000, 0x0400_0000, 0x0100_0000 }; // 8.4, 5.6, 1.4 degrees

pub const View = struct {
    r: [3][3]i32, // Q25 rows: right, up, forward
    t: [3]i32, // Q16, -R * pos
    eye7: [3]i32, // Q7
    bucket: u32,
    tile: u32,
    horizon: i32, // the screen row of the horizon (level camera, no roll)
    rf: [3][3]f32 = undefined, // floatView(): the f32 twin of r (Q16 view units per 1/128 unit) and t, for the A/B
    tf: [3]f32 = undefined,
};

pub fn view(p: Pose) View {
    const sy = fx.sin(p.yaw);
    const cy = fx.cos(p.yaw);
    const sp = fx.sin(p.pitch);
    const cp = fx.cos(p.pitch);
    const r16 = [3][3]i32{
        .{ cy, 0, -sy },
        .{ fx.mulsh16(sy, sp), cp, fx.mulsh16(cy, sp) },
        .{ fx.mulsh16(sy, cp), -sp, fx.mulsh16(cy, cp) },
    };
    var v: View = undefined;
    for (r16, 0..) |row, i| {
        for (row, 0..) |c, j| v.r[i][j] = c << 9;
        v.t[i] = -(fx.mulsh16(row[0], p.pos[0]) + fx.mulsh16(row[1], p.pos[1]) + fx.mulsh16(row[2], p.pos[2]));
    }
    for (p.pos, 0..) |c, i| v.eye7[i] = c >> 9;
    v.bucket = (p.yaw +% (1 << 27)) >> 28;
    const tx: u32 = @intCast(std.math.clamp((p.pos[0] >> 19) + 16, 0, 31));
    const tz: u32 = @intCast(std.math.clamp((p.pos[2] >> 19) + 16, 0, 31));
    v.tile = tz * trk.GRID + tx;
    const tan = fx.mulsh16(sp, @intCast(fx.rcp(@intCast(cp)))); // Q16 tan(pitch): the horizon sits F * tan above the centre
    v.horizon = std.math.clamp(100 - ((tan * 160) >> 16), 0, 200);
    return v;
}

/// Fill the f32 matrices (once a frame, only when the f32 transform is on).
pub fn floatView(v: *View) void {
    for (v.r, 0..) |row, i| {
        for (row, 0..) |c, j| v.rf[i][j] = @as(f32, @floatFromInt(c)) / 65536.0;
        v.tf[i] = @floatFromInt(v.t[i]);
    }
}

/// The lap v0 camera at script frame `frame` (wraps), through POV `pov`.
pub fn lapPose(t: *const trk.Track, frame: u32, pov: Pov) Pose {
    const f = frame % LAP_FRAMES;
    const n: u64 = t.line.len;
    const s: u64 = (@as(u64, f) * n << 16) / LAP_FRAMES; // segment index, Q16
    const i: usize = @intCast(s >> 16);
    const fr: i32 = @intCast(s & 0xFFFF);
    const a = t.line[i];
    const b = t.line[(i + 1) % t.line.len];
    const dy: i16 = @bitCast(b.yaw -% a.yaw);
    const yaw16: u16 = a.yaw +% @as(u16, @bitCast(@as(i16, @intCast((@as(i64, dy) * fr) >> 16))));
    const yaw: u32 = @as(u32, yaw16) << 16;
    var pos: [3]i32 = undefined;
    for (&pos, a.pos, b.pos) |*o, pa, pb| o.* = pa + fx.mulsh16(pb - pa, fr);
    const k = @intFromEnum(pov);
    var o = [3]i32{ BACK[k], HEIGHT[k], @bitCast(PITCH[k]) };
    if (pov == .far) o = zone.blend(o, .{ BACK[1], HEIGHT[1], @bitCast(PITCH[1]) }, zone.weight(t, s)); // under a roof: the near camera (zone.zig)
    pos[0] -= fx.mulsh16(o[0], fx.sin(yaw));
    pos[2] -= fx.mulsh16(o[0], fx.cos(yaw));
    pos[1] += o[1];
    return .{ .pos = pos, .yaw = yaw, .pitch = @bitCast(o[2]) };
}

pub fn povAt(frame: u32) Pov {
    return @enumFromInt(@min((frame % LAP_FRAMES) / (LAP_FRAMES / 3), 2));
}

/// The harness' eight fixed poses: eighths of the lap, the POV cycling.
pub fn fixedPose(t: *const trk.Track, k: u32) Pose {
    return lapPose(t, k * (LAP_FRAMES / POSES), @enumFromInt(k % 3));
}

const std = @import("std");
