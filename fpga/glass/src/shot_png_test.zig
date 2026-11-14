// The screenshot's PNG writer (shot_png.zig) read back by an independent reader: the chunks
// walked and every CRC checked, the IDAT inflated by std's decompressor, the rows compared.
// (Checked once by hand too: Python's zlib/PIL open a glass PNG to the same pixels.)
const std = @import("std");
const png = @import("shot_png.zig");

const gpa = std.testing.allocator;

const Decoded = struct {
    w: u32,
    h: u32,
    kind: u8,
    pal: []u8,
    raw: []u8, // the inflated rows, filter bytes included

    fn deinit(d: Decoded) void {
        gpa.free(d.pal);
        gpa.free(d.raw);
    }
};

fn decode(file: []const u8) !Decoded {
    if (!std.mem.startsWith(u8, file, png.SIGNATURE)) return error.NoSignature;
    var idat: std.ArrayList(u8) = .empty;
    defer idat.deinit(gpa);
    var d = Decoded{ .w = 0, .h = 0, .kind = 0, .pal = try gpa.alloc(u8, 0), .raw = &.{} };
    errdefer gpa.free(d.pal);
    var at: usize = png.SIGNATURE.len;
    var ended = false;
    while (at < file.len) {
        const n = std.mem.readInt(u32, file[at..][0..4], .big);
        const tag = file[at + 4 ..][0..4];
        const body = file[at + 8 ..][0..n];
        const crc = std.mem.readInt(u32, file[at + 8 + n ..][0..4], .big);
        if (crc != std.hash.Crc32.hash(file[at + 4 .. at + 8 + n])) return error.BadCrc;
        if (std.mem.eql(u8, tag, "IHDR")) {
            d.w = std.mem.readInt(u32, body[0..4], .big);
            d.h = std.mem.readInt(u32, body[4..8], .big);
            if (body[8] != 8 or body[10] != 0 or body[11] != 0 or body[12] != 0) return error.BadHeader;
            d.kind = body[9];
        } else if (std.mem.eql(u8, tag, "PLTE")) {
            gpa.free(d.pal);
            d.pal = try gpa.dupe(u8, body);
        } else if (std.mem.eql(u8, tag, "IDAT")) {
            try idat.appendSlice(gpa, body);
        } else if (std.mem.eql(u8, tag, "IEND")) ended = true;
        at += 12 + n;
    }
    if (!ended or at != file.len) return error.NoEnd;
    var in: std.Io.Reader = .fixed(idat.items);
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var z: std.compress.flate.Decompress = .init(&in, .zlib, &window);
    d.raw = try z.reader.allocRemaining(gpa, .unlimited);
    return d;
}

/// The rows of `raw` without their filter bytes, each checked to be 0.
fn rows(raw: []const u8, row: usize, out: []u8) !void {
    const h = out.len / row;
    if (raw.len != h * (row + 1)) return error.BadLength;
    for (0..h) |y| {
        if (raw[y * (row + 1)] != 0) return error.BadFilter;
        @memcpy(out[y * row ..][0..row], raw[y * (row + 1) + 1 ..][0..row]);
    }
}

test "an RGB picture round-trips through an independent reader" {
    var px: [400 * 7 * 3]u8 = undefined;
    for (&px, 0..) |*b, i| b.* = @truncate(i *% 7 ^ i >> 5); // varied, so deflate has work to do
    const file = try png.encode(gpa, .{ .w = 400, .h = 7, .kind = .rgb, .px = &px });
    defer gpa.free(file);
    const d = try decode(file);
    defer d.deinit();
    try std.testing.expectEqual(@as(u32, 400), d.w);
    try std.testing.expectEqual(@as(u32, 7), d.h);
    try std.testing.expectEqual(@as(u8, 2), d.kind);
    var got: [px.len]u8 = undefined;
    try rows(d.raw, 400 * 3, &got);
    try std.testing.expectEqualSlices(u8, &px, &got);
}

test "an indexed picture carries its palette, and a flat screen compresses" {
    const px = try gpa.alloc(u8, 640 * 480);
    defer gpa.free(px);
    @memset(px, 3);
    px[0] = 1;
    px[px.len - 1] = 255;
    var pal: [768]u8 = undefined;
    for (&pal, 0..) |*b, i| b.* = @truncate(i);
    const file = try png.encode(gpa, .{ .w = 640, .h = 480, .kind = .indexed, .px = px, .pal = &pal });
    defer gpa.free(file);
    try std.testing.expect(file.len < 8 * 1024); // 300 KB of one colour: a few KB
    const d = try decode(file);
    defer d.deinit();
    try std.testing.expectEqual(@as(u8, 3), d.kind);
    try std.testing.expectEqualSlices(u8, &pal, d.pal);
    const got = try gpa.alloc(u8, px.len);
    defer gpa.free(got);
    try rows(d.raw, 640, got);
    try std.testing.expectEqualSlices(u8, px, got);
}

test "a known-good tiny PNG: one red pixel, byte for byte" {
    const file = try png.encode(gpa, .{ .w = 1, .h = 1, .kind = .rgb, .px = &.{ 255, 0, 0 } });
    defer gpa.free(file);
    // Signature and IHDR as every 1x1 RGB PNG has them (CRC 0x907753DE, the well-known one).
    const head = png.SIGNATURE ++ "\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xde";
    try std.testing.expectEqualSlices(u8, head, file[0..head.len]);
    try std.testing.expect(std.mem.endsWith(u8, file, "\x00\x00\x00\x00IEND\xae\x42\x60\x82"));
}

test "a picture whose size does not match its pixels is refused" {
    try std.testing.expectError(error.BadImage, png.encode(gpa, .{ .w = 2, .h = 2, .kind = .rgb, .px = &.{ 1, 2, 3 } }));
    try std.testing.expectError(error.BadImage, png.encode(gpa, .{ .w = 0, .h = 1, .kind = .rgb, .px = &.{} }));
    try std.testing.expectError(error.BadImage, png.encode(gpa, .{ .w = 1, .h = 1, .kind = .indexed, .px = &.{0} })); // no palette
}
