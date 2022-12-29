// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const Demo = @import("demo.zig").Demo;

extern fn consoleLog(arg: u32) void;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const fb_size: usize = 256;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var physicial_framebuffer = std.mem.zeroes([fb_size][fb_size][4]u8);
var zigos: ZigOS = undefined;
var demo: Demo = undefined;

// --------------------------------------------------------------------------
// Exposed WASM functions
// --------------------------------------------------------------------------

export fn boot() void {
    zigos = ZigOS.init();
    demo = Demo.init(&zigos);
}

// The returned pointer will be used as an offset integer to the wasm memory
export fn getPhysicialFrameBufferPointer() [*]u8 {
    return @ptrCast([*]u8, &physicial_framebuffer);
}

export fn vbl() void {

}

export fn renderPhysicialFrameBuffer(fb_id: u8) void {
    for (physicial_framebuffer) |*row, y| {
        for (row) |*pixel, x| {

            if (fb_id == 0) {
                pixel.*[0] = @intCast(u8, x);
                pixel.*[1] = @intCast(u8, y);
                pixel.*[2] = @intCast(u8, y);
                pixel.*[3] = 128;                
            } else {
                pixel.*[0] = @intCast(u8, y);
                pixel.*[1] = @intCast(u8, x);
                pixel.*[2] = @intCast(u8, y);
                pixel.*[3] = 128;                
            }

        }
    }
}

fn convertLogicalFrameBuffers(    
) void {

}
