// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const Demo = @import("demo.zig").Demo;

extern fn consoleLog(arg: u32) void;

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
const Resolution = @import("zigos.zig").Resolution;
const Color = @import("zigos.zig").Color;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const fb_lines: usize = 320;
const fb_columns: usize = 200;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var physical_framebuffer = std.mem.zeroes([fb_columns][fb_lines][4]u8);
var zigos: ZigOS = undefined;
var demo: Demo = undefined;

// --------------------------------------------------------------------------
// Exposed WASM functions
// --------------------------------------------------------------------------

export fn boot() void {
    zigos = ZigOS.create();
    zigos.init() catch |err| {
       _ = err catch {};
    };
    demo = Demo.init(&zigos);
}

// The returned pointer will be used as an offset integer to the wasm memory
export fn getPhysicalFrameBufferPointer() [*]u8 {
    return @ptrCast([*]u8, &physical_framebuffer);
}

export fn vbl() void {

}

export fn renderPhysicalFrameBuffer(fb_id: u8) void {

    if (zigos.resolution == Resolution.truecolor) {
        for (physical_framebuffer) |*row, y| {
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
    } else {
        const palfb: *[64000]u8 = zigos.lfb[fb_id];
        var i: u32 = 0;

        for (physical_framebuffer) |*row| {
            for (row) |*pixel| {

                const pal_entry: u8 = palfb[i];
                const pal_value: Color = zigos.palette[pal_entry];
                // const pal_value: Color = Color{.r=35, .g=34, .b=35, .a=0};

                pixel.*[0] = pal_value.r;
                pixel.*[1] = pal_value.g;
                pixel.*[2] = pal_value.b;
                pixel.*[3] = pal_value.a;   

                i += 1;
            }
        }
    }

}

// Convert Palette FB to Physical Framebuffer
fn internalConvertLogicalFrameBuffers() void {
    for (zigos.lfb) |pal_entry, i| {
      _ = pal_entry;
      _ = i;
    }
}
