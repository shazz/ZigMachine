// swm_test.zig — byte-exact round-trips of the real tunes through load/save,
// plus the C64 workfile image path (load → toC64 → fromC64 → save must be
// byte-identical too), a stability check for blank tunes, and the error paths
// that ProcessSWMver1's bounds make reachable.

const std = @import("std");
const swm = @import("swm.zig");

const t_flash = @embedFile("tunes/FLASHITBACK.SWM");

const all_tunes = .{
    .{ "FLASHITBACK", t_flash },
};

fn expectRoundTrip(data: []const u8) !void {
    var song: swm.Song = .{};
    try swm.load(&song, data);

    // save re-derives the same stream length the file already carries, so the
    // file's slice is exactly big enough for the packed result
    const out = try std.testing.allocator.alloc(u8, data.len);
    defer std.testing.allocator.free(out);
    const n = try swm.save(&song, out);
    try std.testing.expectEqual(data.len, n);
    try std.testing.expectEqualSlices(u8, data, out[0..n]);

    // the C64 workfile image feeds back the identical tune body; it has no
    // loadaddr (a num built image sits at MUSICDATA), so compare body only
    var img: [swm.music_len]u8 = undefined;
    try swm.toC64(&song, &img);
    var back: swm.Song = .{};
    try swm.fromC64(&back, &img);
    const n2 = try swm.save(&back, out);
    try std.testing.expectEqual(data.len, n2);
    try std.testing.expectEqualSlices(u8, data[2..], out[2..n2]);
}

test "round-trip each tune byte-identical (file and C64-image paths)" {
    var failures: u32 = 0;
    inline for (all_tunes) |entry| {
        expectRoundTrip(entry[1]) catch |err| {
            failures += 1;
            std.debug.print("FAIL {s}: {s}\n", .{ entry[0], @errorName(err) });
        };
    }
    try std.testing.expectEqual(@as(u32, 0), failures);
}

test "blank tune is stable through reset/save/image/save" {
    var song: swm.Song = .{};
    swm.reset(&song);

    var out1: [512]u8 = undefined;
    const n1 = try swm.save(&song, &out1);
    try std.testing.expect(n1 > 0);

    var img: [swm.music_len]u8 = undefined;
    try swm.toC64(&song, &img);
    var back: swm.Song = .{};
    try swm.fromC64(&back, &img);
    var out2: [512]u8 = undefined;
    const n2 = try swm.save(&back, &out2);

    try std.testing.expectEqual(n1, n2);
    try std.testing.expectEqualSlices(u8, out1[0..n1], out2[0..n2]);
    // blank memory recomputes to all-zero counts (chord0 $7F is not a chord)
    try std.testing.expectEqual(@as(u8, 0), out1[2 + swm.H_SEQAMO]);
    try std.testing.expectEqual(@as(u8, 0), out1[2 + swm.H_PTAMOU]);
    try std.testing.expectEqual(@as(u8, 0), out1[2 + swm.H_INSTAM]);
    try std.testing.expectEqual(@as(u8, 0), out1[2 + swm.H_CHRDLE]);
    try std.testing.expectEqual(@as(u8, 0), out1[2 + swm.H_TMPLEN]);
}

test "TooShort: a file without the header" {
    var song: swm.Song = .{};
    try std.testing.expectError(error.TooShort, swm.load(&song, "SW"));
    try std.testing.expectError(error.TooShort, swm.load(&song, "SWM1"));
}

test "BadId: wrong magic in TUNEHEADER" {
    const bad = "SWX1" ++ [_]u8{0} ** 60 ++ [_]u8{ 0xFE, 1 };
    var song: swm.Song = .{};
    try std.testing.expectError(error.BadId, swm.load(&song, bad[0..]));
}

test "BadCount: header count beyond the tables" {
    var bad: [66]u8 = @splat(0);
    @memcpy(bad[2..6], "SWM1");
    bad[2 + swm.H_SEQAMO] = swm.seq_slots + 1; // 25 orderlists don't exist
    var song: swm.Song = .{};
    try std.testing.expectError(error.BadCount, swm.load(&song, &bad));
}

test "BadSize: pattern with size byte 0" {
    // header claims one pattern; stream sends a size byte 0 for pattern 1
    var bad: [76]u8 = @splat(0);
    @memcpy(bad[2..6], "SWM1");
    bad[2 + swm.H_PTAMOU] = 1;
    bad[66] = 32; // length byte
    bad[67] = 0; // size byte: nonsense
    var song: swm.Song = .{};
    try std.testing.expectError(error.BadSize, swm.load(&song, &bad));
}

test "Truncated: stream runs into the TUNEHEADER" {
    const data = t_flash;
    const cut = 2 + swm.header_size; // stream fully missing
    var song: swm.Song = .{};
    try std.testing.expectError(error.Truncated, swm.load(&song, data[0..cut]));
}

test "NoRoom: output buffer too small for the packtun result" {
    var song: swm.Song = .{};
    try swm.load(&song, t_flash);
    var small: [16]u8 = undefined;
    try std.testing.expectError(error.NoRoom, swm.save(&song, &small));
}
