// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Demo = @import("demo.zig").Demo;

extern fn consoleLogJS(ptr: [*]const u8, len: usize) void;

fn consoleLog(s: []const u8) void {
    consoleLogJS(s.ptr, s.len);
}

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
const Resolution = @import("zigos.zig").Resolution;
const Color = @import("zigos.zig").Color;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var zigos: ZigOS = undefined;
var demo: Demo = undefined;

// --------------------------------------------------------------------------
// Exposed WASM functions
// --------------------------------------------------------------------------
export fn boot() void {

    consoleLog("ZigMachine is booting.....");

    zigos = ZigOS.create();
    zigos.init();
    if (Demo.init()) |aDemo| {
        demo = aDemo;
    } 
    else |_| {
        consoleLog("Demo.init failed");
    }
}

// The returned pointer will be used as an offset integer to the wasm memory
export fn getPhysicalFrameBufferPointer() [*]u8 {
    return @ptrCast([*]u8, &zigos.physical_framebuffer);
}

export fn renderPhysicalFrameBuffer(fb_id: u8) void {

    if (zigos.resolution == Resolution.truecolor) {

        // only one FB in truecolor
        if (fb_id == 0) {
            for (zigos.physical_framebuffer) |*row, y| {
                // can call a HBL handler here
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
    } else {
        // get logical framebuffer
        const s_fb: LogicalFB = zigos.lfbs[fb_id];
        const palfb: [WIDTH*HEIGHT]u8 = s_fb.fb;
        const palette: [256]Color = s_fb.palette;

        var i: u32 = 0;

        // can call a VBL handler here
        for (zigos.physical_framebuffer) |*row| {
            // can call a HBL handler here
            for (row) |*pixel| {

                const pal_entry: u8 = palfb[i];
                const pal_value: Color = palette[pal_entry];

                pixel.*[0] = pal_value.r;
                pixel.*[1] = pal_value.g;
                pixel.*[2] = pal_value.b;
                pixel.*[3] = pal_value.a;   

                i += 1;
            }
        }
    }

}

