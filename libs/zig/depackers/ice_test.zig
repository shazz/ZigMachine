// Robustness tests for the Pack-Ice depacker: everything about REFUSING an
// image, which is the half that has to be right for the machine's sake.
//
// Correctness on a real crunched file is proven end to end instead, by
// apps/sndh_headless.mjs against the D-BUG tune (Crystallized.sndh, 24 KB ->
// 103,978): a bit reader wrong by one bit anywhere yields garbage, so "it
// depacks to a tune the 68000 can then play" is a far stronger check than
// anything that can be hand-written here.
//
//   zig test libs/zig/depackers/ice_test.zig
const std = @import("std");
const ice = @import("ice.zig");

fn header(image: []u8, packed_len: u32, out_len: u32) void {
    @memcpy(image[0..4], "ICE!");
    std.mem.writeInt(u32, image[4..8], packed_len, .big);
    std.mem.writeInt(u32, image[8..12], out_len, .big);
}

test "a file that is not Pack-Ice is refused rather than guessed at" {
    var out: [64]u8 = undefined;
    const plain = "not packed, just a plain old file";
    try std.testing.expect(!ice.isPacked(plain));
    try std.testing.expect(ice.depackedLen(plain) == null);
    try std.testing.expect(ice.depack(plain, &out) == null);
}

test "both spellings of the magic are accepted" {
    var image = [_]u8{0} ** 32;
    header(&image, image.len, 16);
    try std.testing.expect(ice.isPacked(&image));
    @memcpy(image[0..4], "Ice!");
    try std.testing.expect(ice.isPacked(&image));
}

test "a header alone, with no room for a stream, is not an image" {
    var out: [64]u8 = undefined;
    var image = [_]u8{0} ** 11; // one byte short of a header
    try std.testing.expect(!ice.isPacked(&image));
    try std.testing.expect(ice.depack(&image, &out) == null);
}

test "the depacked length is readable without depacking" {
    var image = [_]u8{0} ** 32;
    header(&image, image.len, 0x1962A);
    try std.testing.expectEqual(@as(u32, 0x1962A), ice.depackedLen(&image).?);
}

test "a destination too small is refused, not overrun" {
    var image = [_]u8{0} ** 64;
    header(&image, image.len, 4096);
    var out: [16]u8 = undefined;
    try std.testing.expect(ice.depack(&image, &out) == null);
}

test "a header claiming more packed data than the file holds is refused" {
    var image = [_]u8{0} ** 64;
    header(&image, 4096, 32); // packed length past the end of the buffer
    var out: [64]u8 = undefined;
    try std.testing.expect(ice.depack(&image, &out) == null);
}

test "corrupt bits are refused rather than half-depacked" {
    var image = [_]u8{0} ** 256;
    header(&image, image.len, 4096);
    var out: [4096]u8 = undefined;
    // All-zero bits ask for matches reaching outside the output, and for more
    // packed bytes than exist. Either way: null, never a partial result.
    try std.testing.expect(ice.depack(&image, &out) == null);
}

test "a stream of all-ones bits is refused too" {
    var image = [_]u8{0xFF} ** 256;
    header(&image, image.len, 4096);
    var out: [4096]u8 = undefined;
    try std.testing.expect(ice.depack(&image, &out) == null);
}
