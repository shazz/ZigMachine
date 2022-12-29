const std = @import("std");

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
const Resolution = enum { truecolor, planes };

const Color = struct {
    r: u8, g: u8, b: u8, a: u8
};

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------


// --------------------------------------------------------------------------
// Zig OS
// --------------------------------------------------------------------------
pub const ZigOS = struct {

    back_colors: [4]Color = [4]Color{ 
        Color{.r=0, .g=0, .b=0, .a=0}, 
        Color{.r=0, .g=0, .b=0, .a=0}, 
        Color{.r=0, .g=0, .b=0, .a=0}, 
        Color{.r=0, .g=0, .b=0, .a=0} 
        },
    resolution: Resolution = Resolution.truecolor,

    pub fn init() ZigOS {
        return .{};
    }

    pub fn nop() void {
        
    }

    pub fn setResolution(res: Resolution) void {
        self.resolution = res;
    }

    pub fn setFramebufferBackgroundColor(fb: u8, color: Color) void {
        self.back_colors[fb] = color;
    }

};