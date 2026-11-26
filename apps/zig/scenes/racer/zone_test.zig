// RACER M5 finish: camera zones (zone.zig): the weight along a line with one roofed run, the flyby's far camera under it
// (cam.lapPose), the race's chase camera (pov.zoned), no zone on a track without roofs, and an unknown line flag refused.
// `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const cam = @import("cam.zig");
const data = @import("data.zig");
const pov = @import("pov.zig");
const trk = @import("trk.zig");
const zone = @import("zone.zig");

fn lineWithRoof(segs: *[20]trk.Seg, a: usize, b: usize) trk.Track {
    for (segs, 0..) |*s, i| s.* = .{ .pos = .{ @intCast(i << 18), 0, 0 }, .yaw = 0x4000, .segment = if (i >= a and i < b) zone.ROOF else 0 };
    var t = std.mem.zeroes(trk.Track);
    t.line = segs;
    return t;
}

test "the zone's weight: full on the roof and BEHIND segments past it, ramping over RAMP each side, none far off, smooth between" {
    var segs: [20]trk.Seg = undefined;
    const t = lineWithRoof(&segs, 8, 11); // a roof over segments 8, 9, 10
    const one: u32 = 1 << 16;
    const want = [_]u32{ 0, 0, 0, 0, 0, 0, one / 3, 2 * one / 3, one, one, one, one, one, 2 * one / 3, one / 3, 0, 0, 0, 0, 0 };
    for (want, 0..) |w, i| try std.testing.expectEqual(w, zone.at(&t, i));
    try std.testing.expectEqual(zone.at(&t, 6) + (zone.at(&t, 7) - zone.at(&t, 6)) / 2, zone.weight(&t, (6 << 16) + (1 << 15)));
    try std.testing.expectEqual(@as(u32, 0), zone.weight(&t, 19 << 16)); // it wraps: 19 -> 0, far from the roof
}

test "the flyby's far camera under a roof is the near one; elsewhere and on a track with no roof it is unchanged" {
    const oval = try trk.parse(data.oval);
    for (0..cam.LAP_FRAMES) |f| { // no roof on the oval: every pose as before the zones (its pins hold)
        const p = cam.lapPose(&oval, @intCast(f), .far);
        try std.testing.expectEqual(@as(u32, cam.PITCH[0]), p.pitch);
    }
    var segs: [20]trk.Seg = undefined;
    const t = lineWithRoof(&segs, 0, 20); // all roofed
    const p = cam.lapPose(&t, 100, .far);
    const n = cam.lapPose(&t, 100, .near);
    try std.testing.expectEqual(n.pitch, p.pitch);
    try std.testing.expectEqualSlices(i32, &n.pos, &p.pos);
}

test "the race's chase camera: the far POV blends to the near one under a roof, the cockpit never moves" {
    var segs: [20]trk.Seg = undefined;
    const t = lineWithRoof(&segs, 5, 6);
    const far = pov.offsets(.far, .far, pov.FRAMES);
    const near = pov.offsets(.near, .near, pov.FRAMES);
    const ck = pov.offsets(.cockpit, .cockpit, pov.FRAMES);
    try std.testing.expectEqualSlices(i32, &near, &pov.zoned(&t, .far, far, 5 << 16));
    try std.testing.expectEqualSlices(i32, &far, &pov.zoned(&t, .far, far, 15 << 16));
    try std.testing.expectEqualSlices(i32, &ck, &pov.zoned(&t, .cockpit, ck, 5 << 16));
    try std.testing.expectEqualSlices(i32, &near, &pov.zoned(&t, .far, far, (5 + 20 * 3) << 16)); // u unwrapped over laps
}

test "a racing-line flag the cart does not know is refused (BadBlock); a roof is accepted" {
    const b = try std.testing.allocator.alignedAlloc(u8, .@"4", data.oval.len);
    defer std.testing.allocator.free(b);
    @memcpy(b, data.oval);
    const line_at = std.mem.readInt(u32, b[21 * 4 ..][0..4], .little);
    const fix = struct {
        fn crc(x: []u8) void {
            std.mem.writeInt(u32, x[8..12], std.hash.crc.Crc32IsoHdlc.hash(x[trk.HEADER..]), .little);
        }
    };
    std.mem.writeInt(u16, b[line_at + 14 ..][0..2], zone.ROOF, .little);
    fix.crc(b);
    const t = try trk.parse(b);
    try std.testing.expectEqual(zone.ROOF, t.line[0].segment);
    std.mem.writeInt(u16, b[line_at + 14 ..][0..2], 2, .little);
    fix.crc(b);
    try std.testing.expectError(error.BadBlock, trk.parse(b));
}

test "the mood's draw distance cap: 0 (none) or 3..8 accepted, 1, 2 and 9 refused (BadMood)" {
    const b = try std.testing.allocator.alignedAlloc(u8, .@"4", data.salt.len);
    defer std.testing.allocator.free(b);
    @memcpy(b, data.salt);
    const at = std.mem.readInt(u32, b[trk.MOOD_WORD * 4 ..][0..4], .little);
    try std.testing.expectEqual(@as(u8, 0), (try trk.parse(b)).mood.draw_r); // the shipped Salt Flats: no cap
    for ([_]u8{ 1, 2, 3, 6, 8, 9 }) |r| {
        b[at + 26] = r;
        std.mem.writeInt(u32, b[8..12], std.hash.crc.Crc32IsoHdlc.hash(b[trk.HEADER..]), .little);
        if (r >= 3 and r <= 8) {
            try std.testing.expectEqual(r, (try trk.parse(b)).mood.draw_r);
        } else try std.testing.expectError(error.BadMood, trk.parse(b));
    }
}
