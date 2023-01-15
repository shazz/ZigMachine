// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const shapes = @import("shapes.zig");
const Coord = @import("shapes.zig").Coord;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const WIDTH: u16 = @import("../zigos.zig").WIDTH;
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;

// starfield
const NB_STARS: u32 = 400;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Starfield3D = struct {
    const Star = struct {
        x: f32 = undefined,
        y: f32 = undefined,
        z: f32 = undefined,
        proj_x: f32 = undefined,
        proj_y: f32 = undefined,
        prev_proj_x: f32 = undefined,
        prev_proj_y: f32 = undefined,
    };

    rnd: std.rand.DefaultPrng = undefined,
    starfield_table: [NB_STARS]Star = undefined,
    fb: *LogicalFB = undefined,
    width: f32 = undefined,
    height: f32 = undefined,
    speed: f32 = undefined,
    x: f32 = undefined,
    y: f32 = undefined,
    z: f32 = undefined,
    star_ratio: f32 = undefined,
    color_ratio: f32 = undefined,

    pub fn init(self: *Starfield3D, fb: *LogicalFB, width: u16, height: u16, speed: f32) void {
        self.fb = fb;
        self.rnd = RndGen.init(0);
        self.width = @intToFloat(f32, width);
        self.height = @intToFloat(f32, height);
        self.speed = speed;
        self.star_ratio = 100;

        self.x = self.width / 2;
        self.y = self.height / 2;
        self.z = (self.width + self.height) / 2;
        self.color_ratio = 1 / self.z;        

        // Create palette with a alpha gradient of gray
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        var i: u8 = 1;
        while(i < 50) : (i += 1) {
            fb.setPaletteEntry(i, Color{ .r = 255, .g = 255, .b = 255, .a = 255 - (i * (255/50)) } );
        }

        // Add NB_STARS stars
        for (self.starfield_table) |*star| {
            const x = self.rnd.random().float(f32) * (self.width  * 2) - self.x * 2;
            const y = self.rnd.random().float(f32) * (self.height * 2) - self.y * 2;
            const z = self.rnd.random().float(f32) * self.z;

            star.* = Star{ 
                .x = x, 
                .y = y, 
                .z = z,
                .proj_x = 0,
                .proj_y = 0
             };
        }
    }

    pub fn update(self: *Starfield3D) void {

        for (self.starfield_table) |*star| {
 
            star.*.prev_proj_x = star.proj_x;
            star.*.prev_proj_y = star.proj_y;

            // star.*.x -= .self.speed; 
            // star.*.y -= .self.speed; 
            star.*.z -= self.speed; 

            if(star.z > self.z) { 
                star.*.z -= self.z;
            } 
            if(star.z < 0) { 
                star.*.z += self.z;
            }

			star.*.proj_x = self.x + (star.x / star.z) * self.star_ratio;
			star.*.proj_y = self.y + (star.y / star.z) * self.star_ratio;            
        }
    }

    pub fn render(self: *Starfield3D) void {

        for (self.starfield_table) |*star| {

	        if(star.prev_proj_x > 0 and star.prev_proj_x < self.width  and  star.prev_proj_y > 0 and star.prev_proj_y < self.height){

                const pal_index = self.color_ratio * (star.z * 2) * 40;
                // Console.log("{} => {}", .{pal_index, @floatToInt(u8, pal_index)});

                // self.dest.contex.lineWidth=(1-self.star_color_ratio*self.star[i][2])*2;
                const x0: i16 = @floatToInt(i16, star.prev_proj_x);
                const y0: i16 = @floatToInt(i16, star.prev_proj_y);
                const x1: i16 = @floatToInt(i16, star.proj_x);
                const y1: i16 = @floatToInt(i16, star.proj_y);

                if(x0 != x1 and y0 != y1 ) { 
                    const origin = Coord{ .x = x0, .y = y0 };
                    const dest = Coord{ .x =x1, .y = y1 };

                    shapes.drawLine(self.fb, origin, dest, @floatToInt(u8, pal_index));  
                }
                else {
                    // don't draw lines for nothing
                    const x: u16 = @intCast(u16, x0);
                    const y: u16 = @intCast(u16, y0);
                    self.fb.setPixelValue(x, y, @floatToInt(u8, pal_index));
                }
			}
        }
    }
};
