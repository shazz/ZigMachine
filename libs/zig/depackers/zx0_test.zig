// Round-trip and robustness tests for the ZX0 packer, container and depacker.
//
// Everything the packer writes must come back bit-exact through the depacker:
// synthetic edge cases plus real cart assets. The refusal half matters as much
// as the round trip: a corrupt or truncated image returns null and never reads
// or writes out of bounds, which a Debug test build would trap on.
//
//   zig test libs/zig/depackers/zx0_test.zig      (run from the repo root)
const std = @import("std");
const zx0 = @import("zx0.zig");
const zx0_pack = @import("zx0_pack.zig");

const gpa = std.testing.allocator;

fn roundTrip(input: []const u8) !void {
    const image = try zx0_pack.pack(gpa, input, .{});
    defer gpa.free(image);
    try expectDepacksTo(image, input);
}

fn expectDepacksTo(image: []const u8, input: []const u8) !void {
    try std.testing.expect(zx0.isPacked(image));
    try std.testing.expectEqual(@as(u32, @intCast(input.len)), zx0.depackedLen(image).?);
    const out = try gpa.alloc(u8, input.len);
    defer gpa.free(out);
    try std.testing.expectEqual(@as(?u32, @intCast(input.len)), zx0.depack(image, out));
    try std.testing.expectEqualSlices(u8, input, out);
}

fn depackInSteps(image: []const u8, out: []u8, step_size: u32) ?u32 {
    var s = zx0.Stream.init(image, out) orelse return null;
    while (true) switch (s.step(step_size)) {
        .more => {},
        .done => return s.written(),
        .failed => return null,
    };
}

fn readAsset(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(8 << 20));
}

test "empty input packs to a bare header and depacks to nothing" {
    const image = try zx0_pack.pack(gpa, "", .{});
    defer gpa.free(image);
    try std.testing.expectEqual(@as(usize, zx0.HEADER_LEN), image.len);
    var out: [1]u8 = undefined;
    try std.testing.expectEqual(@as(?u32, 0), zx0.depack(image, &out));
}

test "one byte" {
    try roundTrip("Z");
}

test "short text with repeats at the last offset and at new ones" {
    try roundTrip("abcabcabcXabcabcYYYYYYYYYYabcZZabcabcabc--abc");
}

test "a long run of one byte (overlapping matches, carried offsets)" {
    const buf = try gpa.alloc(u8, 70000);
    defer gpa.free(buf);
    @memset(buf, 0);
    try roundTrip(buf);
}

test "incompressible random bytes" {
    const buf = try gpa.alloc(u8, 50000);
    defer gpa.free(buf);
    var prng = std.Random.DefaultPrng.init(0x2A);
    prng.random().bytes(buf);
    try roundTrip(buf);
}

test "matches at the maximum offset" {
    const buf = try gpa.alloc(u8, zx0.MAX_OFFSET + 600);
    defer gpa.free(buf);
    var prng = std.Random.DefaultPrng.init(7);
    prng.random().bytes(buf);
    @memcpy(buf[zx0.MAX_OFFSET..][0..500], buf[0..500]);
    try roundTrip(buf);
}

test "real cart assets round-trip bit-exact" {
    const paths = [_][]const u8{
        "apps/zig/assets/screens/union_intro/trsi_turn.raw",
        "apps/zig/assets/screens/union_intro/trsi_turn_pal.dat",
        "apps/zig/assets/screens/ics/grid_large.raw",
        "apps/zig/assets/screens/stcs/font40x34_c1.raw",
        "apps/zig/assets/screens/union_intro/wab.raw",
        "apps/zig/assets/ym/raw/Cubase vs Notator.ymraw",
    };
    for (paths) |path| {
        const data = try readAsset(path);
        defer gpa.free(data);
        try roundTrip(data);
    }
}

// --- the depack effect in the header ---------------------------------------

test "every effect round-trips in the header, and the data does not change" {
    const input = "some asset bytes, some asset bytes, some asset bytes";
    const cases = [_]zx0_pack.Options{
        .{ .fx = .none },
        .{ .fx = .rasters },
        .{ .fx = .bar },
        .{ .fx = .text, .text = "DEPACKING THE TRSI LOGO..." },
        .{ .fx = .fade },
        .{ .fx = .noise },
        .{ .fx = .automation, .bars = 100 }, // Kick Off 2 (CODEF 168)
        .{ .fx = .automation, .bars = 30 }, // Elite Snooker (CODEF 422)
        .{ .fx = .automation, .bars = 0 },
    };
    for (cases) |options| {
        const image = try zx0_pack.pack(gpa, input, options);
        defer gpa.free(image);
        const h = zx0.parseHeader(image).?;
        try std.testing.expectEqual(options.fx, h.fx);
        try std.testing.expectEqualStrings(options.text, h.text);
        try std.testing.expectEqual(options.bars orelse 0, h.bars);
        try expectDepacksTo(image, input);
    }
}

