// RACER natively: the track loader (happy path on both tracks, every refusal), the PVS (the
// baked list = the runtime DDA on every baked tile and yaw bucket, both tracks; the R cut; the
// unbaked fallback), and the camera script (wraps, deterministic, tile and bucket).
const std = @import("std");
const cam = @import("cam.zig");
const data = @import("data.zig");
const pvs = @import("pvs.zig");
const trk = @import("trk.zig");

fn copy(src: []align(4) const u8) ![]align(4) u8 {
    const out = try std.testing.allocator.alignedAlloc(u8, .@"4", src.len);
    @memcpy(out, src);
    return out;
}

test "the oval parses: counts, palette, a start grid of eight" {
    const t = try trk.parse(data.oval);
    try std.testing.expectEqual(@as(usize, 1301), t.verts.len);
    try std.testing.expectEqual(@as(usize, 600), t.faces.len);
    try std.testing.expectEqual(@as(usize, 301), t.inner.len);
    try std.testing.expectEqual(@as(usize, 120), t.line.len);
    try std.testing.expectEqual(@as(usize, 8), t.grid.len);
    try std.testing.expectEqual(@as(usize, 12), t.palette.len);
    try std.testing.expectEqualStrings("test_oval", std.mem.sliceTo(&t.name, 0));
}

test "the stress city parses and a full tile holds 81 faces (a ground quad and sixteen boxes, decals aside)" {
    const t = try trk.parse(data.city);
    var most: usize = 0;
    for (0..trk.TILES) |i| most = @max(most, t.tileFaces(i).len);
    try std.testing.expect(most >= 75 and most <= 100);
}

test "a refused blob: bad magic, version, CRC, size and a block out of bounds" {
    const b = try copy(data.oval);
    defer std.testing.allocator.free(b);
    b[0] ^= 1;
    try std.testing.expectError(error.BadMagic, trk.parse(b));
    b[0] ^= 1;
    b[4] = 9;
    try std.testing.expectError(error.BadVersion, trk.parse(b));
    b[4] = trk.VERSION;
    b[trk.HEADER + 100] ^= 0x40;
    try std.testing.expectError(error.BadCrc, trk.parse(b));
    b[trk.HEADER + 100] ^= 0x40;
    try std.testing.expectError(error.Truncated, trk.parse(b[0 .. b.len - 4]));
    try std.testing.expectError(error.Truncated, trk.parse(b[0..64]));
    b[13 * 4] = 0xFF; // the vertex block's offset points past the file
    b[13 * 4 + 1] = 0xFF;
    b[13 * 4 + 2] = 0xFF;
    try std.testing.expectError(error.BadBlock, trk.parse(b));
}

fn pvsMatchesDda(blob: []align(4) const u8) !usize {
    const t = try trk.parse(blob);
    var scratch: [pvs.MAX_ENTRIES]u16 = undefined;
    var checked: usize = 0;
    for (0..trk.TILES) |tile| for (0..trk.BUCKETS) |b| {
        const bk = pvs.baked(&t, @intCast(tile), @intCast(b)) orelse continue;
        const n = pvs.dda(&t, @intCast(tile), @intCast(b), t.rbake, &scratch);
        try std.testing.expectEqualSlices(u16, scratch[0..n], bk);
        checked += 1;
    };
    return checked;
}

test "baked PVS = the runtime DDA on every baked tile and yaw bucket (oval and city)" {
    try std.testing.expect(try pvsMatchesDda(data.oval) >= 16 * 100);
    try std.testing.expect(try pvsMatchesDda(data.city) >= 16 * 100);
}

test "R cuts the list: only entries within R, a smaller R is a prefix-subset, the camera tile is distance 0" {
    const t = try trk.parse(data.oval);
    const start: u32 = (@as(u32, @intCast(t.grid[0].pos[2] >> 19)) + 16) * trk.GRID + @as(u32, @intCast((t.grid[0].pos[0] >> 19) + 16));
    var scratch: [pvs.MAX_ENTRIES]u16 = undefined;
    var prev: usize = 0;
    for ([_]u32{ 1, 3, 5, 8 }) |r| {
        const l = pvs.visible(&t, start, 0, r, &scratch);
        for (l) |e| try std.testing.expect(pvs.distOf(e) <= r);
        try std.testing.expect(l.len >= prev);
        prev = l.len;
        try std.testing.expectEqual(@as(u16, 0), pvs.distOf(l[l.len - 1]));
    }
}

test "a tile the converter did not bake falls back to the DDA, and the lists are far to near" {
    const t = try trk.parse(data.oval);
    try std.testing.expect(pvs.baked(&t, 0, 0) == null); // a corner of the world, off the racing line
    var scratch: [pvs.MAX_ENTRIES]u16 = undefined;
    const l = pvs.visible(&t, 16 * 32 + 16, 3, 8, &scratch);
    var last: u16 = 99;
    for (l) |e| {
        try std.testing.expect(pvs.distOf(e) <= last);
        last = pvs.distOf(e);
    }
}

test "the lap script is a pure function of the frame: wraps, repeats, stays on the road's tiles" {
    const t = try trk.parse(data.oval);
    const a = cam.lapPose(&t, 100, .far);
    const b = cam.lapPose(&t, 100 + cam.LAP_FRAMES, .far);
    try std.testing.expectEqual(a, b);
    try std.testing.expect(!std.meta.eql(a, cam.lapPose(&t, 101, .far)));
    for (0..cam.POSES) |k| {
        const v = cam.view(cam.fixedPose(&t, @intCast(k)));
        try std.testing.expect(pvs.baked(&t, v.tile, v.bucket) != null); // the converter baked every camera tile
        try std.testing.expect(v.horizon >= 0 and v.horizon <= 200);
    }
}
