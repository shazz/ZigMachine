// Native tests for the BARD .kt player's core (kt_core.zig): `zig test` this file from the repo root.
//
// The pins are sha256 of upstream klystron's own render of the first 45 s of each bundled song,
// interleaved s16le stereo at 22050 Hz, from
//   make -C apps/ports/klystrack/kt_ref && apps/ports/klystrack/kt_ref/build/kt_ref docs/music/<song>.kt 45 --raw out
// (upstream cyd + music.c as the klystrack cart builds them: the song's channels, no oversampling,
// the cart's integer chorus LUT; kt_ref/Makefile has the one defined out-of-table read). The core is
// bit-exact against it: a pin moves only if the player or upstream's behaviour does.
const std = @import("std");
const kt = @import("kt_core.zig");
const rd = @import("kt_read.zig");

const SECONDS = 45;

const Pin = struct { song: []const u8, sha: []const u8 };
const pins = [_]Pin{
    .{ .song = "docs/music/starport2.kt", .sha = "fd83a9089664f7b902619bce63c063231f2dc0e6dd15f9237c5854b1ea2d4efe" },
    .{ .song = "docs/music/castlevania.kt", .sha = "c6dda9a8abc38ecc3156580a0d778067c7e5d4a8ad4596a301725083fabdb126" },
    .{ .song = "docs/music/oceanloader3.kt", .sha = "cb18d471add90a3369ae100250a1292a2bf065792ffdd0ebb5290bdf781a3cf0" },
    .{ .song = "docs/music/dpintro.kt", .sha = "ee798b13a10508a5c73ec8b98a808f7102580be43dccb5730b84c8b73dea95f5" },
};

fn readSong(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(1 << 20));
}

fn hex(digest: [32]u8) [64]u8 {
    var out: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{x}", .{&digest}) catch unreachable;
    return out;
}

test "every bundled song renders bit-exact against upstream cyd (kt_ref) for 45 s" {
    const gpa = std.testing.allocator;
    const mem = try gpa.alloc(u8, 1 << 20);
    defer gpa.free(mem);
    const core = try gpa.create(kt.Core);
    defer gpa.destroy(core);
    var block: [2 * 2000]i16 = undefined;
    for (pins) |p| {
        const data = try readSong(p.song);
        defer gpa.free(data);
        core.* = .{};
        try core.load(data, mem);
        try core.start(kt.RATE);
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        var left: usize = SECONDS * kt.RATE;
        while (left > 0) {
            const n: usize = @min(2000, left);
            core.render(block[0 .. 2 * n]);
            h.update(std.mem.sliceAsBytes(block[0 .. 2 * n]));
            left -= n;
        }
        const got = hex(h.finalResult());
        std.testing.expectEqualStrings(p.sha, &got) catch |e| {
            std.debug.print("{s}: not upstream's render\n", .{p.song});
            return e;
        };
    }
}

fn loadErr(data: []const u8) ?rd.Error {
    var mem: [1 << 16]u8 = undefined;
    var core: kt.Core = .{};
    core.load(data, &mem) catch |e| return e;
    return null;
}

test "files that are not a playable .kt are refused with their reason" {
    const gpa = std.testing.allocator;
    const good = try readSong("docs/music/castlevania.kt");
    defer gpa.free(good);
    try std.testing.expectEqual(@as(?rd.Error, error.NotKt), loadErr("cyd!inst\x1b"));
    try std.testing.expectEqual(@as(?rd.Error, error.NotKt), loadErr("cyd"));
    const bad = try gpa.dupe(u8, good);
    defer gpa.free(bad);
    bad[8] = 28; // a version from the future
    try std.testing.expectEqual(@as(?rd.Error, error.Version), loadErr(bad));
    bad[8] = 7; // before packed patterns
    try std.testing.expectEqual(@as(?rd.Error, error.Version), loadErr(bad));
    bad[8] = good[8];
    bad[9] = 17; // 17 channels
    try std.testing.expectEqual(@as(?rd.Error, error.TooManyChannels), loadErr(bad));
    try std.testing.expectEqual(@as(?rd.Error, error.Truncated), loadErr(good[0 .. good.len / 2]));
    try std.testing.expectEqual(@as(?rd.Error, null), loadErr(good));
}

test "a song whose tables do not fit its memory is refused, not written past it" {
    const gpa = std.testing.allocator;
    const data = try readSong("docs/music/dpintro.kt");
    defer gpa.free(data);
    var small: [4096]u8 = undefined;
    var core: kt.Core = .{};
    try std.testing.expectError(error.TooLarge, core.load(data, &small));
    // Loaded, but 3 reverb lines of 2 s do not fit 64 KB: start refuses.
    const mid = try gpa.alloc(u8, 1 << 16);
    defer gpa.free(mid);
    try core.load(data, mid);
    try std.testing.expectError(error.TooLarge, core.start(kt.RATE));
}
