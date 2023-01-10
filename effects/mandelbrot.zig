// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;

const io = std.io;
const math = std.math;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").PHYSICAL_HEIGHT;
const WIDTH: usize = @import("../zigos.zig").PHYSICAL_WIDTH;

const MAX_ITER: u8 = 255;
const F_WIDTH: f32 = @intToFloat(f32, WIDTH);
const F_HEIGHT: f32 = @intToFloat(f32, HEIGHT);
// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Mandelbrot = struct {
    pfb: *[HEIGHT][WIDTH]u32 = undefined,

    pub fn init(self: *Mandelbrot, fb: *[HEIGHT][WIDTH]u32) void {
        self.pfb = fb;

        Console.log("fb: {}", .{@ptrToInt(self.pfb)});
    }

    pub fn update(self: *Mandelbrot) void {
        _ = self;
    }

    pub fn render(self: *Mandelbrot) void {
        for (self.pfb) |*row, y| {
            // can call a HBL handler here
            for (row) |*pixel, x| {
                const col: Color = Color{ .r = @intCast(u8, x), .g = @intCast(u8, y), .b = @intCast(u8, y), .a = 255 };
                pixel.* = col.toRGBA();
            }
        }

        // Copy bitmap data
        // var y: u16 = 0;
        // while (y < HEIGHT) : (y += 1) {
        //     var x: u16 = 0;
        //     while (x < WIDTH) : (x += 1) {
        //         const iter: u8 = get_pixel_color(x, y);
        //         const color: Color = Color{ .r = iter, .g = iter, .b = iter, .a = iter };
        //         self.pfb[x][y] = color.toRGBA();
        //     }
        // }
    }

    fn get_pixel_color(px: i32, py: i32) u8 {
        var iterations: u8 = 0;

        var x0 = @intToFloat(f32, px);
        var y0 = @intToFloat(f32, py);
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
        // smoothed valued
        //     return n + 1 - log(log2(abs(z)))
        // figure out import math first to get log/log2/abs
        return iterations;
    }
};
