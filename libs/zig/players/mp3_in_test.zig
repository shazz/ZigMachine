const std = @import("std");
const in = @import("mp3_in.zig");

const HDR = [4]u8{ 0xFF, 0xFB, 0x90, 0x00 }; // 417 bytes: MPEG-1 128k 44.1 kHz stereo

fn frames(comptime n: usize) [417 * n]u8 {
    var b = [_]u8{0} ** (417 * n);
    for (0..n) |k| @memcpy(b[417 * k ..][0..4], &HDR);
    return b;
}

test "a frame confirmed by the next header is cut whole" {
    var mem: [4096]u8 = undefined;
    var r = in.Ring{ .buf = &mem };
    const two = frames(2);
    r.write(&two);
    var pending: u32 = 0;
    try std.testing.expectEqual(in.Cut{ .frame = 417 }, in.cut(&r, false, false, &pending));
}

test "an unconfirmed first frame waits, unless the input has ended" {
    var mem: [4096]u8 = undefined;
    var r = in.Ring{ .buf = &mem };
    const one = frames(1);
    r.write(&one);
    var pending: u32 = 0;
    try std.testing.expectEqual(in.Cut.wait, in.cut(&r, false, false, &pending));
    try std.testing.expectEqual(in.Cut{ .frame = 417 }, in.cut(&r, false, true, &pending));
}

test "an ID3 tag is skipped across feeds, then the frame is found" {
    var mem: [4096]u8 = undefined;
    var r = in.Ring{ .buf = &mem };
    r.write(&.{ 'I', 'D', '3', 3, 0, 0, 0, 0, 0, 20 }); // a 20-byte body
    var pending: u32 = 0;
    try std.testing.expectEqual(in.Cut.skipped, in.cut(&r, false, false, &pending));
    try std.testing.expectEqual(@as(u32, 30), pending);
    try std.testing.expectEqual(in.Cut.skipped, in.cut(&r, false, false, &pending));
    r.write(&([_]u8{0} ** 20));
    _ = in.cut(&r, false, false, &pending);
    try std.testing.expectEqual(@as(u32, 0), pending);
    const two = frames(2);
    r.write(&two);
    try std.testing.expectEqual(in.Cut{ .frame = 417 }, in.cut(&r, false, false, &pending));
}

test "garbage before the sync is skipped a byte at a time" {
    var mem: [4096]u8 = undefined;
    var r = in.Ring{ .buf = &mem };
    r.write(&.{ 1, 2 });
    const two = frames(2);
    r.write(&two);
    var pending: u32 = 0;
    try std.testing.expectEqual(in.Cut.skipped, in.cut(&r, false, false, &pending));
    try std.testing.expectEqual(in.Cut.skipped, in.cut(&r, false, false, &pending));
    try std.testing.expectEqual(in.Cut{ .frame = 417 }, in.cut(&r, false, false, &pending));
}

test "an overfed ring drops and counts the excess, and wraps" {
    var mem: [8]u8 = undefined;
    var r = in.Ring{ .buf = &mem };
    r.write(&.{ 1, 2, 3, 4, 5, 6 });
    r.skip(4);
    r.write(&.{ 7, 8, 9, 10, 11, 12, 13 });
    try std.testing.expectEqual(@as(u32, 8), r.fill());
    try std.testing.expectEqual(@as(u32, 1), r.dropped);
    try std.testing.expectEqual(@as(u8, 5), r.at(0));
    try std.testing.expectEqual(@as(u8, 12), r.at(7));
}
