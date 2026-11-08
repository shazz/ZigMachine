// The desk mode's reference for tests/tb/video_desk_tb.cpp: a synthetic plane 0 and palette 0,
// and the picture the MACHINE makes of them (machine/video_desk.zig, hwRenderDesk's two halves).
// The testbench plays the plane and palette into zm_video_out and compares the wire with these.
//
//   zig run --dep video_desk -Mroot=fpga/tools/desk_ref.zig -Mvideo_desk=machine/video_desk.zig \
//       -- <out dir> <FB_BASE>
//
// Writes plane.bin (640x480 bytes), pal.bin (256 RGBA words, little-endian) and desk.rgba (the two
// halves in order: 640x480 RGBA words). FB_BASE may be misaligned: the machine drops its low three bits.
const std = @import("std");
const desk = @import("video_desk");

/// A byte that names its lane in the beat (bits 7..5), walks a gradient across beats and lines
/// (bits 4..1) and flips on a one-pixel checker (bit 0): a byte from the wrong lane, beat, line or
/// column shows.
fn index(x: usize, y: usize) u8 {
    return @intCast((x % 8) * 32 + ((x / 8 + y) % 16) * 2 + ((x ^ y) & 1));
}

/// Every channel of every entry different from its neighbours', alpha arbitrary (the mode ignores it).
fn paletteWord(i: u32) u32 {
    const r = i;
    const g = (255 - i) ^ 0x33;
    const b = (i * 5 + 17) & 0xFF;
    return r | g << 8 | b << 16 | ((i * 3) & 0xFF) << 24;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const dir_path = args.next() orelse return error.Usage;
    const fb_base = try std.fmt.parseInt(u32, args.next() orelse return error.Usage, 0);
    const base = desk.baseOf(fb_base);

    const region = try gpa.alloc(u8, base + desk.W * desk.H);
    defer gpa.free(region);
    @memset(region, 0);
    for (0..desk.H) |y| for (0..desk.W) |x| {
        region[base + y * desk.W + x] = index(x, y);
    };
    var palette: [256]u32 = undefined;
    for (&palette, 0..) |*p, i| p.* = paletteWord(@intCast(i));
    const picture = try gpa.alloc(u32, desk.W * desk.H);
    defer gpa.free(picture);
    for (0..2) |half| desk.renderHalf(picture[half * desk.HALF_PIXELS ..].ptr, region.ptr, fb_base, &palette, @intCast(half));

    const io = init.io;
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{});
    defer dir.close(io);
    try dir.writeFile(io, .{ .sub_path = "plane.bin", .data = region[base..] });
    try dir.writeFile(io, .{ .sub_path = "pal.bin", .data = std.mem.sliceAsBytes(&palette) });
    try dir.writeFile(io, .{ .sub_path = "desk.rgba", .data = std.mem.sliceAsBytes(picture) });
}
