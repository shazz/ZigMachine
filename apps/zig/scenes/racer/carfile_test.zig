// RACER: car files (carfile.zig): the built-in GT parses as a v1 file to the embedded model; a synthetic v2 set (two
// models, a palette) parses and assigns the AI cars in turn; every corruption is refused by name, never trapped on.
const std = @import("std");
const carfile = @import("carfile.zig");
const carmodel = @import("carmodel.zig");

const GT = @embedFile("../../assets/screens/racer/gt.kcar");

fn aligned(comptime n: usize, bytes: []const u8) [n]u8 {
    var b: [n]u8 = undefined;
    @memcpy(b[0..bytes.len], bytes);
    return b;
}

/// A v2 set: the GT twice (the second a shade apart: its first face's colour + 1) and a palette, the header's CRC right.
fn set(buf: []align(4) u8) []align(4) u8 {
    const h = carfile.HEADER;
    @memset(buf[0..h], 0);
    std.mem.writeInt(u32, buf[0..4], carfile.MAGIC, .little);
    std.mem.writeInt(u32, buf[4..8], 2, .little);
    std.mem.writeInt(u32, buf[8..12], 2, .little);
    std.mem.writeInt(u32, buf[12..16], carfile.PALETTE, .little);
    for (0..carfile.RAMPS) |i| buf[16 + i * 4 ..][0..3].* = .{ @intCast(i * 30), 100, 200 };
    @memcpy(buf[h..][0..GT.len], GT);
    @memcpy(buf[h + GT.len ..][0..GT.len], GT);
    const end = h + 2 * GT.len;
    std.mem.writeInt(u32, buf[44..48], std.hash.crc.Crc32IsoHdlc.hash(buf[h..end]), .little);
    return buf[0..end];
}

test "the built-in GT as a v1 car file: the embedded model, its parts, its middle, one model" {
    var b align(4) = aligned(GT.len, GT);
    const s = try carfile.parse(&b);
    try std.testing.expectEqual(@as(usize, 1), s.n);
    try std.testing.expect(s.palette == null);
    const m = s.of(5);
    try std.testing.expectEqual(carmodel.gt.end, m.end);
    try std.testing.expectEqual(carmodel.gt.wing_z, m.wing_z);
    try std.testing.expectEqual(carmodel.gt.mid_y, m.mid_y);
    try std.testing.expect(m.mid_y > 0);
    for (carmodel.gt.verts, m.verts) |a, c| try std.testing.expectEqual(a, c);
    try std.testing.expectEqual(carmodel.gt.faces.len, m.faces.len);
}

test "a v2 set: the palette, the player's model 0, the AI cars on models 1.. in turn" {
    var buf: [2 * GT.len + 64]u8 align(4) = undefined;
    const s = try carfile.parse(set(&buf));
    try std.testing.expectEqual(@as(usize, 2), s.n);
    try std.testing.expectEqual([3]u8{ 60, 100, 200 }, s.palette.?[2]);
    try std.testing.expect(s.of(0) == &s.models[0]);
    for (1..8) |k| try std.testing.expect(s.of(k) == &s.models[1]);
}

fn refused(b: []align(4) const u8, want: carfile.Error) !void {
    try std.testing.expectError(want, carfile.parse(b));
}

test "a corrupted car file is refused, never trapped on: every bound" {
    var buf: [2 * GT.len + 64]u8 align(4) = undefined;
    const good = set(&buf);
    var b: [2 * GT.len + 64]u8 align(4) = undefined;
    const n = good.len;
    // truncated anywhere: the header, a record, the last face
    try refused(@alignCast(good[0..32]), error.Truncated);
    for ([_]usize{ 64, 64 + 64, n - 32, n - 4 }) |cut| {
        @memcpy(b[0..cut], good[0..cut]);
        _ = carfile.parse(b[0..cut]) catch continue;
        return error.TestExpectedError;
    }
    // a header word, a flipped body byte (the CRC), a record's counts
    const Case = struct { at: usize, v: u32, want: carfile.Error };
    const cases = [_]Case{
        .{ .at = 0, .v = 0x12345678, .want = error.BadMagic },
        .{ .at = 4, .v = 3, .want = error.BadVersion },
        .{ .at = 8, .v = 0, .want = error.BadBlock },
        .{ .at = 8, .v = carfile.MAX_MODELS + 1, .want = error.BadBlock },
        .{ .at = 12, .v = 6, .want = error.BadBlock },
    };
    for (cases) |c| {
        @memcpy(&b, &buf);
        std.mem.writeInt(u32, b[c.at..][0..4], c.v, .little);
        try refused(b[0..n], c.want);
    }
    @memcpy(&b, &buf);
    b[n - 7] ^= 0x40;
    try refused(b[0..n], error.BadCrc);
}

/// The GT alone (v1) with one word or byte changed and its CRC made right again: the record's own checks.
fn patched(b: []align(4) u8, at: usize, v: u32) void {
    @memcpy(b, GT);
    std.mem.writeInt(u32, b[at..][0..4], v, .little);
    std.mem.writeInt(u32, b[44..48], std.hash.crc.Crc32IsoHdlc.hash(b[64..]), .little);
}

test "a v1 record's counts, part ends and faces are bounded (a right CRC does not let them through)" {
    var b: [GT.len]u8 align(4) = undefined;
    const nf = std.mem.readInt(u32, GT[12..16], .little);
    const vbytes = (std.mem.readInt(u32, GT[8..12], .little) * 6 + 3) / 4 * 4;
    patched(&b, 8, carfile.MAX_VERTS + 1); // vertices past the car cache
    try refused(&b, error.BadBlock);
    patched(&b, 12, nf + 1); // faces != the last part's end
    try refused(&b, error.BadBlock);
    patched(&b, 16 + 4, 0); // hull ends before the wheels (not monotonic)
    try refused(&b, error.BadParts);
    const first = 64 + vbytes; // the first face record: v[0] past the vertices, then nv 5
    patched(&b, first, 0xFFFF);
    try refused(&b, error.BadFace);
    patched(&b, first + 8, std.mem.readInt(u32, GT[first + 8 ..][0..4], .little) & 0xFFFF00FF | 5 << 8);
    try refused(&b, error.BadFace);
    // the shadow flag on a wheel face: two shadow faces
    patched(&b, first + 8, std.mem.readInt(u32, GT[first + 8 ..][0..4], .little) | carfile.FLAG_SHADOW);
    try refused(&b, error.BadParts);
}

test "the shadow is the footprint (R82 bug pass): several faces, the box around them is the model's foot, an empty shadow refused" {
    var b align(4) = aligned(GT.len, GT);
    const m = (try carfile.parse(&b)).of(0);
    const sh = m.range(.shadow);
    try std.testing.expect(sh.len > 1 and sh.len <= carfile.MAX_SHADOW);
    try std.testing.expectEqual(carmodel.gt.foot, m.foot);
    // the footprint holds the wheels (the near model's extent)
    for (m.range(.wheels)) |f| for (f.v[0..f.nv]) |id| {
        try std.testing.expect(m.verts[id][0] >= m.foot.x0 and m.verts[id][0] <= m.foot.x1);
        try std.testing.expect(m.verts[id][2] >= m.foot.z0 and m.verts[id][2] <= m.foot.z1);
    };
    var c: [GT.len]u8 align(4) = undefined;
    const e3 = std.mem.readInt(u32, GT[16 + 12 ..][0..4], .little);
    patched(&c, 16 + 16, e3); // the shadow part empty (its faces fall into the far model, flagged there)
    try refused(&c, error.BadParts);
}
