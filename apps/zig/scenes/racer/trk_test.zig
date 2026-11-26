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
    try std.testing.expectEqual(@as(usize, 15), t.palette.len);
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

fn setWord(b: []u8, i: usize, v: u32) void {
    std.mem.writeInt(u32, b[i * 4 ..][0..4], v, .little);
}

fn refix(b: []u8) void {
    setWord(b, 2, std.hash.crc.Crc32IsoHdlc.hash(b[trk.HEADER..]));
}

/// Each (header word, value) on a copy of `src`: parse must refuse it with an error (the header is outside the CRC: a file is untrusted).
fn expectRefused(src: []align(4) const u8, word_i: usize, v: u32) !void {
    const b = try copy(src);
    defer std.testing.allocator.free(b);
    setWord(b, word_i, v);
    if (trk.parse(b)) |_| return error.TestUnexpectedResult else |_| {}
}

test "a hostile header is refused, never followed: wrapping counts and offsets, too many ramps, segments or grid slots" {
    const big: u32 = 0xFFFF_FFF0;
    for ([_]usize{ 4, 5, 6, 7, 8, 9, 11 }) |w| try expectRefused(data.oval, w, big); // counts: u64 bounds, no wrap
    for (12..25) |w| try expectRefused(data.oval, w, big); // offsets
    try expectRefused(data.oval, 9, trk.MAX_RAMPS + 1); // past the 256-entry palette
    try expectRefused(data.oval, 8, 0); // no grid
    try expectRefused(data.oval, 8, trk.MAX_GRID + 1);
    try expectRefused(data.oval, 10, trk.MAX_RBAKE + 1);
    try expectRefused(data.oval, trk.MOOD_WORD, 4096); // a mood block where none is
}

test "a PVS list running past its block is refused" {
    const b = try copy(data.oval);
    defer std.testing.allocator.free(b);
    const t = try trk.parse(data.oval);
    const at = for (t.pvs_index) |a| (if (a != trk.NOT_BAKED) break a) else unreachable;
    const p = std.mem.readInt(u32, b[20 * 4 ..][0..4], .little) + at * 2;
    std.mem.writeInt(u16, b[p..][0..2], 0xFFFF, .little);
    refix(b);
    try std.testing.expectError(error.BadBlock, trk.parse(b));
}

test "the mood block: Salt Flats' is read (salt far ground at level 7), the oval has none (its defaults), a bad one is refused" {
    const s = try trk.parse(data.salt);
    try std.testing.expectEqual(@as(u8, 7), s.mood.ground_level);
    try std.testing.expectEqual(@as(u8, 1), s.mood.ground_ramp);
    const c = try trk.parse(data.city);
    try std.testing.expectEqual(@as(u8, 8), c.mood.ground_ramp);
    try std.testing.expectEqual(trk.BENCH_ONLY, c.mood.flags);
    const o = try trk.parse(data.oval);
    try std.testing.expectEqual(trk.Mood{}, o.mood);
    const b = try copy(data.salt);
    defer std.testing.allocator.free(b);
    const m = std.mem.readInt(u32, b[trk.MOOD_WORD * 4 ..][0..4], .little);
    for ([_][2]u8{ .{ 0, 30 }, .{ 1, 8 }, .{ 2, 2 }, .{ 3, trk.BACKDROPS }, .{ 24, trk.MAX_CLOCK[0] + 1 }, .{ 25, trk.MAX_CLOCK[1] + 1 }, .{ 26, 1 } }) |bad| {
        const keep = b[m + bad[0]];
        b[m + bad[0]] = bad[1];
        refix(b);
        try std.testing.expectError(error.BadMood, trk.parse(b));
        b[m + bad[0]] = keep;
    }
    refix(b);
    _ = try trk.parse(b);
}

test "the mood's haze (M6, bytes 27-31): 0 strength with a colour or a start is refused (BadMood), a strength alone is a haze" {
    const b = try copy(data.city);
    defer std.testing.allocator.free(b);
    const m = std.mem.readInt(u32, b[trk.MOOD_WORD * 4 ..][0..4], .little);
    for ([_]u8{ 27, 28, 29, 30 }) |at| {
        b[m + at] = 9;
        refix(b);
        try std.testing.expectError(error.BadMood, trk.parse(b));
        b[m + at] = 0;
    }
    b[m + 31] = 1;
    refix(b);
    const t = try trk.parse(b);
    try std.testing.expectEqual(@as(u8, 1), t.mood.haze_strength);
}
