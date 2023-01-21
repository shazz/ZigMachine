// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const RenderTarget = @import("../zigos.zig").RenderTarget;
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
const GRADIENT_STEPS: u8 = 30;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub fn Starfield3D(
    comptime nb_stars: comptime_int,
) type {
    return struct {
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
        starfield_table: [nb_stars]Star = undefined,
        target: RenderTarget = undefined,
        width: f32 = undefined,
        height: f32 = undefined,
        speed: f32 = undefined,
        x: f32 = undefined,
        y: f32 = undefined,
        z: f32 = undefined,
        star_ratio: f32 = undefined,
        color_ratio: f32 = undefined,
        use_lines: bool = undefined,
        const Self = @This();

        pub fn init(target: RenderTarget, width: u16, height: u16, speed: f32, use_lines: bool) Self {

            var sf = Self{};
            sf.target = target;
            sf.rnd = RndGen.init(0);
            sf.width = @intToFloat(f32, width);
            sf.height = @intToFloat(f32, height);
            sf.speed = speed;
            sf.star_ratio = 100;
            sf.use_lines = use_lines;

            sf.x = sf.width / 2;
            sf.y = sf.height / 2;
            sf.z = (sf.width + sf.height) / 2;
            sf.color_ratio = 1 / sf.z;        


            switch (sf.target) {
                .fb => |fb| {
                    // Create palette with a alpha gradient of gray
                    fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
                    var i: u8 = 0;
                    while(i < 10) : (i += 1) {
                        fb.setPaletteEntry(i+1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 } );
                    }        
                    while(i < GRADIENT_STEPS) : (i += 1) {
                        fb.setPaletteEntry(i+1, Color{ .r = 255, .g = 255, .b = 255, .a = 255 - (i * (255/GRADIENT_STEPS-1)) } );
                    }
                },
                else => {}
            }

            // Add NB_STARS stars
            for (sf.starfield_table) |*star| {
                const x = sf.rnd.random().float(f32) * (sf.width * 1.0) - sf.x * 1.0;
                const y = sf.rnd.random().float(f32) * (sf.height * 1.0) - sf.y * 1.0;
                const z = sf.rnd.random().float(f32) * sf.z;

                star.* = Star{ 
                    .x = x, 
                    .y = y, 
                    .z = z,
                    .proj_x = 0,
                    .proj_y = 0
                };
            }

            return sf;
        }

        pub fn update(self: *Self) void {

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

        pub fn render(self: *Self) void {

            for (self.starfield_table) |*star| {

                if(star.prev_proj_x > 0 and star.prev_proj_x < self.width  and  star.prev_proj_y > 0 and star.prev_proj_y < self.height){

                    const pal_index = 1 + self.color_ratio * star.z * 1.2 * @intToFloat(f32, GRADIENT_STEPS-1);
                    // if(@floatToInt(u8, pal_index) < 3)
                    //     Console.log("{} => {}", .{pal_index, @floatToInt(u8, pal_index)});

                    if(self.use_lines){
                        const x0: i16 = @floatToInt(i16, star.prev_proj_x);
                        const y0: i16 = @floatToInt(i16, star.prev_proj_y);
                        const x1: i16 = @floatToInt(i16, star.proj_x);
                        const y1: i16 = @floatToInt(i16, star.proj_y);

                        if(x0 != x1 and y0 != y1) { 
                            const origin = Coord{ .x = x0, .y = y0 };
                            const dest = Coord{ .x =x1, .y = y1 };

                            shapes.drawLine(self.target, origin, dest, @floatToInt(u8, pal_index));  
                        }
                        else {
                            // don't draw lines for nothing
                            const x: u16 = @intCast(u16, x0);
                            const y: u16 = @intCast(u16, y0);
                            self.target.setPixelValue(x, y, @floatToInt(u8, pal_index));
                        }
                    } else {
                        const x: u16 = @floatToInt(u16, star.proj_x);
                        const y: u16 = @floatToInt(u16, star.proj_y);
                        self.target.setPixelValue(x, y, @floatToInt(u8, pal_index));   
                    }
                }
            }
        }
    };
}
