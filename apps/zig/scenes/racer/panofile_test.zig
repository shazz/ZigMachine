// RACER: the panorama file (panofile.zig, R82 32X look item 1): a synthetic strip parsed, and every refusal: magic,
// version, CRC, size, colours (range, the car ramps), a texel off its entries, OPAQUE with a clear texel, and a
// panorama whose entries a track's faces use (clash). `zig test apps/zig/racer_tests.zig`.
const std = @import("std");
const data = @import("data.zig");
const pf = @import("panofile.zig");
const trk = @import("trk.zig");

const W = 256;
const ROWS = 8;
const NC = 4;
const LEN = pf.HEADER + 4 * NC + W * ROWS;

/// A valid panorama: 4 colours from entry `first`, rows of colour 1 + row % 4, a clear top row unless OPAQUE.
pub fn make(buf: *[LEN]u8, first: u8, opaque_: bool) []u8 {
    @memset(buf, 0);
    std.mem.writeInt(u32, buf[0..4], pf.MAGIC, .little);
    std.mem.writeInt(u32, buf[4..8], pf.VERSION, .little);
    std.mem.writeInt(u32, buf[8..12], LEN, .little);
    std.mem.writeInt(u16, buf[16..18], W, .little);
    std.mem.writeInt(u16, buf[18..20], ROWS, .little);
    std.mem.writeInt(u16, buf[20..22], 6, .little);
    std.mem.writeInt(u16, buf[22..24], 17, .little);
    buf[24] = NC;
    buf[25] = first;
    buf[26] = if (opaque_) pf.OPAQUE else 0;
    for (0..NC) |k| buf[pf.HEADER + 4 * k ..][0..3].* = .{ @intCast(40 * k), 90, 200 };
    for (0..ROWS) |r| @memset(buf[pf.HEADER + 4 * NC + r * W ..][0..W], if (r == 0 and !opaque_) 0 else first + @as(u8, @intCast(r % NC)));
    return seal(buf);
}

fn seal(buf: *[LEN]u8) []u8 {
    std.mem.writeInt(u32, buf[12..16], std.hash.crc.Crc32IsoHdlc.hash(buf[pf.HEADER..]), .little);
    return buf;
}

test "a panorama file parsed: its size, horizon, yaw offset, colours, and its texels in place" {
    var buf: [LEN]u8 = undefined;
    const p = try pf.parse(make(&buf, 200, false));
    try std.testing.expectEqual(@as(u32, W), p.width);
    try std.testing.expectEqual(@as(u32, ROWS), p.rows);
    try std.testing.expectEqual(@as(u32, 6), p.horizon);
    try std.testing.expectEqual(@as(u32, 17), p.u0);
    try std.testing.expectEqual(@as(usize, NC), p.colours.len);
    try std.testing.expectEqual([4]u8{ 40, 90, 200, 0 }, p.colours[1]);
    try std.testing.expect(!p.opaque_ and p.texels.len == W * ROWS and p.texels[0] == 0 and p.texels[W] == 201);
    try std.testing.expect(p.owns(203) and !p.owns(204) and !p.owns(199));
    try std.testing.expect((try pf.parse(make(&buf, 200, true))).opaque_);
}

test "a bad panorama file is refused by name: magic, version, CRC, length, size, colours, texels" {
    var buf: [LEN]u8 = undefined;
    const Case = struct { at: usize, v: u8, want: pf.Error };
    const cases = [_]Case{
        .{ .at = 0, .v = 'X', .want = error.BadMagic },
        .{ .at = 4, .v = 2, .want = error.BadVersion },
        .{ .at = 16, .v = 0x40, .want = error.BadSize }, // width 320: not a power of two
        .{ .at = 19, .v = 1, .want = error.BadSize }, // 264 rows
        .{ .at = 21, .v = 1, .want = error.BadSize }, // the horizon past the rows
        .{ .at = 23, .v = 1, .want = error.BadSize }, // u0 past the width
        .{ .at = 26, .v = 2, .want = error.BadSize }, // an unknown flag
        .{ .at = 24, .v = 0, .want = error.BadColours },
        .{ .at = 25, .v = 120, .want = error.BadColours }, // on the car ramps
        .{ .at = 25, .v = 254, .want = error.BadColours }, // past entry 255
        .{ .at = 25, .v = 8, .want = error.BadColours }, // the fixed entries
        .{ .at = pf.HEADER + 4 * NC + 3 * W, .v = 9, .want = error.BadTexel },
    };
    for (cases) |c| {
        _ = make(&buf, 200, false);
        buf[c.at] = c.v;
        try std.testing.expectError(c.want, pf.parse(seal(&buf)));
    }
    _ = make(&buf, 200, false);
    buf[LEN - 1] ^= 1;
    try std.testing.expectError(error.BadCrc, pf.parse(&buf)); // not resealed
    try std.testing.expectError(error.Truncated, pf.parse(make(&buf, 200, false)[0 .. LEN - 1]));
    try std.testing.expectError(error.Truncated, pf.parse(buf[0..10]));
    _ = make(&buf, 200, true);
    buf[pf.HEADER + 4 * NC] = 0; // a clear texel in an OPAQUE strip
    try std.testing.expectError(error.BadTexel, pf.parse(seal(&buf)));
}

test "a panorama whose entries the track's faces use, or past its ramps, clashes; free ones do not" {
    var buf: [LEN]u8 = undefined;
    const t = try trk.parse(data.salt);
    const used = t.faces[0].colour;
    try std.testing.expect(used >= 16);
    try std.testing.expectError(error.Clash, pf.clash(&(try pf.parse(make(&buf, used - 1, false))), &t));
    const past: u8 = @intCast(@min(16 + 8 * t.palette.len, 252));
    if (past + NC > 16 + 8 * t.palette.len) try std.testing.expectError(error.Clash, pf.clash(&(try pf.parse(make(&buf, past, false))), &t));
    var free: ?u8 = null; // four entries on the track's ramps, off the car ramps, no face or decal on them
    var e: u32 = 16;
    while (e + NC <= 16 + 8 * t.palette.len) : (e += 1) {
        if (e < pf.CAR_HI and e + NC > pf.CAR_LO) continue;
        const p = try pf.parse(make(&buf, @intCast(e), false));
        if (pf.clash(&p, &t)) |_| {
            free = @intCast(e);
            break;
        } else |_| {}
    }
    try std.testing.expect(free != null);
}
