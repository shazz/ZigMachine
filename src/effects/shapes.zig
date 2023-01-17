// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");

const LogicalFB = @import("../zigos.zig").LogicalFB;
const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("../zigos.zig").HEIGHT;
const WIDTH: usize = @import("../zigos.zig").WIDTH;

pub const Coord = struct {
    x: i16 = undefined,
    y: i16 = undefined,
};


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Drawline
// --------------------------------------------------------------------------
pub fn drawLine(fb: *LogicalFB, src: Coord, dest: Coord, color_entry: u8) void {

    var coord0: Coord = undefined;
    var coord1: Coord = undefined;
    
    if(dest.y < src.y) {
        // coord0 = Coord{ .x=@min(dest.x, @intCast(i16, WIDTH)), .y=@min(dest.y, @intCast(i16, HEIGHT))};
        coord0 = Coord{ .x=dest.x, .y=dest.y};
        coord1 = Coord{ .x=src.x, .y=src.y};
    } else {
        coord0 = Coord{ .x=src.x, .y=src.y};
        coord1 = Coord{ .x=dest.x, .y=dest.y};
    }

    // Console.log("coord 0: ({}, {})", .{coord0.x, coord0.y });
    // Console.log("coord 1: ({}, {})", .{coord1.x, coord1.y });

    // check limits

    var dx: i16 = undefined;
    var dy: i16 = undefined;

    var dp: i16 = undefined;
    var delta_e: i16 = undefined;
    var delta_ne: i16 = undefined;

    // check quadrant
    if(coord1.x >= coord0.x) {
        dx = coord1.x - coord0.x;
        dy = coord1.y - coord0.y;

        if(dx >= dy) {

            // y1 > y0 and x1 > x0 and dx >= dy
            dp = 2*dy - dx;
            delta_e = 2*dy;
            delta_ne = 2*(dy - dx);

            var x = coord0.x;
            var y = coord0.y;

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while(x < coord1.x){
                if(dp <= 0) {
                    dp += delta_e;
                    x += 1;
                } else {
                    dp += delta_ne;
                    x += 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
            } 
        } else {
            // y1 >= y0 and x1 >= x0 and dx < dy
            dp = 2*dx - dy;
            delta_e = 2*dx;
            delta_ne = 2*(dx-dy);

            var x = coord0.x;
            var y = coord0.y;

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while(y < coord1.y){
                if(dp <= 0) {
                    dp += delta_e;
                    y += 1;
                } else {
                    dp += delta_ne;
                    x += 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
            } 
        }
    } else {
        dx = coord0.x - coord1.x;
        dy = coord1.y - coord0.y;

        if(dx >= dy) {

            // y1 > y0 and x0 > x1 and dx >= dy
            dp = 2*dy - dx;
            delta_e = 2*dy;
            delta_ne = 2*(dy - dx);

            var x = coord0.x;
            var y = coord0.y;

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while(x > coord1.x){
                if(dp <= 0) {
                    dp += delta_e;
                    x -= 1;
                } else {
                    dp += delta_ne;
                    x -= 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            }         
        } else {

            // y1 > y0 and x0 > x1 and dx < dy
            dp = 2*dx - dy;
            delta_e = 2*dx;
            delta_ne = 2*(dx - dy); 

            var x = coord0.x;
            var y = coord0.y;

            fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);

            while(y < coord1.y){
                if(dp <= 0) {
                    dp += delta_e;
                    y += 1;
                } else {
                    dp += delta_ne;
                    x -= 1;
                    y += 1;
                }
                fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
                
            } 
        }

    }
}

pub fn fillPolygon(fb: *LogicalFB, vertices: []const Coord, color_entry: u8) void {

        var min_x: i16 = 0; //std.math.maxInt(i16);
        var min_y: i16 = 0; //std.math.maxInt(i16);
        var max_x: i16 = WIDTH-1; //std.math.minInt(i16);
        var max_y: i16 = HEIGHT-1; //std.math.minInt(i16);

        for (vertices) |pt| {
            min_x = std.math.min(min_x, pt.x);
            min_y = std.math.min(min_y, pt.y);
            max_x = std.math.max(max_x, pt.x);
            max_y = std.math.max(max_y, pt.y);
        }

        var y: i16 = min_y;
        while (y <= max_y) : (y += 1) {
            var x: i16 = min_x;
            while (x <= max_x) : (x += 1) {
                var inside = false;
                const p = Coord{ .x = x, .y = y };

                // free after https://stackoverflow.com/a/17490923

                var j = vertices.len - 1;
                for (vertices) |p0, i| {
                    defer j = i;
                    const p1 = vertices[j];

                    if ((p0.y > p.y) != (p1.y > p.y) and @intToFloat(f32, p.x) < @intToFloat(f32, (p1.x - p0.x) * (p.y - p0.y)) / @intToFloat(f32, (p1.y - p0.y)) + @intToFloat(f32, p0.x))
                    {
                        inside = !inside;
                    }
                }
                if (inside) {
                    if(x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT) {
                        fb.setPixelValue(@intCast(u16, x), @intCast(u16, y), color_entry);
                    }
                }
            }
        }
    }