test "the stream is byte-identical whichever effect is chosen" {
    const data = try readAsset("apps/zig/assets/screens/union_intro/wab.raw");
    defer gpa.free(data);
    const plain = try zx0_pack.pack(gpa, data, .{});
    defer gpa.free(plain);
    const text = try zx0_pack.pack(gpa, data, .{ .fx = .text, .text = "LOADING" });
    defer gpa.free(text);
    const fade = try zx0_pack.pack(gpa, data, .{ .fx = .fade });
    defer gpa.free(fade);
    const stream = plain[zx0.HEADER_LEN..];
    try std.testing.expectEqualSlices(u8, stream, fade[zx0.HEADER_LEN..]);
    try std.testing.expectEqualSlices(u8, stream, text[zx0.HEADER_LEN + 1 + 7 ..]);
    const out = try gpa.alloc(u8, data.len);
    defer gpa.free(out);
    try std.testing.expectEqual(@as(?u32, @intCast(data.len)), depackInSteps(text, out, 7));
    try std.testing.expectEqualSlices(u8, data, out);
}

test "the packer rejects a bad effect or message" {
    try std.testing.expect(zx0_pack.parseFx("sparkles") == null);
    try std.testing.expectEqual(zx0.Fx.fade, zx0_pack.parseFx("fade").?);
    try std.testing.expectEqual(zx0.Fx.noise, zx0_pack.parseFx("noise").?);
    try std.testing.expectEqual(zx0.Fx.automation, zx0_pack.parseFx("automation").?);
    try std.testing.expectError(error.TextNotAllowed, zx0_pack.pack(gpa, "a", .{ .fx = .automation, .bars = 100, .text = "HI" }));
    try std.testing.expectError(error.BarsRequired, zx0_pack.pack(gpa, "a", .{ .fx = .automation }));
    try std.testing.expectError(error.BarsNotAllowed, zx0_pack.pack(gpa, "a", .{ .fx = .bar, .bars = 30 }));
    try std.testing.expectError(error.TextNotAllowed, zx0_pack.pack(gpa, "a", .{ .fx = .noise, .text = "HI" }));
    const long = "X" ** (zx0.MAX_TEXT + 1);
    try std.testing.expectError(error.TextTooLong, zx0_pack.pack(gpa, "a", .{ .fx = .text, .text = long }));
    try std.testing.expectError(error.TextRequired, zx0_pack.pack(gpa, "a", .{ .fx = .text }));
    try std.testing.expectError(error.TextNotAllowed, zx0_pack.pack(gpa, "a", .{ .fx = .bar, .text = "HI" }));
    try std.testing.expectError(error.TextNotPrintable, zx0_pack.pack(gpa, "a", .{ .fx = .text, .text = "BAD\nLINE" }));
}

test "the depacker refuses an unknown effect, version or malformed message" {
    const input = "payload payload payload";
    var out: [64]u8 = undefined;
    const image = try zx0_pack.pack(gpa, input, .{ .fx = .text, .text = "HELLO" });
    defer gpa.free(image);

    image[5] = 9; // unknown fx
    try std.testing.expect(zx0.parseHeader(image) == null);
    try std.testing.expect(zx0.depack(image, &out) == null);
    image[5] = 7; // the first id past automation (6)
    try std.testing.expect(zx0.depack(image, &out) == null);
    // a header that stops where automation's bar-height byte should be
    try std.testing.expect(zx0.parseHeader(&[_]u8{ 'Z', 'X', '0', '!', zx0.VERSION, @intFromEnum(zx0.Fx.automation), 0, 0, 0, 0 }) == null);
    image[5] = @intFromEnum(zx0.Fx.text);

    image[4] = 2; // unknown version
    try std.testing.expect(zx0.depack(image, &out) == null);
    image[4] = zx0.VERSION;

    image[zx0.HEADER_LEN] = 0; // empty message
    try std.testing.expect(zx0.depack(image, &out) == null);
    image[zx0.HEADER_LEN] = zx0.MAX_TEXT + 1; // over-long message
    try std.testing.expect(zx0.depack(image, &out) == null);
    image[zx0.HEADER_LEN] = 5;

    image[zx0.HEADER_LEN + 2] = 0x07; // non-printable
    try std.testing.expect(zx0.depack(image, &out) == null);
    image[zx0.HEADER_LEN + 2] = 'E';

    try std.testing.expect(zx0.parseHeader(image[0 .. zx0.HEADER_LEN + 3]) == null); // text cut short
    try std.testing.expect(zx0.parseHeader(image[0..zx0.HEADER_LEN]) == null); // length byte missing
    try std.testing.expectEqual(@as(?u32, input.len), zx0.depack(image, &out));
}

// --- resumable stream --------------------------------------------------------

