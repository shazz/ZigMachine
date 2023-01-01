
// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const RndGen = std.rand.DefaultPrng;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Fade = struct {

    fb: *LogicalFB = undefined,
    speed: i8 = undefined,
    use_alpha: bool = undefined,
    is_done: bool = undefined,
    first_pal_index: u8 = undefined,
    last_pal_index: u8 = undefined,

    pub fn init(fb: *LogicalFB, use_alpha: bool, first_pal_index: u8, last_pal_index: u8, fade_in_first: bool) Fade { 

        if (fade_in_first) {
            var counter: u8 = 0;
            while (counter < 16) : (counter += 1) {
                var pal_color: Color = fb.getPaletteEntry(counter);
                pal_color.a = 0;
                fb.setPaletteEntry(counter, pal_color);
            }
        }

        return .{ .fb=fb, .use_alpha=use_alpha, .is_done=false, .first_pal_index=first_pal_index, .last_pal_index=last_pal_index};
    }

    pub fn update(self: *Fade, fade_dir: bool) void {

        var counter: u8 = self.first_pal_index;
        while (counter <= self.last_pal_index) : (counter += 1) {
            var pal_color: Color = self.fb.getPaletteEntry(counter);

            if (self.use_alpha) {
                if (fade_dir) {
                    if (pal_color.a < 255) {
                        pal_color.a += 1;
                    }
                } else {
                    if (pal_color.a > 0) {
                        pal_color.a -= 1;
                    }
                }
            } else {
                if (fade_dir == false) {
                    if (pal_color.r > 0) {
                        pal_color.r -= 1;
                    }
                    if (pal_color.g > 0) {
                        pal_color.g -= 1; 
                    }                   
                    if (pal_color.b > 0) {
                        pal_color.b -= 1;
                    }
                } else{
                    Console.log("Not implemented yet", .{});
                }
            }            
          
            self.fb.setPaletteEntry(counter, pal_color);
        }
    }

    pub fn render(self: *Fade) void {
        _ = self;
    }

};


