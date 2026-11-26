// --------------------------------------------------------------------------
// RACER: a track's race clock (M5 step 4). freds72's rule is 75 s at the start and 10 s at each
// checkpoint, tuned for a short lap with four checkpoints; on a long or twisty lap (every 32X course)
// the pilot runs out of time. Now each track has its own:
//   - the mood block's clock bytes (tools/racer/mood.py: byte 24 the start, 25 the extension, in
//     seconds) when the converter wrote them (the Track Kit's `ktrk_clock`);
//   - else (0, every file converted before this step) computed at load from the racing line: a lap's
//     estimated time P = (length + 0.15 x total turning in degrees) / 10.5 seconds (fitted to the AI
//     pilot's lap on 11 tracks: never under it, M5.md step 4), then
//       start = max(75, ceil(1.5 x P)),  extension = max(10, ceil(0.8 x P / checkpoints)),
//     freds72's own ratios (75 s and 4 x 10 s against the oval's 47 s pilot lap: 1.6 and 0.85). The
//     floors are his numbers, so the oval (P = 47.9 s) keeps exactly 75 s + 10 s.
// Integer only (a load-time loop over the line, never per frame). No ZigOS import.
// --------------------------------------------------------------------------
const std = @import("std");
const trk = @import("trk.zig");

pub const HZ = 30;
pub const BASE_START = 75; // freds72's, seconds
pub const BASE_EXTEND = 10;
pub const MAX_START = 250; // the mood byte's bound (trk.parse refuses more)
pub const MAX_EXTEND = 60;
// P = (length + TURN_X100 / 100 x degrees) / (PACE_X10 / 10): fitted to the AI pilot's lap times (M5.md step 4)
pub const PACE_X10 = 105; // 10.5 units a second
pub const TURN_X100 = 15; // a degree of turning costs 0.15 units of length
pub const START_LAPS_X10 = 15; // the start covers 1.5 estimated laps
pub const EXT_LAPS_X10 = 8; // the extensions of one lap add 0.8 of one

pub var break_flat = false; // racer_front.mjs --break clock (key U): the computed clock is freds72's

pub const Clock = struct {
    start: u32, // ticks
    extend: u32, // ticks a checkpoint
    computed: bool, // from the line (no clock in the file)
};

/// The racing line's length in units (Q16 positions; integer square roots of Q8 differences).
pub fn lapLength(t: *const trk.Track) u32 {
    var sum: u64 = 0;
    for (t.line, 0..) |s, i| {
        const n = t.line[(i + 1) % t.line.len].pos;
        var sq: u64 = 0;
        for (0..3) |k| {
            const d: i64 = (@as(i64, n[k]) - s.pos[k]) >> 8; // Q8: a 2^23-unit difference squares within u64
            sq += @intCast(d * d);
        }
        sum += std.math.sqrt(sq);
    }
    return @intCast(sum >> 8);
}

/// The racing line's total turning in degrees (each segment's yaw step, wrapped to +-180).
pub fn turning(t: *const trk.Track) u32 {
    var sum: u64 = 0;
    for (t.line, 0..) |s, i| {
        const d: i16 = @bitCast(t.line[(i + 1) % t.line.len].yaw -% s.yaw);
        sum += @abs(d);
    }
    return @intCast(sum * 360 >> 16);
}

/// The estimated lap time, tenths of a second.
pub fn lapTenths(t: *const trk.Track) u32 {
    return (lapLength(t) * 100 + TURN_X100 * turning(t)) / PACE_X10;
}

/// What the clock is computed from: the estimated lap, the checkpoints, the file's clock bytes (the track select keeps
/// these for a track it has not loaded: preview.zig).
pub const Parts = struct { tenths: u32 = 0, checkpoints: u32 = 1, file: [2]u8 = .{ 0, 0 } };

pub fn parts(t: *const trk.Track) Parts {
    return .{ .tenths = lapTenths(t), .checkpoints = @intCast(@max(t.checkpoints.len, 1)), .file = t.mood.clock };
}

pub fn of(t: *const trk.Track) Clock {
    return fromParts(parts(t));
}

pub fn fromParts(q: Parts) Clock {
    const p = if (break_flat) 0 else q.tenths;
    const start_s: u32 = if (q.file[0] != 0) q.file[0] else @max(BASE_START, ceilDiv(p * START_LAPS_X10, 100));
    const ext_s: u32 = if (q.file[1] != 0) q.file[1] else @max(BASE_EXTEND, ceilDiv(p * EXT_LAPS_X10, 100 * q.checkpoints));
    return .{
        .start = @as(u32, @min(start_s, MAX_START)) * HZ, // (@min with a constant narrows to u8)
        .extend = @as(u32, @min(ext_s, MAX_EXTEND)) * HZ,
        .computed = q.file[0] == 0 or q.file[1] == 0,
    };
}

fn ceilDiv(a: u32, b: u32) u32 {
    return (a + b - 1) / b;
}