test "stepping with any budget gives exactly the one-shot result" {
    const data = try readAsset("apps/zig/assets/screens/union_intro/trsi_turn.raw");
    defer gpa.free(data);
    const image = try zx0_pack.pack(gpa, data, .{ .fx = .rasters });
    defer gpa.free(image);
    const once = try gpa.alloc(u8, data.len);
    defer gpa.free(once);
    const stepped = try gpa.alloc(u8, data.len);
    defer gpa.free(stepped);
    try std.testing.expectEqual(@as(?u32, @intCast(data.len)), zx0.depack(image, once));
    for ([_]u32{ 1, 7, 4096 }) |size| {
        @memset(stepped, 0xAA);
        try std.testing.expectEqual(@as(?u32, @intCast(data.len)), depackInSteps(image, stepped, size));
        try std.testing.expectEqualSlices(u8, once, stepped);
    }
}

test "a step never writes more than its budget, and done stays done" {
    const input = "abababababababababababab0123456789abababababab";
    const image = try zx0_pack.pack(gpa, input, .{});
    defer gpa.free(image);
    var out: [input.len]u8 = undefined;
    var s = zx0.Stream.init(image, &out).?;
    var last: u32 = 0;
    while (s.step(3) == .more) {
        try std.testing.expect(s.written() - last <= 3);
        last = s.written();
    }
    try std.testing.expectEqualSlices(u8, input, &out);
    try std.testing.expectEqual(zx0.Progress.done, s.step(100));
    try std.testing.expect(s.tokens > 1);
}

test "a truncated stream fails under stepping too, and stays failed" {
    const data = try readAsset("apps/zig/assets/screens/union_intro/wab.raw");
    defer gpa.free(data);
    const image = try zx0_pack.pack(gpa, data, .{});
    defer gpa.free(image);
    const out = try gpa.alloc(u8, data.len);
    defer gpa.free(out);
    for ([_]u32{ 1, 7, 4096 }) |size| {
        try std.testing.expect(depackInSteps(image[0 .. image.len / 2], out, size) == null);
    }
    var s = zx0.Stream.init(image[0 .. image.len / 2], out).?;
    while (s.step(4096) == .more) {}
    try std.testing.expectEqual(zx0.Progress.failed, s.step(4096));
}

// --- refusals ----------------------------------------------------------------

test "wrong magic is refused" {
    var out: [16]u8 = undefined;
    const plain = "ZX1!\x01\x00\x04\x00\x00\x00abcd";
    try std.testing.expect(!zx0.isPacked(plain));
    try std.testing.expect(zx0.depack(plain, &out) == null);
}

test "a destination too small is refused, not overrun" {
    const image = try zx0_pack.pack(gpa, "hello hello hello hello", .{});
    defer gpa.free(image);
    var out: [8]u8 = undefined;
    try std.testing.expect(zx0.depack(image, &out) == null);
}

test "a truncated stream is refused" {
    const data = try readAsset("apps/zig/assets/screens/union_intro/wab.raw");
    defer gpa.free(data);
    const image = try zx0_pack.pack(gpa, data, .{});
    defer gpa.free(image);
    const out = try gpa.alloc(u8, data.len);
    defer gpa.free(out);
    for ([_]usize{ zx0.HEADER_LEN, zx0.HEADER_LEN + 1, image.len / 2, image.len - 1 }) |cut| {
        try std.testing.expect(zx0.depack(image[0..cut], out) == null);
    }
}

test "a stated length that disagrees with the stream is refused" {
    const input = "the quick brown fox jumps over the lazy dog, the quick brown fox";
    const image = try zx0_pack.pack(gpa, input, .{});
    defer gpa.free(image);
    var out: [256]u8 = undefined;
    std.mem.writeInt(u32, image[6..10], input.len - 1, .little); // too small: stream overruns it
    try std.testing.expect(zx0.depack(image, &out) == null);
    std.mem.writeInt(u32, image[6..10], input.len + 1, .little); // too large: stream ends early
    try std.testing.expect(zx0.depack(image, &out) == null);
}

test "random corruption never reads or writes out of bounds" {
    const data = try readAsset("apps/zig/assets/screens/union_intro/wab.raw");
    defer gpa.free(data);
    const image = try zx0_pack.pack(gpa, data, .{});
    defer gpa.free(image);
    const out = try gpa.alloc(u8, data.len);
    defer gpa.free(out);
    const bad = try gpa.alloc(u8, image.len);
    defer gpa.free(bad);
    var prng = std.Random.DefaultPrng.init(99);
    const rnd = prng.random();
    for (0..400) |_| {
        @memcpy(bad, image);
        for (0..1 + rnd.uintLessThan(usize, 8)) |_| {
            const at = zx0.HEADER_LEN + rnd.uintLessThan(usize, image.len - zx0.HEADER_LEN);
            bad[at] = rnd.int(u8);
        }
        _ = zx0.depack(bad, out); // null or a (wrong) full length: either is fine, a trap is not
    }
}
