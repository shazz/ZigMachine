const std = @import("std");

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
pub const Resolution = enum { truecolor, planes };

pub const Color = struct {
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
    lfb: [4]*[64000]u8 = undefined,
    palette: [256]Color = undefined,

    pub fn create() ZigOS {
        return .{};
    }

    pub fn init(self: *ZigOS) error{OutOfMemory}!void {
        self.resolution = Resolution.planes;

        for (self.palette) |_, i| {
            self.palette[i] = Color{.r=0, .g=@intCast(u8, i), .b=@intCast(u8, i), .a=255};
        }

        // get allocator
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        // allocate memory
        var memory = try allocator.create([64000]u8);       

        // write dummy pixels
        var i: usize = 0;
        while (i <= 64000) : (i += 1) {
            memory[i] = 2;
        }
        // for (memory) | _, i | {
        //     memory[i] = 1;
        // }
        self.lfb[0] = memory;
    }

    pub fn setFrameBufferAddress(self: *ZigOS, fb_nb: u8, addr: *u32) void {
        self.lfb[fb_nb] = addr;
    }

    pub fn nop(self: *ZigOS) void {
        _ = self;
    }

    pub fn setResolution(self: *ZigOS, res: Resolution) void {
        self.resolution = res;
    }

    pub fn setFramebufferBackgroundColor(self: *ZigOS, fb: u8, color: Color) void {
        self.back_colors[fb] = color;
    }

};