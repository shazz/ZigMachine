// A PNG of a screenshot (app_shot.zig): 8-bit RGB, or 8-bit indexed with its palette (the desk),
// filter 0 on every row, the IDAT one zlib stream from std's deflate (std.compress.flate.Compress).
// No dependency beyond std: the board's glass is one static binary.
const std = @import("std");
const flate = std.compress.flate;

pub const SIGNATURE = "\x89PNG\r\n\x1a\n";

/// IHDR's colour type.
pub const Kind = enum(u8) { rgb = 2, indexed = 3 };

pub const Image = struct {
    w: u32,
    h: u32,
    kind: Kind,
    px: []const u8, // rgb: R, G, B a pixel; indexed: one palette index a pixel; rows top-down, packed
    pal: []const u8 = &.{}, // indexed: R, G, B an entry, 1..256 entries

    pub fn rowBytes(self: Image) usize {
        return @as(usize, self.w) * @as(usize, if (self.kind == .rgb) 3 else 1);
    }
};

pub const Error = error{ BadImage, OutOfMemory, WriteFailed };

/// The whole file, owned by the caller.
pub fn encode(gpa: std.mem.Allocator, img: Image) Error![]u8 {
    if (img.w == 0 or img.h == 0 or img.px.len != img.rowBytes() * img.h) return error.BadImage;
    if (img.kind == .indexed and (img.pal.len == 0 or img.pal.len > 768 or img.pal.len % 3 != 0)) return error.BadImage;
    const idat = try deflate(gpa, img);
    defer gpa.free(idat);
    var out = try std.Io.Writer.Allocating.initCapacity(gpa, idat.len + 1024);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(SIGNATURE);
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], img.w, .big);
    std.mem.writeInt(u32, ihdr[4..8], img.h, .big);
    ihdr[8..13].* = .{ 8, @intFromEnum(img.kind), 0, 0, 0 }; // depth 8, deflate, filter set 0, no interlace
    try chunk(w, "IHDR", &ihdr);
    if (img.kind == .indexed) try chunk(w, "PLTE", img.pal);
    try chunk(w, "IDAT", idat);
    try chunk(w, "IEND", "");
    return out.toOwnedSlice();
}

fn chunk(w: *std.Io.Writer, tag: *const [4]u8, body: []const u8) error{WriteFailed}!void {
    try w.writeInt(u32, @intCast(body.len), .big);
    try w.writeAll(tag);
    try w.writeAll(body);
    var crc = std.hash.Crc32.init();
    crc.update(tag);
    crc.update(body);
    try w.writeInt(u32, crc.final(), .big);
}

/// The rows, each after its filter byte (0: none), as one zlib stream.
fn deflate(gpa: std.mem.Allocator, img: Image) Error![]u8 {
    var z = try std.Io.Writer.Allocating.initCapacity(gpa, 64 * 1024);
    errdefer z.deinit();
    const c = try gpa.create(flate.Compress); // ~224 KiB of tables: never on a thread's stack
    defer gpa.destroy(c);
    const window = try gpa.alloc(u8, flate.max_window_len);
    defer gpa.free(window);
    c.* = try flate.Compress.init(&z.writer, window, .zlib, .level_4);
    const n = img.rowBytes();
    for (0..img.h) |y| {
        try c.writer.writeByte(0);
        try c.writer.writeAll(img.px[y * n ..][0..n]);
    }
    try c.finish();
    return z.toOwnedSlice();
}
