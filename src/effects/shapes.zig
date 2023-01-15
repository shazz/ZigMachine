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

