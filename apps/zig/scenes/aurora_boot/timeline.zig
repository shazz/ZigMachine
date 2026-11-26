// --------------------------------------------------------------------------
// AURORA BOOT: the frame plan. The cart counts 60 Hz frames (dt is ignored). The baker's records are
// 30 fps: record r covers frames 2r (exact) and 2r + 1 (the midpoint toward record r + 1). The aurora's
// frame j is on screen from record AURORA_AT + j; it changes over its two frames (the baker's first container on the
// even one, the second on the odd one) so a 60 Hz frame never does a whole frame's work.
// No ZigOS import: it tests natively.
// --------------------------------------------------------------------------
const std = @import("std");

pub const Step = struct {
    rec: u32, // the record this frame sits on or after
    odd: bool, // true: halfway to record rec + 1
};

pub fn step(f: u32) Step {
    return .{ .rec = f / 2, .odd = f & 1 == 1 };
}

/// The aurora frame shown from record `rec`, or null outside the aurora's window.
pub fn auroraFrame(rec: u32, at: u32, n: u32) ?u32 {
    if (rec < at or rec - at >= n) return null;
    return rec - at;
}

/// The last frame: the baked fade reaches black on the last record.
pub fn lastFrame(records: u32) u32 {
    return (records - 1) * 2;
}

test "a 60 Hz frame is exact on even frames and halfway on odd ones" {
    try std.testing.expectEqual(Step{ .rec = 0, .odd = false }, step(0));
    try std.testing.expectEqual(Step{ .rec = 3, .odd = true }, step(7));
}

test "the aurora window opens at AURORA_AT and ends after n frames" {
    try std.testing.expectEqual(@as(?u32, null), auroraFrame(29, 30, 151));
    try std.testing.expectEqual(@as(?u32, 0), auroraFrame(30, 30, 151));
    try std.testing.expectEqual(@as(?u32, 150), auroraFrame(180, 30, 151));
    try std.testing.expectEqual(@as(?u32, null), auroraFrame(181, 30, 151));
}

test "the last frame is the last record's exact frame" {
    try std.testing.expectEqual(@as(u32, 508), lastFrame(255));
}
