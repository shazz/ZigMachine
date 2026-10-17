// --------------------------------------------------------------------------
// Generator for mandelbrot/image.rle, the escape-time image of the Mandelbrot
// cart (400x280, one byte a pixel). It is the SAME loop as
// libs/zig/effects/mandelbrot.zig get_pixel_color (kept in step by hand; the
// scene_hash harness compares the cart against the old per-pixel maths), run
// once on the host instead of 8 M iterations on ZIGGY.
//
// The output is run-length coded per row: (run - 1, value) pairs, runs capped at
// 256, rows back to back (the cart knows each row has 400 pixels).
//
//   zig run apps/zig/scenes/mandelbrot/gen_mandelbrot.zig -- apps/zig/scenes/mandelbrot/image.rle
// --------------------------------------------------------------------------
const std = @import("std");

const W: usize = 400;
const H: usize = 280;
const MAX_ITER: u8 = 255;
const F_WIDTH: f32 = @as(f32, @floatFromInt(W));
const F_HEIGHT: f32 = @as(f32, @floatFromInt(H));

fn escapeTime(px: i32, py: i32) u8 {
    var iterations: u8 = 0;
    var x0 = @as(f32, @floatFromInt(px));
    var y0 = @as(f32, @floatFromInt(py));
    x0 = ((x0 / F_WIDTH) * 2.51) - 1.67;
    y0 = ((y0 / F_HEIGHT) * 2.24) - 1.12;
    var x: f32 = 0;
    var y: f32 = 0;
    var tmp: f32 = 0;
    var xsquare: f32 = 0;
    var ysquare: f32 = 0;
    while ((xsquare + ysquare < 4.0) and (iterations < MAX_ITER)) : (iterations += 1) {
        tmp = xsquare - ysquare + x0;
        y = 2 * x * y + y0;
        x = tmp;
        xsquare = x * x;
        ysquare = y * y;
    }
    return iterations;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.UsageOutPath;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (0..H) |y| {
        var row: [W]u8 = undefined;
        for (&row, 0..) |*p, x| p.* = escapeTime(@intCast(x), @intCast(y));
        var x: usize = 0;
        while (x < W) {
            var e = x + 1;
            while (e < W and e - x < 256 and row[e] == row[x]) e += 1;
            try out.append(gpa, @intCast(e - x - 1));
            try out.append(gpa, row[x]);
            x = e;
        }
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = out.items });
    std.debug.print("{} bytes\n", .{out.items.len});
}
